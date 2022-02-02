/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MarketLibrary.sol";
import "./VolatilityChain.sol";
import "./interfaces/EOption.sol";
import "./interfaces/IProtocolDataProvider.sol";
import "./interfaces/ILendingPoolAddressesProvider.sol";

contract OptionVault is AccessControl, EOption{
  using FullMath for uint256;
  using OptionLibrary for OptionLibrary.Option;
  using EnumerableSet for EnumerableSet.UintSet;

  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");

  OptionLibrary.Option[] internal optionsList;
  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;

  VolatilityChain internal immutable volatilityChain;
  ILendingPoolAddressesProvider public immutable aaveAddress;
  ERC20 public immutable underlying;
  ERC20 public immutable funding;
  uint256 internal immutable fundingDecimals;
  uint256 internal immutable underlyingDecimals;

  uint256 internal constant BASE  = 1e18;
  uint256 internal constant SCALING = 1e5;
  uint256 public overCollateral = 1e17;

  uint256 public activeContractCount = 0;
  uint256 public sellPutCollaterals = 0;
  uint256 public deltaAtZero = 0;
  uint256 public deltaAtMax = 0;

  constructor(VolatilityChain _volChain, ERC20 _underlying, ERC20 _funding, ILendingPoolAddressesProvider _aaveAddress){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    volatilityChain = _volChain; 
    funding = _funding;
    underlying = _underlying;
    aaveAddress = _aaveAddress;
    fundingDecimals = _funding.decimals();
    underlyingDecimals = _underlying.decimals();}

  function addOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _premium, uint256 _cost, uint256 _price, uint256 _volatility, address _holder) external onlyRole(EXCHANGE_ROLE) returns(uint256 _id) {
    require(_tenor > 0, "Zero tenor");
    _id = optionsList.length;
    // Arguments: option type, option side, contract status (default to draft), contract holder address, contract id, creation timestamp, effective timestamp (default to 0), tenor in seconds, maturity timestamp (default to 0), excersie timestamp (default to 0), amount or size of contract, current spot price, option strike, implied volatility, calculated premium and total cost including collaterals.
    optionsList.push(OptionLibrary.Option(_poType, _side, OptionLibrary.OptionStatus.Draft, _holder, _id, block.timestamp,  0, _tenor, 0,  0, _amount, _price, _strike, _volatility, _premium, _cost));}

  function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
  function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionsList[activeOptionsPerOwner[_address].at(_index)];}

  function getOptionInfo(uint256 _id) external view returns(OptionLibrary.OptionStatus, OptionLibrary.OptionSide, address) {
    require(_id< optionsList.length);
    return (optionsList[_id].status, optionsList[_id].side, optionsList[_id].holder);}

  function getGrossCapital(address _address) external view returns(uint256 _capital){
    (uint256 _price, ) = volatilityChain.queryPrice();
    (uint256 _underlying_balance, uint256 _funding_balance, uint256 _collateral_balance, uint256 _debt_balance) = getBalances(_address);
    _capital = _funding_balance + _collateral_balance + _underlying_balance.ethmul(_price);
    uint256 _debt_amount = _debt_balance.ethmul(_price);
    require(_capital > _debt_amount, "Negative equity.");
    _capital -= _debt_amount;}

  function getMaxHedge() external view returns (uint256){
    (uint256 _price,) = volatilityChain.queryPrice();
    return Math.max(deltaAtZero, deltaAtMax).ethmul(_price);}

  function getContractPayoff(uint256 _id) external view returns(uint256 _payoff, uint256 _payback){
    (uint256 _price,) = volatilityChain.queryPrice();
    return optionsList[_id].calcPayoff(_price);}

  function calculateAggregateDelta(uint256 _price, bool _includeExpiring) public view returns(int256 _delta){
    _delta= 0;
    for(uint256 i=0;i<activeContractCount;i++){
      OptionLibrary.Option storage _option = optionsList[uint256(activeOptions.at(i))];
      uint256 _maturityLeft = _option.calcRemainingMaturity();
      uint256 _vol = volatilityChain.getVol(_maturityLeft);
      _delta += _option.calcDelta(_price, _vol, _includeExpiring);}}

  function calculateContractGamma(uint256 _id, uint256 _price) public view returns(int256 _gamma){
    _gamma = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active  && (optionsList[_id].maturity > block.timestamp)){
      uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - block.timestamp);
      _gamma = SafeCast.toInt256(OptionLibrary.calcGamma(_price, optionsList[_id].strike, _vol).ethmul(optionsList[_id].amount));
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell){ _gamma = -_gamma;}}}
      
  function calculateAggregateGamma() external view returns(int256 _gamma){
    (uint256 _price,) = volatilityChain.queryPrice();
    _gamma= 0;
    for(uint256 i=0;i<activeContractCount;i++){
      _gamma += calculateContractGamma(uint256(activeOptions.at(i)),_price);}}

  function calculateSpotGamma() external view returns(int256 _gamma){
    uint256 _vol = volatilityChain.getVol(86400);
    _gamma = SafeCast.toInt256(OptionLibrary.calcGamma(BASE, BASE, _vol));}

  function anyOptionExpiring() external view returns(bool _isExpiring) {
    _isExpiring = false;
    for(uint256 i=0;i<activeContractCount;i++){
      if(optionsList[uint256(activeOptions.at(i))].isExpiring()){
        _isExpiring = true;
        break;}}}

  function getExpiringOptionId() external view returns(uint256 _id){
    _id = 0;
    for(uint256 i=0;i<activeContractCount;i++){
      uint256 _id_i = uint256(activeOptions.at(i));
      if(optionsList[_id_i].isExpiring()){
        _id = _id_i;
        break;}}}

  function stampActiveOption(uint256 _id, address _holder) external onlyRole(EXCHANGE_ROLE) {
    OptionLibrary.Option storage _option = optionsList[_id];
    _option.effectiveTime = block.timestamp;
    _option.maturity = block.timestamp + _option.tenor;
    _option.status = OptionLibrary.OptionStatus.Active;
    
    sellPutCollaterals += _option.sellPutCollateral();
    deltaAtZero += _option.calcDeltaAtZero();
    deltaAtMax += _option.calcDeltaAtMax();

    activeOptionsPerOwner[_holder].add(_id);
    activeOptions.add(_id);
    activeContractCount += 1;
    
    emit StampNewOption(_id, block.timestamp);}

  function stampExpiredOption(uint256 _id)  external onlyRole(EXCHANGE_ROLE){
    activeOptions.remove(_id);
    activeContractCount -= Math.min(activeContractCount, 1);
    
    OptionLibrary.Option storage _option = optionsList[_id];
    _option.status = OptionLibrary.OptionStatus.Expired;
    _option.exerciseTime = block.timestamp;
    activeOptionsPerOwner[_option.holder].remove(_id);
    
    deltaAtZero -= Math.min(deltaAtZero, _option.calcDeltaAtZero());
    deltaAtMax -= Math.min(deltaAtMax, _option.calcDeltaAtMax());
    sellPutCollaterals -= Math.min(sellPutCollaterals, _option.sellPutCollateral());
    
    emit StampExpire(_id, block.timestamp);}

  // this function emits values in token decimals.
  function calcSwapTradesInTok(address _address, uint256 _swapSlippage) external view returns(int256 _tradeUnderlyingAmount, int256 _tradeFundingAmount){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _aggregateDelta = calculateAggregateDelta(_price, false);
    _tradeUnderlyingAmount = (_aggregateDelta >= 0? _aggregateDelta: SafeCast.toInt256(0)) - SafeCast.toInt256(MarketLibrary.toWei(underlying.balanceOf(_address), underlyingDecimals));
    _tradeFundingAmount = MarketLibrary.toDecimalsInt(OptionLibrary.getOpposeTrade(_tradeUnderlyingAmount, _price, _swapSlippage), fundingDecimals);
    _tradeUnderlyingAmount = MarketLibrary.toDecimalsInt(_tradeUnderlyingAmount, underlyingDecimals);}
  
  // this function emits values in DEFAULT decimals.
  function getBalances(address _address) public view returns(uint256 _underlyingBalance, uint256 _fundingBalance, uint256 _collateralBalance, uint256 _debtBalance){ 
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(aaveAddress.getAddress("0x1"));
    ( _underlyingBalance, ,  _debtBalance) = MarketLibrary.getTokenBalances(_address, _protocolDataProvider, underlying);
    ( _fundingBalance,  _collateralBalance,) = MarketLibrary.getTokenBalances(_address, _protocolDataProvider, funding); }

  // this function emits values in token decimals.
  function calcLoanRepaymentInTok(address _address, uint256 _lendingPoolRateMode) external view returns(uint256 _repayAmount, uint256 _repaySwapValue){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _aggregateDelta = calculateAggregateDelta(_price, false);
    (int256 _loanTradeAmount, , ) = MarketLibrary.getLoanTrade(_address, IProtocolDataProvider(aaveAddress.getAddress("0x1")), _aggregateDelta, underlying, _lendingPoolRateMode == 2);
    _repayAmount = 0;
    _repaySwapValue = 0;
    if(_loanTradeAmount < 0){
      uint256 _loanAmountU = uint256(-_loanTradeAmount);
      _repayAmount = _loanAmountU - Math.min(_loanAmountU, ERC20(underlying).balanceOf(address(this)));
      _repaySwapValue = MarketLibrary.toDecimals(_repayAmount.ethmul(_price), fundingDecimals);
      _repayAmount = MarketLibrary.toDecimals(_repayAmount, underlyingDecimals);}}

  // this function emits values in token decimals.
  function calcLoanTradesInTok(address _address, uint256 _lendingPoolRateMode) external view returns(int256 _loanTradeAmount, int256 _collateralChange, address _loanAddress, address _collateralAddress){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _aggregateDelta = calculateAggregateDelta(_price, false); 
    uint256 _targetLoan = 0;
    IProtocolDataProvider _protocolProvider = IProtocolDataProvider(aaveAddress.getAddress("0x1"));
    (_loanTradeAmount, _targetLoan, _loanAddress) = MarketLibrary.getLoanTrade(_address, _protocolProvider , _aggregateDelta, underlying, _lendingPoolRateMode == 2);
    (_collateralChange, _collateralAddress) = MarketLibrary.getCollateralTrade(_address, _protocolProvider, _targetLoan, _price, funding, underlying, overCollateral);
    _loanTradeAmount = MarketLibrary.toDecimalsInt(_loanTradeAmount, ERC20(_loanAddress).decimals());
    _collateralChange =MarketLibrary.toDecimalsInt(_collateralChange, ERC20(_collateralAddress).decimals());}

  function queryVol(uint256 _tenor) external view returns(uint256){return volatilityChain.getVol(_tenor);}
  function queryPrice() external view returns(uint256, uint256){return volatilityChain.queryPrice();}
  function tokenHash() external view returns (bytes32) {return volatilityChain.tokenHash();}
  function resetOverCollateral(uint256 _overCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) { overCollateral= _overCollateral;}
}
