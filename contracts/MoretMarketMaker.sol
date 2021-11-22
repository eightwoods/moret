// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MarketLibrary.sol";
import "./OptionVault.sol";

contract MoretMarketMaker is ERC20, AccessControl, EOption
{
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

  uint256 private multiplier;
  uint256 public settlementFee= 5 * (10 ** 15);
  uint256 public exerciseFee= 5 * (10 ** 15);
  OptionVault internal optionVault;

  address internal underlying;
  address internal funding;
  address public maintenanceAddress;
  uint256 public lendingPoolRateMode = 2;
  uint256 public swapSlippage = 5 * (10 ** 15);
  
  constructor(string memory _name, string memory _symbol, address _optionAddress) ERC20(_name, _symbol){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    _setupRole(MINER_ROLE, msg.sender);
    maintenanceAddress = msg.sender;
    optionVault = OptionVault(_optionAddress);
    multiplier = OptionLibrary.Multiplier();
    underlying = optionVault.underlying();
    funding = optionVault.funding();
    _mint(msg.sender, multiplier);}

  function expireOptions(address exerciseFeeRecipient) external {
    uint256 _expiringId = optionVault.getExpiringOptionId();
    while(_expiringId >0) {
      optionVault.stampExpiredOption(_expiringId);
      
      ( uint256 _payoff, uint256 _payback) = optionVault.getContractPayoff(_expiringId);
      require(_payback < MarketLibrary.balanceDef(funding, address(this)), "Balance insufficient.");
      if(_payback > 0){
        uint256 _holderPayment = _payoff == _payback? MulDiv(_payback, multiplier - settlementFee - exerciseFee, multiplier): _payback;
        uint256 _settleFeeAmount = MulDiv(_payoff, settlementFee, multiplier);
        uint256 _exerciseFeeAmount = MulDiv(_payoff, exerciseFee, multiplier);

        require(IERC20(funding).transfer(optionVault.getOptionHolder(_expiringId), MarketLibrary.cvtDecimals(_holderPayment, funding)), "Failed payment to holder");
        require(IERC20(funding).transfer(maintenanceAddress, MarketLibrary.cvtDecimals(_settleFeeAmount, funding)), "Failed payment to maintenance");
        require(IERC20(funding).transfer(exerciseFeeRecipient, MarketLibrary.cvtDecimals(_exerciseFeeAmount, funding)), "Failed payment to exerciser.");}
      
      _expiringId = optionVault.getExpiringOptionId();}}

  function calcCapital(bool _net, bool _average) public view returns(uint256 _capital){
      (uint256 _price, ) = optionVault.queryPrice();
      (uint256 _underlying_balance, uint256 _funding_balance, uint256 _collateral_balance, uint256 _debt_balance) = optionVault.getBalances(address(this));
      _capital = _funding_balance + _collateral_balance + MulDiv(_underlying_balance, _price, multiplier);
      require(_capital > MulDiv(_debt_balance, _price, multiplier), "Negative equity.");
      _capital -= MulDiv(_debt_balance, _price, multiplier);

      if(_net){ _capital -= Math.min(MulDiv(optionVault.getAggregateNotional(false), _price, multiplier), _capital);}
      if(_average){ 
        if(totalSupply() > 0) _capital = MulDiv(_capital , multiplier , totalSupply()); 
        if(totalSupply() == 0 && _capital == 0) _capital = multiplier;}}
    
  function addCapital(uint256 _depositAmount) external {
      uint256 _mintMPTokenAmount = MulDiv(MarketLibrary.cvtDef(_depositAmount, funding), multiplier, calcCapital(false, true));
      require(ERC20(funding).transferFrom(msg.sender, address(this), _depositAmount));
      _mint(msg.sender, _mintMPTokenAmount);
      emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);}

  function withdrawCapital(uint256 _burnMPTokenAmount) external {
      uint256 _withdrawValue = MarketLibrary.cvtDecimals(MulDiv(calcCapital(true, true),  _burnMPTokenAmount , multiplier), funding); 
      require(IERC20(funding).balanceOf(address(this)) > _withdrawValue,"Insufficient balance");
      _burn(msg.sender, _burnMPTokenAmount);
      require(ERC20(funding).transfer(msg.sender, _withdrawValue));
      emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);}
  
  function approveSpending(address _tokenAddress, address _spenderAddress, uint256 _amount) external onlyRole(MINER_ROLE){
    ERC20(_tokenAddress).approve(_spenderAddress, _amount);}

  function tradesSwaps(int256 _underlyingAmt, int256 _fundingAmt, address _router, uint256 _parameter, bool _useAggregator) external onlyRole(MINER_ROLE) {
    (uint256 _fromAmt, uint256 _toAmt, address _fromAddress, address _toAddress) = MarketLibrary.cleanTradeAmounts(_underlyingAmt, _fundingAmt, optionVault.underlying(), optionVault.funding());
    if(_useAggregator) swapByAggregator(_fromAddress, _toAddress, _router, _fromAmt, _toAmt, _parameter);
    if(!_useAggregator) swapByRouter(_fromAddress, _toAddress, _router, _fromAmt, _toAmt, _parameter);}
  
  function swapByRouter(address _fromAddress, address _toAddress, address _router, uint256 _fromAmt, uint256 _toAmt, uint256 _deadline) internal {
    ERC20(_fromAddress).approve(_router, _fromAmt);
    address[] memory _path = new address[](2);
    _path[0]=_fromAddress;
    _path[1] = _toAddress;
    IUniswapV2Router02(_router).swapTokensForExactTokens(_fromAmt, _toAmt, _path, address(this), block.timestamp + _deadline );}

  function swapByAggregator(address _fromAddress, address _toAddress, address _aggregator, uint256 _fromAmt, uint256 _toAmt, uint256 _parts) internal {
    ERC20(_fromAddress).approve(_aggregator, _fromAmt);
    (uint256 returnAmount, uint256[] memory distribution) =  I1InchProtocol(_aggregator).getExpectedReturn( IERC20(_fromAddress), IERC20(_toAddress), _fromAmt, _parts, 0);
    I1InchProtocol(_aggregator).swap(IERC20(_fromAddress), IERC20(_toAddress), _fromAmt, Math.min(returnAmount, _toAmt), distribution, 0);}

  function hedgeTradesForLoans() external onlyRole(MINER_ROLE) {
    (int256 _loanTradeAmount, int256 _collateralChange, address _loanAddress, address _collateralAddress) = optionVault.calcHedgeTradesForLoans(address(this), lendingPoolRateMode);
    _loanTradeAmount = MarketLibrary.cvtDecimalsInt(_loanTradeAmount, _loanAddress);
    _collateralChange = MarketLibrary.cvtDecimalsInt(_collateralChange, _collateralAddress);
    address _lendingPoolAddress = ILendingPoolAddressesProvider(optionVault.aaveAddress()).getLendingPool();

    if(_collateralChange > 0){
      ERC20(funding).increaseAllowance(_lendingPoolAddress, uint256(_collateralChange));
      ILendingPool(_lendingPoolAddress).deposit(funding, uint256(_collateralChange), address(this), 0);}
    
    if(_loanTradeAmount > 0){
      ILendingPool(_lendingPoolAddress).borrow(underlying, uint256(_loanTradeAmount), lendingPoolRateMode,  0, address(this));}

    if(_loanTradeAmount < 0){
      require(ERC20(underlying).balanceOf(address(this))>= uint256(-_loanTradeAmount), "not enough token to repay loans");
      ERC20(_loanAddress).approve(_lendingPoolAddress, uint256(-_loanTradeAmount));
      ERC20(underlying).approve(_lendingPoolAddress, uint256(-_loanTradeAmount));
      ILendingPool(_lendingPoolAddress).repay(underlying, uint256(-_loanTradeAmount), lendingPoolRateMode, address(this));}

    if(_collateralChange < 0){
      ERC20(_collateralAddress).increaseAllowance(_lendingPoolAddress, uint256(-_collateralChange));
      ILendingPool(_lendingPoolAddress).withdraw(funding, uint256(-_collateralChange), address(this));}}

  function resetSettlementFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ require(_newFee < multiplier); settlementFee = _newFee;}
  function resetExerciseFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ require(_newFee < multiplier); exerciseFee = _newFee;}
  function resetMaintenance(address _newAddress) external onlyRole(ADMIN_ROLE){ maintenanceAddress = _newAddress;}
  function resetSlippage(uint256 _slippage) external onlyRole(ADMIN_ROLE){ swapSlippage = _slippage;}
  // function resetLendingPoolRateMode(uint256 _newRateMode) external onlyRole(ADMIN_ROLE) {
  //   require(_newRateMode == 1 || _newRateMode == 2);
  //   lendingPoolRateMode = _newRateMode;}
}
