/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.0;

import "./FullMath.sol";
import "prb-math/contracts/PRBMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

library OptionLibrary {
  using FullMath for uint256;
  using FullMath for int256;
  // using PRBMath for uint256;

  enum PayoffType { Call, Put}
  enum OptionSide{ Buy, Sell}
  enum OptionStatus { Draft, Active, Exercised, Expired}
  
  struct Option { 
    PayoffType poType; OptionSide side; OptionStatus status; 
    address holder; uint256 id; 
    uint256 createTime; uint256 effectiveTime; 
    uint256 tenor; uint256 maturity; uint256 exerciseTime; 
    uint256 amount;
    uint256 spot;uint256 strike;
    uint256 volatility;
    uint256 premium;uint256 cost;}
  
  uint256 internal constant BASE  = 1e18;

  function calcIntrinsicValue(uint256 _strike, uint256 _price, uint256 _amount, PayoffType _poType) private pure returns(uint256){
      uint256 _intrinsicValue = 0;
      if((_poType == PayoffType.Call) && (_price > _strike)){ _intrinsicValue = _price - _strike; }
      if((_poType == PayoffType.Put) && (_price<_strike)){ _intrinsicValue = _strike - _price;}
      return _intrinsicValue.ethmul(_amount); }

  function calcTimeValue(uint256 _price, uint256 _vol, uint256 _strike, uint256 _atmPremium, uint256 _amount, uint256 _hedgeCost) private pure returns (uint256){
    if(_vol == 0) return 0;
    uint256 _m = _strike > _price? _price.ethdiv(_strike) : _strike.ethdiv(_price); // always in (0,1]
    uint256 _v = _vol > BASE? BASE: _vol; // always in (0, 1]
    return _atmPremium.muldiv(_v / 2, BASE + _v / 2 - _m).ethmul(_amount).accrue(_hedgeCost);}

  function calcPremium(uint256 _price, uint256 _vol, uint256 _strike, PayoffType _poType, uint256 _amount, uint256 _interest, uint256 _hedgeCost) external pure returns(uint256){
    int256 _atm_d = SafeCast.toInt256(_vol/ 2); // d value when at the money
    uint256 _discount = (_atm_d - SafeCast.toInt256(_vol)).logistic().discount(_interest);
    uint256 _atmPremium = _price.ethmul(_atm_d.logistic() - _discount);
    uint256 _timeValue = calcTimeValue(_price, _vol, _strike, _atmPremium, _amount, _hedgeCost);
    uint256 _intrinsicValue = calcIntrinsicValue(_strike, _price, _amount, _poType);
    return _intrinsicValue + _timeValue;}

  function calcCost(uint256 _price, uint256 _strike, uint256 _amount, PayoffType _poType, OptionSide _side, uint256 _premium) external pure returns (uint256 _cost) {
    _cost = _premium;
    if(_side == OptionSide.Sell){
      if(_poType == PayoffType.Put){ 
        _cost =  _amount.ethmul(_strike) - _premium;}
      else if(_poType == PayoffType.Call){ 
        _cost = _amount.ethmul(_price) - _premium;}}}

  function calcPayoff(Option storage _option, uint256 _price) public view returns(uint256){
    return calcIntrinsicValue(_option.strike, _price, _option.amount, _option.poType);}

  function calcNotionalExposure(Option storage _option, uint256 _price) public view returns(uint256){ 
    return _option.amount.ethmul(_price);}

  function calcDelta(Option storage _option, uint256 _price, uint256 _vol) public view returns(uint256 _delta){
    uint256 _moneyness = _price.ethdiv(_option.strike);
    int256 _d = SafeCast.toInt256(2 *  (_moneyness * BASE).sqrt().ethdiv(_vol)) - SafeCast.toInt256(2 * BASE.ethdiv(_vol)) + SafeCast.toInt256(_vol/ 2);
    _delta = _d.logistic().ethmul(_option.amount);}
  
  function calcGamma(uint256 _price, uint256 _strike, uint256 _vol) public pure returns(uint256 _gamma){
    uint256 _moneyness = _price.ethdiv(_strike);
    int256 _d = SafeCast.toInt256(2 * (_moneyness * BASE).sqrt().ethdiv(_vol)) - SafeCast.toInt256(2 * BASE.ethdiv(_vol)) + SafeCast.toInt256(_vol/ 2);
    _gamma = _d.normalDensity().ethdiv(_price).ethdiv(_vol);}

  function adjustSlippage(uint256 _amount, bool _adjustUpward, uint256 _slippage, uint256 _loanInterest) public pure returns (uint256 _adjustedAmount){
    _adjustedAmount = _amount;
    if(_adjustUpward) {
      _adjustedAmount = _amount.accrue(_slippage + _loanInterest);}
    else {
      _adjustedAmount = _amount.discount(_slippage+ _loanInterest);}}

  function getOpposeTrade(int256 _amount, uint256 _price, uint256 _slippage) external pure returns (int256 _oppositeAmount){
    _oppositeAmount = SafeCast.toInt256(adjustSlippage(_amount >=0 ? uint256(_amount): uint256(-_amount), _amount>0, _slippage, 0).ethmul(_price)) * (_amount >=0? int256(-1): int256(1));}

  function calcRiskPremiumAMM(uint256 _max, int256 _input, uint256 _constant, uint256 _volCapacityFactor) external pure returns(int256) {
    int256 _capacity = SafeCast.toInt256(BASE); // capacity should be in (0,2)
    if(_input < 0){_capacity +=  SafeCast.toInt256(uint256(-_input).muldiv(_volCapacityFactor, _max));}
    if(_input > 0){ _capacity -= SafeCast.toInt256(uint256(_input).muldiv(_volCapacityFactor, _max));}
    require(_capacity>=0,"Capacity breached.");
    return SafeCast.toInt256(_constant.ethdiv(uint256(_capacity))) - SafeCast.toInt256(_constant);}

}
