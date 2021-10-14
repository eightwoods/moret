/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "./FullMath.sol";
import "prb-math/contracts/PRBMathSD59x18.sol";

library OptionLibrary {
  using PRBMathSD59x18 for int256;
  enum PayoffType { Call, Put}
  enum OptionSide{ Buy, Sell}
  enum OptionStatus { Draft, Active, Exercised, Expired}
  struct Option { PayoffType poType; OptionSide side; OptionStatus status; address holder; uint256 id; uint256 createTime; uint256 effectiveTime; uint256 tenor; uint256 maturity; uint256 exerciseTime; uint256 amount;uint256 spot;uint256 strike;uint256 volatility;uint256 premium;uint256 cost;}
  struct Percent{ uint256 numerator; uint256 denominator;}

  function calcIntrinsicValue(uint256 _strike, uint256 _price, uint256 _amount, PayoffType _poType, uint256 _priceMultiplier) private pure returns(uint256){
      uint256 _intrinsicValue = 0;
      if((_poType == PayoffType.Call) && (_price > _strike)){ _intrinsicValue = _price - _strike; }
      if((_poType == PayoffType.Put) && (_price<_strike)){ _intrinsicValue = _strike - _price;}
      return MulDiv(_intrinsicValue, _amount, _priceMultiplier); }

  function calcTimeValue(uint256 _strike, uint256 _price, uint256 _volatility, uint256 _amount, uint256 _priceMultiplier) private pure returns (uint256){
    if(_volatility == 0) return _volatility;
    uint256 _moneyness = _strike > _price? (_price * _priceMultiplier / _strike) : (_strike * _priceMultiplier / _price); // always in (0,1]
    uint256 _midPoint = _priceMultiplier - (_volatility > _priceMultiplier? _priceMultiplier: _volatility) / 2 ; // always in [0.5, 1]
    uint256 _a = 2 * _priceMultiplier - _midPoint; // always in [1, 1.5]
    uint256 _b = _priceMultiplier - _midPoint; // always in [0, 0.5]
    return MulDiv(_amount * 4, MulDiv(_b,  _volatility, _a - _moneyness), 10 * _priceMultiplier);}

  function calcPremium(uint256 _price, uint256 _volatility, uint256 _strike, PayoffType _poType, uint256 _amount, uint256 _priceMultiplier) public pure returns(uint256){
      uint256 _intrinsicValue = calcIntrinsicValue(_strike, _price, _amount, _poType, _priceMultiplier);
      uint256 _timeValue = MulDiv(calcTimeValue(_strike, _price, _volatility, _amount, _priceMultiplier), _price, _priceMultiplier);
      return _intrinsicValue + _timeValue;}

  function calcPayoff(Option storage _option, uint256 _price, uint256 _priceMultiplier) public view returns(uint256){
    return calcIntrinsicValue(_option.strike, _price, _option.amount, _option.poType, _priceMultiplier);}

  function calcDelta(uint256 _price, uint256 _strike, uint256 _priceMultiplier, uint256 _vol) public pure returns(uint256 _delta){
    uint256 _moneyness = MulDiv(_price, _priceMultiplier, _strike);
    int256 _d = int256(MulDiv(2 , (_moneyness * _priceMultiplier).sqrt(), _vol)) - int256(MulDiv(2,  _priceMultiplier, _vol)) + int256(_vol / 2);
    _delta = Logistic(_d);}
  
  function calcGamma(uint256 _price, uint256 _strike, uint256 _priceMultiplier, uint256 _vol) public pure returns(uint256 _gamma){
    uint256 _moneyness = MulDiv(_price, _priceMultiplier, _strike);
    int256 _d = int256(MulDiv(2 , (_moneyness * _priceMultiplier).sqrt(), _vol)) - int256(MulDiv(2,  _priceMultiplier, _vol)) + int256(_vol / 2);
    _gamma = MulDiv(MulDiv(NormalDensity(_d), _priceMultiplier, _price), _priceMultiplier, _vol);}

  // function getCost(Option storage _option, bool _inVol) public view returns(uint256){
  //   if(_inVol)
  //   {
  //     return (_option.premium + _option.fee)  * _option.spot / _option.volatility;
  //   }
  //   return _option.premium + _option.fee;
  // }

}
