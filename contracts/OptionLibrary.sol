/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity 0.8.10;

import "./FullMath.sol";
import "prb-math/contracts/PRBMath.sol";

library OptionLibrary {
  using PRBMath for uint256;
  enum PayoffType { Call, Put}
  enum OptionSide{ Buy, Sell}
  enum OptionStatus { Draft, Active, Exercised, Expired}
  struct Option { PayoffType poType; OptionSide side; OptionStatus status; address holder; uint256 id; uint256 createTime; uint256 effectiveTime; uint256 tenor; uint256 maturity; uint256 exerciseTime; uint256 amount;uint256 spot;uint256 strike;uint256 volatility;uint256 premium;uint256 cost;}
  struct Percent{ uint256 numerator; uint256 denominator;}
  uint256 public constant DefaultMultiplier  = 10 ** 18;
  uint256 public constant DefaultDecimals = 18;
  uint256 public constant AnnualSeconds = 31536000; // 365 * 24 * 60 * 60

  function Multiplier() public pure returns (uint256){return DefaultMultiplier;}
  function Decimals() public pure returns (uint256) {return DefaultDecimals;}
  function ToDefaultDecimals(uint256 _rawData, uint256 _rawDataDecimals) public pure returns(uint256){
    require(DefaultDecimals >= _rawDataDecimals);
    return _rawData * (10** (DefaultDecimals - _rawDataDecimals));}
  function ToCustomDecimals(uint256 _rawData, uint256 _rawDataDecimals) public pure returns(uint256){
    require(DefaultDecimals >= _rawDataDecimals);
    return _rawData / (10** (DefaultDecimals - _rawDataDecimals));}

  function calcIntrinsicValue(uint256 _strike, uint256 _price, uint256 _amount, PayoffType _poType) private pure returns(uint256){
      uint256 _intrinsicValue = 0;
      if((_poType == PayoffType.Call) && (_price > _strike)){ _intrinsicValue = _price - _strike; }
      if((_poType == PayoffType.Put) && (_price<_strike)){ _intrinsicValue = _strike - _price;}
      return MulDiv(_intrinsicValue, _amount, DefaultMultiplier); }

  function calcTimeValue(uint256 _price, uint256 _vol, uint256 _strike, uint256 _atmPremium) private pure returns (uint256){
    if(_vol == 0) return _vol;
    uint256 _moneyness = _strike > _price? (_price * DefaultMultiplier / _strike) : (_strike * DefaultMultiplier / _price); // always in (0,1]
    uint256 _midPoint = DefaultMultiplier - (_vol > DefaultMultiplier? DefaultMultiplier: _vol) / 2 ; // always in [0.5, 1]
    uint256 _a = 2 * DefaultMultiplier - _midPoint; // always in [1, 1.5]
    uint256 _b = DefaultMultiplier - _midPoint; // always in [0, 0.5]
    // return MulDiv(_amount * 4, MulDiv(_b,  _vol, _a - _moneyness), 10 * DefaultMultiplier);}
    return MulDiv(_atmPremium, _b, _a - _moneyness);}

  function calcPremium(uint256 _price, uint256 _vol, uint256 _strike, PayoffType _poType, uint256 _amount, uint256 _interest) public pure returns(uint256){
    int256 _d = int256(MulDiv(2 * DefaultMultiplier, DefaultMultiplier, _vol)) - int256(MulDiv(2 * DefaultMultiplier,  DefaultMultiplier, _vol)) + int256(_vol/ 2);
    uint256 _discount = MulDiv(Logistic(_d - int256(_vol)), DefaultMultiplier, DefaultMultiplier + _interest);
    uint256 _atmPremium = MulDiv(_price, Logistic(_d) - _discount, DefaultMultiplier);
    uint256 _timeValue = MulDiv(_amount, calcTimeValue(_price, _vol, _strike, _atmPremium), DefaultMultiplier);
    uint256 _intrinsicValue = calcIntrinsicValue(_strike, _price, _amount, _poType);
    return _intrinsicValue + _timeValue;}

  function calcOptionCost(uint256 _price, uint256 _strike, uint256 _amount, uint256 _vol, PayoffType _poType, OptionSide _side, uint256 _interest) external pure returns(uint256 _premium, uint256 _cost) {
    _premium = calcPremium(_price, _vol, _strike, _poType, _amount, _interest);
    _cost = _premium;
    if(_side == OptionSide.Sell && _poType == PayoffType.Put){ _cost = MulDiv(_amount, _strike, DefaultMultiplier) - _cost;}
    if(_side == OptionSide.Sell && _poType == PayoffType.Call){ _cost = MulDiv(_amount, _price, DefaultMultiplier) - _cost;}}

  function calcPayoff(Option storage _option, uint256 _price) public view returns(uint256){
    return calcIntrinsicValue(_option.strike, _price, _option.amount, _option.poType);}

  function calcNotionalExposure(Option storage _option, uint256 _price) public view returns(uint256){ 
    return MulDiv(_option.amount, _price, DefaultMultiplier);}

  function calcDelta(Option storage _option, uint256 _price, uint256 _vol) public view returns(uint256 _delta){
    uint256 _moneyness = MulDiv(_price, DefaultMultiplier, _option.strike);
    int256 _d = int256(MulDiv(2 * DefaultMultiplier,  (_moneyness * DefaultMultiplier).sqrt(), _vol)) - int256(MulDiv(2 * DefaultMultiplier,  DefaultMultiplier, _vol)) + int256(_vol/ 2);
    _delta = MulDiv(Logistic(_d), _option.amount, DefaultMultiplier);}
  
  function calcGamma(uint256 _price, uint256 _strike, uint256 _vol) public pure returns(uint256 _gamma){
    uint256 _moneyness = MulDiv(_price, DefaultMultiplier, _strike);
    int256 _d = int256(MulDiv(2 * DefaultMultiplier,  (_moneyness * DefaultMultiplier).sqrt(), _vol)) - int256(MulDiv(2 * DefaultMultiplier,  DefaultMultiplier, _vol)) + int256(_vol/ 2);
    _gamma = MulDiv(MulDiv(NormalDensity(_d), DefaultMultiplier, _price), DefaultMultiplier, _vol);}

  function adjustStrike(uint256 _strike, PayoffType _poType, OptionSide _side, uint256 _slippage, uint256 _loanInterest) external pure returns(uint256 _adjustedStrike){
    _adjustedStrike = adjustSlippage(_strike, false, _slippage, 0); // downward
    if((_poType==PayoffType.Put && _side == OptionSide.Buy) || (_poType==PayoffType.Call && _side == OptionSide.Sell)){ 
      _adjustedStrike = adjustSlippage(_strike,true, _slippage, _loanInterest);} //upward
  }

  function adjustSlippage(uint256 _amount, bool _adjustUpward, uint256 _slippage, uint256 _loanInterest) public pure returns (uint256 _adjustedAmount){
    _adjustedAmount = _amount;
    if(_adjustUpward) _adjustedAmount = MulDiv(_amount, DefaultMultiplier + _slippage + _loanInterest, DefaultMultiplier);
    if(!_adjustUpward) _adjustedAmount = MulDiv(_amount, DefaultMultiplier, DefaultMultiplier + _slippage+ _loanInterest);}

  function getOpposeTrade(int256 _amount, uint256 _price, uint256 _slippage) external pure returns (int256 _oppositeAmount){
    _oppositeAmount = int256(MulDiv(adjustSlippage(_amount >=0 ? uint256(_amount): uint256(-_amount), _amount>0, _slippage, 0), _price, DefaultMultiplier)) * (_amount >=0? int256(-1): int256(1));}

  function calcRiskPremiumAMM(uint256 _max, int256 _input, uint256 _constant, uint256 _volCapacityFactor) external pure returns(int256) {
    int256 _capacity = int256(DefaultMultiplier); // capacity should be in (0,2)
    if(_input < 0){_capacity +=  int256(MulDiv(uint256(-_input), _volCapacityFactor, _max));}
    if(_input > 0){ _capacity -= int256(MulDiv(uint256(_input) , _volCapacityFactor, _max));}
    require(_capacity>=0,"Capacity breached.");
    return int256(MulDiv(_constant, DefaultMultiplier, uint256(_capacity))) - int256(_constant);}

}
