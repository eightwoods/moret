// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MathLib.sol";

library OptionLib {
  using MathLib for uint256;
  using MathLib for int256;

  enum PayoffType { Call, Put}
  enum OptionSide{ Buy, Sell}
  enum OptionStatus { Draft, Active, Exercised, Expired}

  uint256 internal constant SECONDS_1Y = 31536000; // 365 * 24 * 60 * 60

  // Items: option type, option side, contract status, contract holder address, contract id, creation timestamp, effective timestamp, tenor in seconds, maturity timestamp, excersie timestamp, amount or size of contract, current spot price, option strike, implied volatility, calculated premium and total cost including collaterals.
  struct Option { 
    PayoffType poType; OptionSide side; OptionStatus status; 
    address holder; uint256 id; 
    uint256 createTime; uint256 effectiveTime; 
    uint256 tenor; uint256 maturity; uint256 exerciseTime; 
    uint256 amount;
    uint256 spot; uint256 strike;
    uint256 volatility;
    uint256 premium;uint256 cost;
    address pool;}
  
  uint256 internal constant BASE  = 1e18;

  function calcIntrinsicValue(Option memory _option, uint256 _price) public pure returns(uint256){
    uint256 _intrinsicValue = 0;
    if((_option.poType == PayoffType.Call) && (_price > _option.strike)){ _intrinsicValue = _price - _option.strike; }
    if((_option.poType == PayoffType.Put) && (_price < _option.strike)){ _intrinsicValue = _option.strike - _price;}
    return _intrinsicValue.ethmul(_option.amount); }

  function calcTimeValue(Option memory _option, uint256 _price, uint256 _volatilityByT, uint256 _atmPremium) public pure returns (uint256){
    if(_volatilityByT == 0) return 0;
    uint256 _m = _option.strike > _price? _price.ethdiv(_option.strike) : _option.strike.ethdiv(_price); // always in (0,1]
    uint256 _v = _volatilityByT > BASE? BASE: _volatilityByT; // always in (0, 1]
    return _atmPremium.muldiv(_v / 2, BASE + _v / 2 - _m).ethmul(_option.amount);}

  function calcPremium(Option memory _option, uint256 _price, uint256 _volatilityByT, uint256 _loanInterest) public pure returns(uint256 _premium){
    uint256 _interest = _loanInterest.muldiv( _option.tenor, SECONDS_1Y);

    int256 _atm_d = SafeCast.toInt256(_volatilityByT/ 2); // d value when at the money
    uint256 _discount = (_atm_d - SafeCast.toInt256(_volatilityByT)).logistic().discount(_interest);
    uint256 _atmPremium = _price.ethmul(_atm_d.logistic() - _discount);
    uint256 _timeValue = calcTimeValue(_option,  _price, _volatilityByT, _atmPremium);
    uint256 _intrinsicValue = calcIntrinsicValue(_option, _price);
    _premium = _intrinsicValue + _timeValue;}

  function calcCollateral(Option memory _option) public pure returns(uint256 _collateral){
    if(_option.side == OptionSide.Sell){
      if(_option.poType == PayoffType.Put){ 
        _collateral =  _option.amount.ethmul(_option.strike);}
      else if(_option.poType == PayoffType.Call){ 
        _collateral = _option.amount.ethmul(_option.spot);}}
  }

  // function calcCost(OptionSide _side, uint256 _premium) public pure returns (uint256 _cost) {
  //   _cost = _premium;
  //   if(_side == OptionSide.Sell){
  //     if(_poType == PayoffType.Put){ 
  //       _cost =  _amount.ethmul(_strike) - _premium;}
  //     else if(_poType == PayoffType.Call){ 
  //       _cost = _amount.ethmul(_price) - _premium;}}}

  // payoff is the premium of options, payback is the amount owned to the option holder including both the signed amount of payoff and paid collaterals.
  function calcPayoff(Option storage _option, uint256 _price) public view returns(uint256 _payoff, uint256 _payback, uint256 _collateral){
    _payoff = calcIntrinsicValue(_option, _price);
    _payback = _payoff;
    _collateral = 0;
    if(_option.side == OptionSide.Sell){
      if (_option.poType == PayoffType.Call){
        _collateral = _option.amount.ethmul(_price);
        _payback = _collateral - _payoff;}
      else if(_option.poType == PayoffType.Put){
        _collateral = _option.amount.ethmul(_option.strike);
        _payback = _collateral - _payoff;}}}

  function getNetNotional(Option storage _option) public view returns(int256 _netNotional){
    _netNotional = SafeCast.toInt256(_option.amount);
    if(_option.side == OptionSide.Sell) {_netNotional = -_netNotional;}}

  function sellPutCollateral(Option storage _option) public view returns (uint256 _collateral){
    if(_option.side == OptionSide.Sell && _option.poType == PayoffType.Put) _collateral = _option.amount.ethmul(_option.strike);}

  function calcRemainingMaturity(Option storage _option) public view returns(uint256 _maturityLeft){
    _maturityLeft = _option.maturity - Math.min(_option.maturity, block.timestamp);}

  function calcDelta(Option storage _option, uint256 _price, uint256 _vol, bool _includeExpiring) public view returns(int256 _delta){
    _delta = 0;
    if(_option.status== OptionStatus.Active && (_includeExpiring || (_option.maturity > block.timestamp))){
      if(_option.side== OptionSide.Buy){
        uint256 _moneyness = _price.ethdiv(_option.strike);
        int256 _d = SafeCast.toInt256(2 *  (_moneyness * BASE).sqrt().ethdiv(_vol)) - SafeCast.toInt256(2 * BASE.ethdiv(_vol)) + SafeCast.toInt256(_vol/ 2);
        _delta = SafeCast.toInt256(_d.logistic().ethmul(_option.amount));
        if(_option.poType == PayoffType.Put) {
          _delta = -SafeCast.toInt256(_option.amount) + _delta; }}
      else if(_option.side== OptionSide.Sell && _option.poType== PayoffType.Call){ 
        _delta = SafeCast.toInt256(_option.amount);}}} // collateral for sell call options. zero for sell put options  

  function calcDeltaAtZero(Option storage _option) public view returns(uint256 _delta){
    _delta = _option.poType == PayoffType.Call? _option.amount: 0;}

  function calcDeltaAtMax(Option storage _option) public view returns(uint256 _delta){
    _delta = (_option.poType == PayoffType.Put && _option.side== OptionSide.Buy)? _option.amount: 0;}
  
  function calcGamma(uint256 _price, uint256 _strike, uint256 _vol) public pure returns(uint256 _gamma){
    uint256 _moneyness = _price.ethdiv(_strike);
    int256 _d = SafeCast.toInt256(2 * (_moneyness * BASE).sqrt().ethdiv(_vol)) - SafeCast.toInt256(2 * BASE.ethdiv(_vol)) + SafeCast.toInt256(_vol/ 2);
    _gamma = _d.normalDensity().ethdiv(_price).ethdiv(_vol);}
  
  function isExpiring(Option storage _option) public view returns (bool){ 
    return (_option.status== OptionStatus.Active) && (_option.maturity <= block.timestamp);}

  

  // Returns premium, costs (if sell option, cost includes collateral) and implied volatility
  // function calcCost(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLib.PayoffType _poType, OptionLib.OptionSide _side) public view returns(uint256 , uint256 , uint256 ){
  //   uint256 _price = volChain.queryPrice();
  //   return calcOptionCost(_tenor, _price, _strike, _amount, _poType, _side);}


}
