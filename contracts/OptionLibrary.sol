/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity 0.8.9;

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

  function calcTimeValue(uint256 _strike, uint256 _price, uint256 _volatility, uint256 _amount) private pure returns (uint256){
    if(_volatility == 0) return _volatility;
    uint256 _moneyness = _strike > _price? (_price * DefaultMultiplier / _strike) : (_strike * DefaultMultiplier / _price); // always in (0,1]
    uint256 _midPoint = DefaultMultiplier - (_volatility > DefaultMultiplier? DefaultMultiplier: _volatility) / 2 ; // always in [0.5, 1]
    uint256 _a = 2 * DefaultMultiplier - _midPoint; // always in [1, 1.5]
    uint256 _b = DefaultMultiplier - _midPoint; // always in [0, 0.5]
    return MulDiv(_amount * 4, MulDiv(_b,  _volatility, _a - _moneyness), 10 * DefaultMultiplier);}

  function calcPremium(uint256 _price, uint256 _volatility, uint256 _strike, PayoffType _poType, uint256 _amount) public pure returns(uint256){
      uint256 _intrinsicValue = calcIntrinsicValue(_strike, _price, _amount, _poType);
      uint256 _timeValue = MulDiv(calcTimeValue(_strike, _price, _volatility, _amount), _price, DefaultMultiplier);
      return _intrinsicValue + _timeValue;}

  function calcPayoff(Option storage _option, uint256 _price) public view returns(uint256){
    return calcIntrinsicValue(_option.strike, _price, _option.amount, _option.poType);}

  function calcNotionalExposure(Option storage _option, uint256 _price) public view returns(uint256){ return MulDiv(_option.amount, _price, DefaultMultiplier);}

  function calcDelta(uint256 _price, uint256 _strike, uint256 _vol) public pure returns(uint256 _delta){
    uint256 _moneyness = MulDiv(_price, DefaultMultiplier, _strike);
    int256 _d = int256(MulDiv(2 * DefaultMultiplier,  (_moneyness * DefaultMultiplier).sqrt(), _vol)) - int256(MulDiv(2 * DefaultMultiplier,  DefaultMultiplier, _vol)) + int256(_vol/ 2);
    _delta = Logistic(_d);}
  
  function calcGamma(uint256 _price, uint256 _strike, uint256 _vol) public pure returns(uint256 _gamma){
    uint256 _moneyness = MulDiv(_price, DefaultMultiplier, _strike);
    int256 _d = int256(MulDiv(2 * DefaultMultiplier,  (_moneyness * DefaultMultiplier).sqrt(), _vol)) - int256(MulDiv(2 * DefaultMultiplier,  DefaultMultiplier, _vol)) + int256(_vol/ 2);
    _gamma = MulDiv(MulDiv(NormalDensity(_d), DefaultMultiplier, _price), DefaultMultiplier, _vol);}

  function adjustSlippage(uint256 _amount, bool _adjustUpward, uint256 _slippage, uint256 _loanInterest) public pure returns (uint256 _adjustedAmount){
    _adjustedAmount = _amount;
    if(_adjustUpward) _adjustedAmount = MulDiv(_amount, DefaultMultiplier + _slippage + _loanInterest, DefaultMultiplier);
    if(!_adjustUpward) _adjustedAmount = MulDiv(_amount, DefaultMultiplier, DefaultMultiplier + _slippage+ _loanInterest);}

  function getOpposeTrade(int256 _amount, uint256 _price, uint256 _slippage) external pure returns (int256 _oppositeAmount){
    _oppositeAmount = int256(MulDiv(adjustSlippage(_amount >=0 ? uint256(_amount): uint256(-_amount), _amount>0, _slippage, 0), _price, DefaultMultiplier)) * (_amount >=0? int256(-1): int256(1));}

}
