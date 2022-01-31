// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MarketLibrary.sol";
import "./OptionVault.sol";
import "./interfaces/EOption.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ILendingPoolAddressesProvider.sol";
import "./interfaces/ILendingPool.sol";

contract MoretMarketMaker is ERC20, AccessControl, EOption{
  using FullMath for uint256;
  using MarketLibrary for uint256;
  
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  uint256 internal constant BASE = 1e18;

  uint256 internal immutable fundingDecimals;
  OptionVault internal immutable optionVault;
  ERC20 internal immutable underlying;
  ERC20 internal immutable funding;

  uint256 public settlementFee= 0.005e18;
  uint256 public exerciseFee= 0.005e18;
  uint256 public swapSlippage = 0.0005e18;
  uint256 public lendingPoolRateMode = 2;
  address public maintenanceAddress;
  
  constructor(string memory _name, string memory _symbol, OptionVault _optionVault) ERC20(_name, _symbol){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    maintenanceAddress = msg.sender;
    optionVault = _optionVault;
    underlying = _optionVault.underlying();
    funding = _optionVault.funding();
    fundingDecimals = _optionVault.funding().decimals();
    _mint(msg.sender, BASE);}

  function expireOptions(address _exerciseFeeRecipient) external {
    uint256 _expiringId = optionVault.getExpiringOptionId();

    optionVault.stampExpiredOption(_expiringId);
    
    (uint256 _payoff, uint256 _payback) = optionVault.getContractPayoff(_expiringId);
    
    uint256 _settleFeeAmount = _payoff.ethmul(settlementFee);
    uint256 _exerciseFeeAmount = _payoff.ethmul(exerciseFee);
    
    OptionLibrary.Option memory _option = optionVault.getOption(_expiringId);
    OptionLibrary.OptionSide _optionSide = _option.side;
    if(_optionSide == OptionLibrary.OptionSide.Buy){
      _payback = _payback - Math.min(_payback, _settleFeeAmount + _exerciseFeeAmount);
      if(_payback > 0){
        require(funding.transfer(optionVault.getOption(_expiringId).holder, _payback.toDecimals(fundingDecimals)), "Failed payment to holder");}}
    else if(_optionSide == OptionLibrary.OptionSide.Sell && _payback > 0){
      require(funding.transfer(optionVault.getOption(_expiringId).holder, _payback.toDecimals(fundingDecimals)), "Failed payment to holder");}

    if(_settleFeeAmount > 0){
      require(funding.transfer(maintenanceAddress, _settleFeeAmount.toDecimals(fundingDecimals)), "Failed payment to maintenance");}

    if(_exerciseFeeAmount > 0){
      require(funding.transfer(_exerciseFeeRecipient, _exerciseFeeAmount.toDecimals(fundingDecimals)), "Failed payment to exerciser.");}
    
    emit Expire(_option.holder, _option, _payback);}

  function calcCapital(bool _net, bool _average) public view returns(uint256 _capital){
    _capital = optionVault.getGrossCapital(address(this));
    if(_net){ _capital -= Math.min(optionVault.getMaxHedge() + optionVault.sellPutCollaterals(), _capital);}
    if(_average){ 
      if(totalSupply() > 0) {
        _capital = _capital.ethdiv(totalSupply()); }
      else if(totalSupply() == 0 && _capital == 0) {
        _capital = BASE;}}}
    
  function addCapital(uint256 _depositAmount) external {
      uint256 _mintMPTokenAmount = MarketLibrary.toWei(_depositAmount, fundingDecimals).ethdiv(calcCapital(false, true));
      require(funding.transferFrom(msg.sender, address(this), _depositAmount));
      _mint(msg.sender, _mintMPTokenAmount);}

  function withdrawCapital(uint256 _burnMPTokenAmount) external {
      uint256 _withdrawValue = calcCapital(true, true).ethmul(_burnMPTokenAmount).toDecimals(fundingDecimals); 
      _burn(msg.sender, _burnMPTokenAmount);
      require(funding.transfer(msg.sender, _withdrawValue));}

  function tradeSwapAggregate(int256 _underlyingAmt, int256 _fundingAmt, address payable _spender, bytes calldata _calldata, uint256 _gas) external onlyRole(EXCHANGE_ROLE){
    (uint256 _fromAmt, , address _fromAddress, ) = MarketLibrary.cleanTradeAmounts(_underlyingAmt, _fundingAmt, address(underlying), address(funding));
    require(ERC20(_fromAddress).approve(_spender, _fromAmt), "Swap approval failed");
    (bool success, bytes memory data) = _spender.call{gas: _gas}(_calldata);
    emit Response(success, data);}

  function tradeSwaps(int256 _underlyingAmt, int256 _fundingAmt, IUniswapV2Router02 _router, uint256 _deadline) external onlyRole(EXCHANGE_ROLE) {
    (uint256 _fromAmt, uint256 _toAmt, address _fromAddress, address _toAddress) = MarketLibrary.cleanTradeAmounts(_underlyingAmt, _fundingAmt, address(underlying), address(funding));
    require(ERC20(_fromAddress).approve(address(_router), _fromAmt), "Swap approval failed");
    address[] memory _path = new address[](2);
    _path[0]=_fromAddress;
    _path[1] = _toAddress;
    _router.swapTokensForExactTokens(_toAmt, _fromAmt, _path, address(this), block.timestamp + _deadline );}

  function hedgeTradesForLoans() external onlyRole(EXCHANGE_ROLE) {
    (int256 _loanTradeAmount, int256 _collateralChange,,) = optionVault.calcLoanTradesInTok(address(this), lendingPoolRateMode);
    address _lendingPoolAddress = ILendingPoolAddressesProvider(optionVault.aaveAddress()).getLendingPool();
    ILendingPool _lendingPool = ILendingPool(_lendingPoolAddress);

    if(_collateralChange > 0){
      require(funding.approve(_lendingPoolAddress, uint256(_collateralChange)), "Collateral approval failed.");
      _lendingPool.deposit(address(funding), uint256(_collateralChange), address(this), 0);}
    
    if(_loanTradeAmount > 0){
      _lendingPool.borrow(address(underlying), uint256(_loanTradeAmount), lendingPoolRateMode,  0, address(this));}
    else if(_loanTradeAmount < 0){
      uint256 _loan = uint256(-_loanTradeAmount);
      require(underlying.balanceOf(address(this))>= _loan, "not enough token to repay loans");
      require(underlying.approve(_lendingPoolAddress, _loan), "Loan approval failed");
      _lendingPool.repay(address(underlying), _loan, lendingPoolRateMode, address(this));}

    if(_collateralChange < 0){
      _lendingPool.withdraw(address(funding), uint256(-_collateralChange), address(this));}}

  function resetSettlementFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ 
    require(_newFee < BASE, "Param too big"); 
    settlementFee = _newFee;
    emit ResetParameter(0, _newFee);}

  function resetExerciseFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ 
    require(_newFee < BASE, "Param too big"); 
    exerciseFee = _newFee;
    emit ResetParameter(1, _newFee);}

  function resetSlippage(uint256 _slippage) external onlyRole(ADMIN_ROLE){ 
    swapSlippage = _slippage;
    emit ResetParameter(2, _slippage);}
  
  function resetLendingPoolRateMode(uint256 _newRateMode) external onlyRole(ADMIN_ROLE) {
    require(_newRateMode == 1 || _newRateMode == 2);
    lendingPoolRateMode = _newRateMode;
    emit ResetParameter(3, _newRateMode);}

  function resetMaintenance(address _newAddress) external onlyRole(ADMIN_ROLE){ 
    maintenanceAddress = _newAddress;
    emit ResetAddress(0, _newAddress);}
}
