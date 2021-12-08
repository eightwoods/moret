/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity 0.8.10;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MarketLibrary.sol";

contract OptionVault is AccessControl{
  using OptionLibrary for OptionLibrary.Option;
  using EnumerableSet for EnumerableSet.UintSet;
  // using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  mapping(uint256=> OptionLibrary.Option) internal optionsList;
  uint256 public optionCounter = 0;
  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;
  IVolatilityChain internal volatilityChain;

  address public volChainAddress;
  address public aaveAddress;
  address public underlying;
  address public funding;

  uint256 public overCollateral = 10 ** 17;

  constructor( address _volChainAddress, address _underlying, address _funding, address _aaveAddress){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    volChainAddress = _volChainAddress;
    volatilityChain = IVolatilityChain(_volChainAddress); 
    funding = _funding;
    underlying = _underlying;
    aaveAddress = _aaveAddress;}
  
  function descriptionHash() external view returns (bytes32)  { return keccak256(abi.encodePacked(volatilityChain.getDecription()));}

  function addOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _premium, uint256 _cost, uint256 _price, uint256 _volatility, address _holder) external onlyRole(EXCHANGE_ROLE) returns(uint256 _id) {
    optionCounter++;
    _id = optionCounter;
    optionsList[_id] = OptionLibrary.Option(_poType, _side, OptionLibrary.OptionStatus.Draft, _holder, _id, block.timestamp,  0, _tenor, 0,  0, _amount, _price, _strike, _volatility, _premium, _cost);}

  function getOptionHolder(uint256 _id) external view returns(address) { return optionsList[_id].holder;}
  function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
  function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionsList[activeOptionsPerOwner[_address].at(_index)];}
  function getOption(uint256 _id) external view returns(OptionLibrary.Option memory) {return optionsList[_id];}

  function getAggregateNotional() external view returns(uint256 _notional) {
    _notional= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      _notional += optionsList[uint256(activeOptions.at(i))].amount;} }

  function getGrossCapital(address _address) external view returns(uint256 _capital){
    (uint256 _price, ) = volatilityChain.queryPrice();
    (uint256 _underlying_balance, uint256 _funding_balance, uint256 _collateral_balance, uint256 _debt_balance) = getBalances(_address);
    _capital = _funding_balance + _collateral_balance + MulDiv(_underlying_balance, _price, OptionLibrary.Multiplier());
    require(_capital > MulDiv(_debt_balance, _price, OptionLibrary.Multiplier()), "Negative equity.");
    _capital -= MulDiv(_debt_balance, _price, OptionLibrary.Multiplier());}

  function getMaxHedge() external view returns (uint256){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _deltaZero = calculateAggregateDelta(_price / 1e5, true);
    int256 _deltaMax = calculateAggregateDelta(_price * 1e5, true);
    return MulDiv(Math.max(_deltaZero>=0?uint256(_deltaZero):uint256(-_deltaZero), _deltaMax>=0?uint256(_deltaMax):uint256(-_deltaMax) ), _price, OptionLibrary.Multiplier());}

  function getSellPutCollateral() external view returns (uint256 _collateral){
    _collateral= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      uint256 _id = uint256(activeOptions.at(i));
      if(optionsList[_id].status== OptionLibrary.OptionStatus.Active && optionsList[_id].side == OptionLibrary.OptionSide.Sell && optionsList[_id].poType==OptionLibrary.PayoffType.Put){
      _collateral +=  optionsList[_id].calcNotionalExposure(optionsList[_id].strike);}}}

  function getContractPayoff(uint256 _id) external view returns(uint256 _payoff, uint256 _payback){
    (uint256 _price,) = volatilityChain.queryPrice();
    _payoff = optionsList[_id].calcPayoff(_price);
    _payback = _payoff;
    if(optionsList[_id].side == OptionLibrary.OptionSide.Sell && optionsList[_id].poType==OptionLibrary.PayoffType.Call){
      _payback =  optionsList[_id].calcNotionalExposure(_price) - _payoff;}
    if(optionsList[_id].side == OptionLibrary.OptionSide.Sell && optionsList[_id].poType==OptionLibrary.PayoffType.Put){
      _payback =  optionsList[_id].calcNotionalExposure(optionsList[_id].strike) - _payoff;}}

  function calculateContractDelta(uint256 _id, uint256 _price, bool _includeExpiring) public view returns(int256 _delta){
    _delta = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active && (_includeExpiring || (optionsList[_id].maturity > block.timestamp))){
      if(optionsList[_id].side==OptionLibrary.OptionSide.Buy){
        uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - Math.min(optionsList[_id].maturity, block.timestamp));
        _delta = int256(MulDiv(OptionLibrary.calcDelta(_price, optionsList[_id].strike, _vol), optionsList[_id].amount, OptionLibrary.Multiplier() ));
        if(optionsList[_id].poType==OptionLibrary.PayoffType.Put) {_delta = -int256(optionsList[_id].amount) + _delta; }}
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell && optionsList[_id].poType==OptionLibrary.PayoffType.Call){ 
        _delta = int256(optionsList[_id].amount);}}} // collateral for sell call options. zero for sell put options
    
  function calculateAggregateDelta(uint256 _price, bool _includeExpiring) public view returns(int256 _delta){
    _delta= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      _delta += calculateContractDelta(uint256(activeOptions.at(i)),_price, _includeExpiring);}}

  function calculateContractGamma(uint256 _id, uint256 _price) public view returns(int256 _gamma){
    _gamma = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active  && (optionsList[_id].maturity > block.timestamp)){
      uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - block.timestamp);
      _gamma = int256(MulDiv(OptionLibrary.calcGamma(_price, optionsList[_id].strike, _vol), optionsList[_id].amount, OptionLibrary.Multiplier() ));
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell){ _gamma = -_gamma;}}}
      
  function calculateAggregateGamma() external view returns(int256 _gamma){
    (uint256 _price,) = volatilityChain.queryPrice();
    _gamma= 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      _gamma += calculateContractGamma(uint256(activeOptions.at(i)),_price);}}

  function calculateSpotGamma() external view returns(int256 _gamma){
    uint256 _vol = volatilityChain.getVol(86400);
    _gamma = int256(OptionLibrary.calcGamma(OptionLibrary.Multiplier(), OptionLibrary.Multiplier(), _vol));}
    
  // function validateOption(uint256 _id, address _holder) external view {
  //   require(optionsList[_id].holder== _holder, "Not the owner.");
  //   require(optionsList[_id].maturity >= block.timestamp, "Option has expired.");
  //   require(optionsList[_id].status==OptionLibrary.OptionStatus.Active, "Not active option.");}

  function anyOptionExpiring() external view returns(bool _isExpiring) {
    _isExpiring = false;
    for(uint256 i=0;i<activeOptions.length();i++){
      if(isExpiring(uint256(activeOptions.at(i)))){
        _isExpiring = true;
        break;}}}

  function isExpiring(uint256 _id) public view returns (bool){ return (optionsList[_id].status== OptionLibrary.OptionStatus.Active) && (optionsList[_id].maturity <= block.timestamp);}

  function getExpiringOptionId() external view returns(uint256 _id){
    _id = 0;
    for(uint256 i=0;i<activeOptions.length();i++){
      if(isExpiring(uint256(activeOptions.at(i)))){
        _id = uint256(activeOptions.at(i));
        break;}}
  }

  function stampActiveOption(uint256 _id, address _holder) external onlyRole(EXCHANGE_ROLE) {
    optionsList[_id].effectiveTime = block.timestamp;
    optionsList[_id].maturity = optionsList[_id].effectiveTime + optionsList[_id].tenor;
    optionsList[_id].status = OptionLibrary.OptionStatus.Active;
    activeOptionsPerOwner[_holder].add(_id);
    activeOptions.add(_id);}

  function stampExercisedOption(uint256 _id) external onlyRole(EXCHANGE_ROLE){
    activeOptionsPerOwner[optionsList[_id].holder].remove(_id);
    activeOptions.remove(_id);
    optionsList[_id].status = OptionLibrary.OptionStatus.Exercised;
    optionsList[_id].exerciseTime = block.timestamp;}

  function stampExpiredOption(uint256 _id)  external onlyRole(EXCHANGE_ROLE){
    activeOptionsPerOwner[optionsList[_id].holder].remove(_id);
    activeOptions.remove(_id);
    optionsList[_id].status = OptionLibrary.OptionStatus.Expired;
    optionsList[_id].exerciseTime = block.timestamp;}

  // this function emits values in token decimals.
  function calcSwapTradesInTok(address _address, uint256 _swapSlippage) external view returns(int256 _tradeUnderlyingAmount, int256 _tradeFundingAmount){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _aggregateDelta = calculateAggregateDelta(_price, false);
    _tradeUnderlyingAmount = (_aggregateDelta >= 0? _aggregateDelta: int256(0)) - int256(MarketLibrary.balanceDef(underlying, _address));
    _tradeFundingAmount = MarketLibrary.cvtDecimalsInt(OptionLibrary.getOpposeTrade(_tradeUnderlyingAmount, _price, _swapSlippage), funding);
    _tradeUnderlyingAmount = MarketLibrary.cvtDecimalsInt(_tradeUnderlyingAmount, underlying);}
  
  // this function emits values in DEFAULT decimals.
  function getBalances(address _address) public view returns(uint256 _underlyingBalance, uint256 _fundingBalance, uint256 _collateralBalance, uint256 _debtBalance){
    address _protocolAds = ILendingPoolAddressesProvider(aaveAddress).getAddress("0x1");//bytes32(uint256(1)));
    ( _underlyingBalance, ,  _debtBalance) = MarketLibrary.getTokenBalances(_address, _protocolAds, underlying);
    ( _fundingBalance,  _collateralBalance,) = MarketLibrary.getTokenBalances(_address, _protocolAds, funding); }

  // this function emits values in token decimals.
  function calcLoanRepaymentInTok(address _address, uint256 _lendingPoolRateMode) external view returns(uint256 _repayAmount, uint256 _repaySwapValue){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _aggregateDelta = calculateAggregateDelta(_price, false);
    (int256 _loanTradeAmount, , ) = MarketLibrary.getLoanTrade(_address, ILendingPoolAddressesProvider(aaveAddress).getAddress("0x1"), _aggregateDelta, underlying, _lendingPoolRateMode == 2);
    _repayAmount = 0;
    _repaySwapValue = 0;
    if(_loanTradeAmount < 0){
      _repayAmount = uint256(-_loanTradeAmount) - Math.min(uint256(-_loanTradeAmount), ERC20(underlying).balanceOf(address(this)));
      _repaySwapValue = MarketLibrary.cvtDecimals(MulDiv(_repayAmount, _price, OptionLibrary.Multiplier()), funding);
      _repayAmount = MarketLibrary.cvtDecimals(_repayAmount, underlying);}}

  // this function emits values in token decimals.
  function calcLoanTradesInTok(address _address, uint256 _lendingPoolRateMode) external view returns(int256 _loanTradeAmount, int256 _collateralChange, address _loanAddress, address _collateralAddress){
    (uint256 _price,) = volatilityChain.queryPrice();
    int256 _aggregateDelta = calculateAggregateDelta(_price, false);
    address _protocolAds = ILendingPoolAddressesProvider(aaveAddress).getAddress("0x1");
    uint256 _targetLoan = 0;
    (_loanTradeAmount, _targetLoan, _loanAddress) = MarketLibrary.getLoanTrade(_address, _protocolAds, _aggregateDelta, underlying, _lendingPoolRateMode == 2);
    (_collateralChange, _collateralAddress) = MarketLibrary.getCollateralTrade(_address, _protocolAds, _targetLoan, _price, funding, underlying, overCollateral);
    _loanTradeAmount = MarketLibrary.cvtDecimalsInt(_loanTradeAmount, _loanAddress);
    _collateralChange =MarketLibrary.cvtDecimalsInt(_collateralChange, _collateralAddress);}

  function queryVol(uint256 _tenor) external view returns(uint256){return volatilityChain.getVol(_tenor);}
  function queryPrice() external view returns(uint256, uint256){return volatilityChain.queryPrice();}
  function tokenHash() external view returns (bytes32) {return volatilityChain.getTokenHash();}
  function resetOverCollateral(uint256 _overCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) { overCollateral= _overCollateral;}
}
