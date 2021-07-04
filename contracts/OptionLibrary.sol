/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

library OptionLibrary {
  enum PayoffType { Call, Put}
  enum OptionSide{ Buy, Sell}
  enum OptionStatus { Draft, Active, Exercised, Expired}

  struct Option {
      PayoffType poType;
      OptionSide side;
      OptionStatus status;
      address holder;
      uint256 id;
      uint256 createTime;
      uint256 effectiveTime;
      uint256 tenor;
      uint256 exerciseTime;

      uint256 amount;
      uint256 spot;
      uint256 strike;
      uint256 volatility;
      uint256 premium;
      uint256 fee;
  }

  struct Percent{
    uint256 numerator;
    uint256 denominator;
  }

  function calcIntrinsicValue(uint256 _strike, uint256 _price, uint256 _amount, PayoffType _poType) public pure returns(uint256)
  {
      uint256 _intrinsicValue = 0;

      if((_poType == PayoffType.Call) && (_price > _strike)){
        _intrinsicValue = _price - _strike;
      }
      if((_poType == PayoffType.Put) && (_price<_strike)){
        _intrinsicValue = _strike - _price;
      }
      return _intrinsicValue * _amount / _price;
  }

  function calcVolSkew(uint256 _strike, uint256 _price, uint256 _volatility, uint256 _priceMultiplier) public pure returns (uint256)
  {
    if(_volatility == 0)
       return _volatility;

    uint256 _moneyness = _strike > _price? (_price * _priceMultiplier / _strike) : (_strike * _priceMultiplier / _price); // always in (0,1]

    uint256 _midPoint = _priceMultiplier - (_volatility > _priceMultiplier? _priceMultiplier: _volatility) / 2 ; // always in [0.5, 1]
    uint256 _a = 2 * _priceMultiplier - _midPoint; // always in [1, 1.5]
    uint256 _b = _priceMultiplier - _midPoint; // always in [0, 0.5]

    return _b * _volatility / (_a - _moneyness);
  }

  function calcTimeValue(uint _volatility, uint256 _amount, uint256 _priceMultiplier) public pure returns(uint256)
  {
      return _amount * _volatility / _priceMultiplier * 4 / 10;
  }

  function calcPremium(uint256 _price, uint256 _volatility, uint256 _strike, PayoffType _poType, uint256 _amount, uint256 _priceMultiplier)
    public pure returns(uint256){
      uint256 _intrinsicValue = calcIntrinsicValue(_strike, _price, _amount, _poType);
      uint256 _timeValue = calcTimeValue(calcVolSkew(_strike, _price, _volatility, _priceMultiplier), _amount, _priceMultiplier);

      return _intrinsicValue + _timeValue;
  }

  function calcFee(uint256 _amount, Percent memory _feeAddon) public pure returns(uint256)
  {
      return _amount * _feeAddon.numerator / _feeAddon.denominator;
  }

  function getCost(Option storage _option, bool _inVol) public view returns(uint256){
    if(_inVol)
    {
      return (_option.premium + _option.fee)  * _option.spot / _option.volatility;
    }
    return _option.premium + _option.fee;
  }

  function calcPayoffValue(Option storage _option, uint256 _price) public view returns(uint256)
  {
      uint256 _intrinsicValue = 0;

      if((_option.poType == PayoffType.Call) && (_price > _option.strike)){
        _intrinsicValue = _price - _option.strike;
      }
      if((_option.poType == PayoffType.Put) && (_price<_option.strike)){
        _intrinsicValue = _option.strike - _price;
      }
      return _intrinsicValue * _option.amount / _price;
  }

}
