// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./FullMath.sol";
import "./MarketLibrary.sol";

contract MoretMarketMaker is ERC20, AccessControl, EOption
{
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;

  uint256 private constant ethMultiplier = 10 ** 18;
  uint256 public settlementFee = 5 * (10 ** 15); // 0.5% for settlement fee
  uint256 public exerciseFee = 5 * (10 ** 15); // 0.5% to compensate for the exercise bot.
  uint256 public extraCollateral = 12 * (10**17); // 20% extra collateral to post
  IOptionVault internal optionVault;

  address public underlyingAddress;
  address public fundingAddress;
  address internal maintenanceAddress;
  address internal protocolDataProviderAddress;
  
  constructor(string memory _name, string memory _symbol, address _underlyingAddress, address _fundingAddress, address _optionAddress, address _protocolDataProviderAddress) ERC20(_name, _symbol){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    maintenanceAddress = msg.sender;
    fundingAddress = _fundingAddress;
    underlyingAddress = _underlyingAddress;
    optionVault = IOptionVault(_optionAddress);
    protocolDataProviderAddress = _protocolDataProviderAddress;
    _mint(msg.sender, ethMultiplier);}

  function recordOptionPurchase(address _purchaser, uint256 _id) external  onlyRole(EXCHANGE_ROLE){
    activeOptionsPerOwner[_purchaser].add(_id);
    activeOptions.add(_id);}

  function getAggregateGamma(bool _ignoreSells) public onlyRole(EXCHANGE_ROLE) view returns(int256 _gamma){
    (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
    _gamma= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      _gamma += optionVault.calculateContractGamma(uint256(activeOptions.at(i)),_price, _priceMultiplier, _ignoreSells);}}

  function getAggregateDelta(bool _ignoreSells) internal view returns(int256 _delta,uint256 _price, uint256 _priceMultiplier){
    (_price,, _priceMultiplier) = optionVault.queryPrice();
    _delta= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      _delta += optionVault.calculateContractDelta(uint256(activeOptions.at(i)),_price, _priceMultiplier, _ignoreSells);}}

  function getBalances() public view returns(uint256 _underlyingBalance, uint256 _fundingBalance, uint256 _collateralBalance, uint256 _debtBalance){
    ( _underlyingBalance, ,  _debtBalance) = MarketLibrary.getTokenBalances(address(this), protocolDataProviderAddress, underlyingAddress);
    ( _fundingBalance,  _collateralBalance,) = MarketLibrary.getTokenBalances(address(this), protocolDataProviderAddress, fundingAddress); }

  function anyOptionExpiring() external view returns(bool _isExpiring) {
    _isExpiring = false;
    for(uint256 i=0;i<activeOptions.length();i++){
      if(optionVault.isOptionExpiring(uint256(activeOptions.at(i)))){
        _isExpiring = true;
        break;}}}

  function expireOptions() external   returns(uint256 _expiringId){
    _expiringId = 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      if(optionVault.isOptionExpiring(uint256(activeOptions.at(i)))){
        _expiringId = uint256(activeOptions.at(i));
        break;}}
    if(_expiringId >0) {
      ( , uint256 _payback) = optionVault.getContractPayoff(_expiringId);
      require(_payback < IERC20(underlyingAddress).balanceOf(address(this)), "Balance insufficient.");
      if(_payback > 0){
        optionVault.stampExpiredOption(_expiringId);
        activeOptionsPerOwner[optionVault.getOptionHolder(_expiringId)].remove(_expiringId);
        activeOptions.remove(_expiringId);
        uint256 _settleFeeAmount = MulDiv(_payback, settlementFee, ethMultiplier);
        uint256 _exerciseFeeAmount = MulDiv(_payback, exerciseFee, ethMultiplier);
        require(IERC20(underlyingAddress).transfer(optionVault.getOptionHolder(_expiringId), _payback - _settleFeeAmount - _exerciseFeeAmount));
        require(IERC20(underlyingAddress).transfer(maintenanceAddress, _settleFeeAmount));
        require(IERC20(underlyingAddress).transfer(msg.sender, _exerciseFeeAmount));}}}

  function getAggregateNotional() internal view returns(uint256 _notional) {
    _notional= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      _notional += optionVault.queryOptionNotional(uint256(activeOptions.at(i)), false);} }

  function calcCapital(bool _net, bool _average) public view returns(uint256 _capital){
      (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
      (uint256 _underlying_balance, uint256 _funding_balance, uint256 _collateral_balance, uint256 _debt_balance) = getBalances();
      _capital = _funding_balance + _collateral_balance + MulDiv(_underlying_balance, _price, _priceMultiplier);
      require(_capital > MulDiv(_debt_balance, _price, _priceMultiplier), "Negative equity.");
      _capital -= MulDiv(_debt_balance, _price, _priceMultiplier);

      if(_net){ _capital -= Math.min(getAggregateNotional(), _capital);}
      if(_average){ _capital = MulDiv(_capital , ethMultiplier , totalSupply()); }}
    
  function addCapital(uint256 _depositAmount) external {
      uint256 _averageGrossCapital = calcCapital(false, true);
      uint256 _mintMPTokenAmount = MulDiv(_depositAmount, ethMultiplier, _averageGrossCapital);
      require(ERC20(fundingAddress).transferFrom(msg.sender, address(this), _depositAmount));
      _mint(msg.sender, _mintMPTokenAmount);
      emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);}

  function withdrawCapital(uint256 _burnMPTokenAmount) external {
      uint256 _withdrawValue = MulDiv(calcCapital(true, true),  _burnMPTokenAmount , ethMultiplier);
      require(IERC20(fundingAddress).balanceOf(address(this)) > _withdrawValue,"Insufficient balance");
      _burn(msg.sender, _burnMPTokenAmount);
      require(ERC20(fundingAddress).transfer(msg.sender, _withdrawValue));
      emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);}
  
  function calcHedgeTrade() external onlyRole(EXCHANGE_ROLE) view returns(uint256 _targetUnderlying, int256 _chgDebt, int256 _chgCollateral){
    (int256 _aggregateDelta, uint256 _price, uint256 _priceMultiplier) = getAggregateDelta(false);
    _targetUnderlying = 0;
    _chgDebt = 0;
    ( , uint256 _fundingBalance, uint256 _collateralBalance, uint256 _debtBalance) = getBalances();
    if(_aggregateDelta >= 0){_chgDebt = -int256(_debtBalance); 
      _chgCollateral = -int256(_collateralBalance);
      _targetUnderlying = uint256(_aggregateDelta) ;}
    if(_aggregateDelta < 0){_targetUnderlying = 0; 
      _chgDebt = int256(_debtBalance) + _aggregateDelta;
      (uint256 _ltv, uint256 _reserveMultiplier) = MarketLibrary.getLTV(protocolDataProviderAddress, underlyingAddress);
      uint256 _requiredCollateral = MulDiv(MulDiv(MulDiv(uint256(-_aggregateDelta), _price, _priceMultiplier), _reserveMultiplier, _ltv), extraCollateral, ethMultiplier);
      require(_requiredCollateral<= (_fundingBalance + _collateralBalance), "Insufficient collateral;");
      _chgCollateral =  int256(_requiredCollateral) - int256(_collateralBalance) ;}}

  function approveSpending(address _tokenAddress, address _exchangeAddress, uint256 _amount) external onlyRole(EXCHANGE_ROLE){
    ERC20(_tokenAddress).increaseAllowance(_exchangeAddress, _amount);}

  function depositCollateral(uint256 _addCollateral, address _lendingPoolAddress) external onlyRole(EXCHANGE_ROLE){
    ERC20(fundingAddress).increaseAllowance(_lendingPoolAddress, _addCollateral);
    ILendingPool(_lendingPoolAddress).deposit(fundingAddress, _addCollateral, address(this), 0);}

  function withdrawCollateral(uint256 _removeCollateral, address _lendingPoolAddress) external onlyRole(EXCHANGE_ROLE){
    (address _collateralAddress,,) = MarketLibrary.getLendingTokenAddresses(protocolDataProviderAddress, fundingAddress);
    ERC20(_collateralAddress).increaseAllowance(_lendingPoolAddress, _removeCollateral);
    ILendingPool(_lendingPoolAddress).withdraw(fundingAddress, _removeCollateral, address(this));}

  function borrowLoans(uint256 _borrowAmount , address _lendingPoolAddress, uint256 _lendingPoolRateMode)  external onlyRole(EXCHANGE_ROLE) {
    ILendingPool(_lendingPoolAddress).borrow(underlyingAddress, _borrowAmount, _lendingPoolRateMode,  0, address(this));}

  function repayLoans(uint256 _repayAmount, address _lendingPoolAddress, uint256 _lendingPoolRateMode)  external onlyRole(EXCHANGE_ROLE) {
    (,address _stableDebt, address _debtToken) = MarketLibrary.getLendingTokenAddresses(protocolDataProviderAddress, underlyingAddress);
    if(_lendingPoolRateMode==1) _debtToken = _stableDebt;
    ERC20(_debtToken).approve(_lendingPoolAddress, _repayAmount);
    ERC20(underlyingAddress).approve(_lendingPoolAddress, _repayAmount);
    ILendingPool(_lendingPoolAddress).repay(underlyingAddress, _repayAmount, _lendingPoolRateMode, address(this));}

  function swapToUnderlyingAtVenue(uint256 _underlyingAmount, address _exchangeAddress, uint256 _maxSlippage, uint256 _deadlineLag) external onlyRole(EXCHANGE_ROLE)  returns(uint256[] memory _swappedAmounts){
    address[] memory _path = new address[](2);
    _path[0] = fundingAddress;
    _path[1] = underlyingAddress; 
    (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
    uint256 _maxCost = MulDiv(MulDiv(_underlyingAmount, _price, _priceMultiplier), ethMultiplier + _maxSlippage, ethMultiplier);
    ERC20(fundingAddress).increaseAllowance(_exchangeAddress, _maxCost);
    _swappedAmounts = IUniswapV2Router02(_exchangeAddress).swapTokensForExactTokens(_underlyingAmount, _maxCost, _path, address(this), block.timestamp + _deadlineLag); }

  function swapToFundingAtVenue(uint256 _underlyingAmount,  address _exchangeAddress, uint256 _maxSlippage, uint256 _deadlineLag) external onlyRole(EXCHANGE_ROLE)   returns(uint256[] memory _swappedAmounts) {
    ERC20(underlyingAddress).increaseAllowance(_exchangeAddress, _underlyingAmount);
    address[] memory _path = new address[](2);
    _path[0] = underlyingAddress;
    _path[1] = fundingAddress;
    (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
    uint256 _minReturn = MulDiv(MulDiv(_underlyingAmount, _price, _priceMultiplier), ethMultiplier - _maxSlippage, ethMultiplier);
    _swappedAmounts = IUniswapV2Router02(_exchangeAddress).swapExactTokensForTokens(_underlyingAmount, _minReturn, _path, address(this), block.timestamp + _deadlineLag);}

  function swapToUnderlyingAtAggregator(uint256 _underlyingAmount, address _exchangeAddress, uint256 _maxSlippage ) external onlyRole(EXCHANGE_ROLE)  returns(uint256 _swappedAmounts, uint256 _swappedUnderlying){
    (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
    _swappedAmounts = MulDiv(MulDiv(_underlyingAmount, _price, _priceMultiplier), ethMultiplier + _maxSlippage, ethMultiplier);
    (uint256 _returnAmount, uint256[] memory _distribution) = I1InchProtocol(_exchangeAddress).getExpectedReturn( IERC20(fundingAddress) , IERC20(underlyingAddress) , _swappedAmounts, 1, 0);
    ERC20(fundingAddress).increaseAllowance(_exchangeAddress, _swappedAmounts);
    _swappedUnderlying = I1InchProtocol(_exchangeAddress).swap( IERC20(fundingAddress), IERC20(underlyingAddress), _swappedAmounts, _returnAmount, _distribution, 0);}

  function swapToFundingAtAggregator(uint256 _underlyingAmount,  address _exchangeAddress, uint256 _maxSlippage ) external onlyRole(EXCHANGE_ROLE)  returns(uint256 _swappedAmounts) {
    (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
    (uint256 _returnAmount, uint256[] memory _distribution) = I1InchProtocol(_exchangeAddress).getExpectedReturn( IERC20(underlyingAddress), IERC20(fundingAddress), _underlyingAmount, 1, 0);
    require(_returnAmount >= MulDiv(MulDiv(_underlyingAmount, _price, _priceMultiplier), ethMultiplier - _maxSlippage, ethMultiplier),"Excessive slippage.");
    ERC20(underlyingAddress).increaseAllowance(_exchangeAddress, _underlyingAmount);
    _swappedAmounts = I1InchProtocol(_exchangeAddress).swap(IERC20(underlyingAddress), IERC20(fundingAddress), _underlyingAmount, _returnAmount, _distribution, 0);}

  function resetSettlementFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ require(_newFee < ethMultiplier); settlementFee = _newFee;}
  function resetExerciseFee(uint256 _newFee) external onlyRole(ADMIN_ROLE){ require(_newFee < ethMultiplier); exerciseFee = _newFee;}
  function resetMaintenance(address _newAddress) external onlyRole(ADMIN_ROLE){ maintenanceAddress = _newAddress;}

  function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
  function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionVault.getOption(activeOptionsPerOwner[_address].at(_index));}

}
