// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./MarketLibrary.sol";

contract MoretMarketMaker is ERC20, AccessControl, EOption
{
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

  uint256 private multiplier = 10 ** 18;
  uint256 public settlementFee= 5 * (10 ** 15);
  uint256 public exerciseFee= 5 * (10 ** 15);
  IOptionVault internal optionVault;

  address public underlyingAddress;
  address public fundingAddress;
  address public vaultAddress; 
  address public maintenanceAddress;
  address public aaveAddressProviderAddress;
  uint256 public lendingPoolRateMode = 2;
  uint256 public swapSlippage = 5 * (10 ** 15);
  
  constructor(string memory _name, string memory _symbol, address _underlyingAddress, address _fundingAddress, address _optionAddress, address _aaveAddressProviderAddress) ERC20(_name, _symbol){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    _setupRole(MINER_ROLE, msg.sender);
    maintenanceAddress = msg.sender;
    fundingAddress = _fundingAddress;
    underlyingAddress = _underlyingAddress;
    vaultAddress = _optionAddress;
    optionVault = IOptionVault(_optionAddress);
    aaveAddressProviderAddress = _aaveAddressProviderAddress;
    _mint(msg.sender, multiplier);}

  function getBalances() public view returns(uint256 _underlyingBalance, uint256 _fundingBalance, uint256 _collateralBalance, uint256 _debtBalance){
    address _protocolDataProviderAddress = ILendingPoolAddressesProvider(aaveAddressProviderAddress).getAddress("0x1");//bytes32(uint256(1)));
    ( _underlyingBalance, ,  _debtBalance) = MarketLibrary.getTokenBalances(address(this), _protocolDataProviderAddress, underlyingAddress);
    ( _fundingBalance,  _collateralBalance,) = MarketLibrary.getTokenBalances(address(this), _protocolDataProviderAddress, fundingAddress); }

  function expireOptions(address exerciseFeeRecipient) external {
    uint256 _expiringId = optionVault.getExpiringOptionId();
    while(_expiringId >0) {
      optionVault.stampExpiredOption(_expiringId);
      
      ( uint256 _payoff, uint256 _payback) = optionVault.getContractPayoff(_expiringId);
      require(_payback < MarketLibrary.balanceDef(fundingAddress, address(this)), "Balance insufficient.");
      if(_payback > 0){
        uint256 _holderPayment = _payoff == _payback? MulDiv(_payback, multiplier - settlementFee - exerciseFee, multiplier): _payback;
        uint256 _settleFeeAmount = MulDiv(_payoff, settlementFee, multiplier);
        uint256 _exerciseFeeAmount = MulDiv(_payoff, exerciseFee, multiplier);

        require(IERC20(fundingAddress).transfer(optionVault.getOptionHolder(_expiringId), MarketLibrary.cvtDecimals(_holderPayment, fundingAddress)), "Failed payment to holder");
        require(IERC20(fundingAddress).transfer(maintenanceAddress, MarketLibrary.cvtDecimals(_settleFeeAmount, fundingAddress)), "Failed payment to maintenance");
        require(IERC20(fundingAddress).transfer(exerciseFeeRecipient, MarketLibrary.cvtDecimals(_exerciseFeeAmount, fundingAddress)), "Failed payment to exerciser.");}
      
      _expiringId = optionVault.getExpiringOptionId();}}

  function calcCapital(bool _net, bool _average) public view returns(uint256 _capital){
      (uint256 _price, ) = optionVault.queryPrice();
      (uint256 _underlying_balance, uint256 _funding_balance, uint256 _collateral_balance, uint256 _debt_balance) = getBalances();
      _capital = _funding_balance + _collateral_balance + MulDiv(_underlying_balance, _price, multiplier);
      require(_capital > MulDiv(_debt_balance, _price, multiplier), "Negative equity.");
      _capital -= MulDiv(_debt_balance, _price, multiplier);

      if(_net){ _capital -= Math.min(MulDiv(optionVault.getAggregateNotional(false), _price, multiplier), _capital);}
      if(_average){ 
        if(totalSupply() > 0) _capital = MulDiv(_capital , multiplier , totalSupply()); 
        if(totalSupply() == 0 && _capital == 0) _capital = multiplier;}}
    
  function addCapital(uint256 _depositAmount) external {
      uint256 _mintMPTokenAmount = MulDiv(MarketLibrary.cvtDef(_depositAmount, fundingAddress), multiplier, calcCapital(false, true));
      require(ERC20(fundingAddress).transferFrom(msg.sender, address(this), _depositAmount));
      _mint(msg.sender, _mintMPTokenAmount);
      emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);}

  function withdrawCapital(uint256 _burnMPTokenAmount) external {
      uint256 _withdrawValue = MarketLibrary.cvtDecimals(MulDiv(calcCapital(true, true),  _burnMPTokenAmount , multiplier), fundingAddress); 
      require(IERC20(fundingAddress).balanceOf(address(this)) > _withdrawValue,"Insufficient balance");
      _burn(msg.sender, _burnMPTokenAmount);
      require(ERC20(fundingAddress).transfer(msg.sender, _withdrawValue));
      emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);}
  
  function approveSpending(address _tokenAddress, address _spenderAddress, uint256 _amount) external onlyRole(MINER_ROLE){
    ERC20(_tokenAddress).approve(_spenderAddress, _amount);}

  function calcHedgeTradesForSwaps() external onlyRole(MINER_ROLE) view returns(int256 _tradeUnderlyingAmount, int256 _tradeFundingAmount){
    (int256 _aggregateDelta, uint256 _price) = optionVault.calculateAggregateDelta(false);
    _tradeUnderlyingAmount = (_aggregateDelta >= 0? _aggregateDelta: int256(0)) - int256(MarketLibrary.balanceDef(underlyingAddress, address(this)));
    _tradeFundingAmount = MarketLibrary.cvtDecimalsInt(OptionLibrary.getOpposeTrade(_tradeUnderlyingAmount, _price, swapSlippage), fundingAddress);
    _tradeUnderlyingAmount = MarketLibrary.cvtDecimalsInt(_tradeUnderlyingAmount, underlyingAddress);}

  function calcHedgeTradesForLoans() external onlyRole(MINER_ROLE) view returns(int256 _loanTradeAmount, int256 _collateralChange, address _loanAddress, address _collateralAddress){
    (int256 _aggregateDelta, uint256 _price) = optionVault.calculateAggregateDelta(false);
    address _protocolDataProviderAddress = ILendingPoolAddressesProvider(aaveAddressProviderAddress).getAddress("0x1");//bytes32(uint256(1)));
    uint256 _targetLoan = 0;
    (_loanTradeAmount, _targetLoan, _loanAddress) = MarketLibrary.getLoanTrade(address(this), _protocolDataProviderAddress, _aggregateDelta, underlyingAddress, lendingPoolRateMode == 2);
    (_collateralChange, _collateralAddress) = MarketLibrary.getCollateralTrade(address(this), _protocolDataProviderAddress, _targetLoan, _price, fundingAddress, underlyingAddress);}

  // function depositCollateral(uint256 _addCollateral, address _lendingPoolAddress) external onlyRole(EXCHANGE_ROLE){
  //   ERC20(fundingAddress).increaseAllowance(_lendingPoolAddress, _addCollateral);
  //   ILendingPool(_lendingPoolAddress).deposit(fundingAddress, _addCollateral, address(this), 0);}

  // function withdrawCollateral(uint256 _removeCollateral, address _lendingPoolAddress) external onlyRole(EXCHANGE_ROLE){
  //   (address _collateralAddress,,) = MarketLibrary.getLendingTokenAddresses(protocolDataProviderAddress, fundingAddress);
  //   ERC20(_collateralAddress).increaseAllowance(_lendingPoolAddress, _removeCollateral);
  //   ILendingPool(_lendingPoolAddress).withdraw(fundingAddress, _removeCollateral, address(this));}

  // function borrowLoans(uint256 _borrowAmount , address _lendingPoolAddress, uint256 _lendingPoolRateMode)  external onlyRole(EXCHANGE_ROLE) {
  //   ILendingPool(_lendingPoolAddress).borrow(underlyingAddress, _borrowAmount, _lendingPoolRateMode,  0, address(this));}

  // function repayLoans(uint256 _repayAmount, address _lendingPoolAddress, uint256 _lendingPoolRateMode)  external onlyRole(EXCHANGE_ROLE) {
  //   (,address _stableDebt, address _debtToken) = MarketLibrary.getLendingTokenAddresses(protocolDataProviderAddress, underlyingAddress);
  //   if(_lendingPoolRateMode==1) _debtToken = _stableDebt;
  //   ERC20(_debtToken).approve(_lendingPoolAddress, _repayAmount);
  //   ERC20(underlyingAddress).approve(_lendingPoolAddress, _repayAmount);
  //   ILendingPool(_lendingPoolAddress).repay(underlyingAddress, _repayAmount, _lendingPoolRateMode, address(this));}

  function resetSettlementFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ require(_newFee < multiplier); settlementFee = _newFee;}
  function resetExerciseFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ require(_newFee < multiplier); exerciseFee = _newFee;}
  // function resetMaintenance(address _newAddress) external onlyRole(ADMIN_ROLE){ maintenanceAddress = _newAddress;}
  function resetSlippage(uint256 _slippage) external onlyRole(ADMIN_ROLE){ swapSlippage = _slippage;}
  function resetLendingPoolRateMode(uint256 _newRateMode) external onlyRole(ADMIN_ROLE) {
    require(_newRateMode == 1 || _newRateMode == 2);
    lendingPoolRateMode = _newRateMode;}
  function getHoldersOptionCount(address _address) external view returns(uint256){return optionVault.getHoldersOptionCount(_address);}
  function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionVault.getHoldersOption(_index, _address);}
  function anyOptionExpiring() external view returns(bool){return optionVault.anyOptionExpiring();} 
}
