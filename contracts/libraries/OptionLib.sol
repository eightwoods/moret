// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MathLib.sol";

library OptionLib {
  using MathLib for uint256;
  using SignedMath for int256;
  using MathLib for int256;
  using Math for uint256;

  enum PayoffType { Call, Put, CallSpread, PutSpread}
  enum OptionSide{ Buy, Sell}
  enum OptionStatus { Draft, Active, Exercised, Expired}
  enum PaymentMethod { USDC, Token, Vol}

  uint256 internal constant SECONDS_1Y = 31536000; // 365 * 24 * 60 * 60

  // Items: option type, option side, contract status, contract holder address, contract id, creation timestamp, effective timestamp, tenor in seconds, maturity timestamp, excersie timestamp, amount or size of contract, current spot price, option strike, implied volatility, calculated premium and total cost including collaterals.
  struct Option { 
    PayoffType poType; OptionSide side; OptionStatus status; 
    address holder; uint256 id; 
    uint256 createTime; uint256 effectiveTime; 
    uint256 tenor; uint256 maturity; uint256 exerciseTime; 
    uint256 amount;
    uint256 spot; uint256 strike; uint256 spread;
    uint256 volatility;
    uint256 premium;uint256 cost;
    address pool;
    int256 exposure;}
  
  uint256 internal constant BASE  = 1e18;

  function calcIntrinsicValue(Option memory _option, uint256 _price) public pure returns(uint256){
    uint256 _intrinsicValue = 0;
    if((_option.poType == PayoffType.Call) && (_price > _option.strike)){ _intrinsicValue = _price - _option.strike; }
    if((_option.poType == PayoffType.Put) && (_price < _option.strike)){ _intrinsicValue = _option.strike - _price;}
    if((_option.poType == PayoffType.CallSpread) && (_price > _option.strike)) {
      if(_price >= _option.strike + _option.spread){ _intrinsicValue = _option.spread;}
      else{ _intrinsicValue = _price - _option.strike; }}
    if((_option.poType == PayoffType.PutSpread) && (_price < _option.strike)){
      require(_option.strike > _option.spread, "option spread wrong");
      if(_price <= _option.strike - _option.spread){ _intrinsicValue = _option.spread;}
      else{_intrinsicValue = _option.strike - _price;}
    }
    return _intrinsicValue.ethmul(_option.amount); }

  function calcTimeValue(uint256 _strike, uint256 _amount, uint256 _price, uint256 _volatilityByT, uint256 _atmPremium) public pure returns (uint256){
    if(_volatilityByT == 0) return 0;
    uint256 _m = _strike > _price? _price.ethdiv(_strike) : _strike.ethdiv(_price); // always in (0,1]
    uint256 _v = _volatilityByT > BASE? BASE: _volatilityByT; // always in (0, 1]
    return _atmPremium.muldiv(_v / 2, BASE + _v / 2 - _m).ethmul(_amount);}

  function calcPremium(Option memory _option, uint256 _price, uint256 _volatilityByT, uint256 _loanInterest) external pure returns(uint256 _premium){
    uint256 _intrinsicValue = calcIntrinsicValue(_option, _price);

    uint256 _interest = _loanInterest.muldiv( _option.tenor, SECONDS_1Y);
    int256 _atm_d = SafeCast.toInt256(_volatilityByT/ 2); // d value when at the money
    uint256 _discount = (_atm_d - SafeCast.toInt256(_volatilityByT)).logistic().discount(_interest);
    uint256 _atmPremium = _price.ethmul(_atm_d.logistic() - _discount);
    
    uint256 _timeValue = calcTimeValue(_option.strike, _option.amount, _price, _volatilityByT, _atmPremium);
    uint256 _spreadTimeValue = 0;
    if(_option.poType == PayoffType.CallSpread){
      _spreadTimeValue = calcTimeValue(_option.strike + _option.spread, _option.amount, _price, _volatilityByT, _atmPremium);
    }
    else if(_option.poType == PayoffType.PutSpread){
      require(_option.strike > _option.spread, "option spread wrong");
      _spreadTimeValue = calcTimeValue(_option.strike - _option.spread, _option.amount, _price, _volatilityByT, _atmPremium);
    }
    
    require((_intrinsicValue + _timeValue) >= _spreadTimeValue, "wrong time value");
    _premium = _intrinsicValue + _timeValue - _spreadTimeValue;}

  function calcCollateral(Option memory _option, uint256 _price, uint256 _premium) external pure returns(uint256 _collateral){
    if(_option.side == OptionSide.Sell){
      if(_option.poType == PayoffType.Put){ 
        _collateral =  _option.amount.ethmul(_option.strike).max(_premium);}
      else if(_option.poType == PayoffType.Call){ 
        _collateral = _option.amount.ethmul(_price).max(_premium);}}
      else if(_option.poType == PayoffType.PutSpread || _option.poType == PayoffType.CallSpread){ 
        _collateral =  _option.amount.ethmul(_option.spread).max(_premium);}
  }

  // payoff is the premium of options, payback is the amount owned to the option holder including both the signed amount of payoff and paid collaterals.
  function calcPayoff(Option storage _option, uint256 _price) external view returns(uint256 _payoff, uint256 _payback, uint256 _collateral){
    _payoff = calcIntrinsicValue(_option, _price);
    _payback = _payoff;
    _collateral = 0;
    if(_option.side == OptionSide.Sell){
      if (_option.poType == PayoffType.Call){
        _collateral = _option.amount.ethmul(_price);
        _payback = _collateral - _collateral.min(_payoff);}
      else if(_option.poType == PayoffType.Put){
        _collateral = _option.amount.ethmul(_option.strike);
        _payback = _collateral - _collateral.min(_payoff);}
      else if(_option.poType == PayoffType.PutSpread || _option.poType == PayoffType.CallSpread){ 
        _collateral = _option.amount.ethmul(_option.spread);
        _payback = _collateral - _collateral.min(_payoff);}
      }}

  function getUnderCollateral(Option storage _option) external view returns(uint256 _collateral){
    if(_option.side == OptionSide.Sell && _option.poType == PayoffType.Call) {
      _collateral = _option.amount;}
      }

  function sellFundCollateral(Option storage _option) external view returns (uint256 _collateral){
    if(_option.side == OptionSide.Sell){
      if(_option.poType == PayoffType.Put) {
        _collateral = _option.amount.ethmul(_option.strike);}
      else if(_option.poType == PayoffType.PutSpread || _option.poType == PayoffType.CallSpread){
        _collateral = _option.amount.ethmul(_option.spread);}
    } }

  function quoteCallVol(Option memory _option, uint256 _price, uint256 _volatilityByT, uint256 _volCapacityFactor, int256 _currentExposureUp, uint256 _maxExposure) external pure returns(uint256 _impVol, int256 _exposureUp){
    _exposureUp = calcDelta(_option, _price, _volatilityByT);
    int256 _newExposure = _currentExposureUp + _exposureUp;
    _impVol = calcRiskPremium(_maxExposure, _currentExposureUp, _newExposure, _volatilityByT , _volCapacityFactor);
  }

  function quotePutVol(Option memory _option, uint256 _price, uint256 _volatilityByT, uint256 _volCapacityFactor, int256 _currentExposureDown, uint256 _maxExposure) external pure returns(uint256 _impVol, int256 _exposureDown){
    _exposureDown = calcDelta(_option, _price, _volatilityByT);
    int256 _newExposure = _currentExposureDown + _exposureDown;
    _impVol = calcRiskPremium(_maxExposure, -_currentExposureDown, -_newExposure, _volatilityByT , _volCapacityFactor);
  }

  function calcDelta(Option memory _option, uint256 _price, uint256 _volatilityByT) public pure returns(int256 _delta){
    _delta = delta(_price, _option.strike, _volatilityByT, _option.amount);
    if(_option.poType == PayoffType.Put){
      _delta = -SafeCast.toInt256(_option.amount) + _delta;
    }
    else if (_option.poType == PayoffType.PutSpread){
      require(_option.strike > _option.spread, "option spread wrong");
      int256 _spreadDelta = delta(_price, _option.strike - _option.spread, _volatilityByT, _option.amount);
      _delta = _delta - _spreadDelta;
    }
    else if (_option.poType == PayoffType.CallSpread){
      int256 _spreadDelta = delta(_price, _option.strike + _option.spread, _volatilityByT, _option.amount);
      _delta = _delta - _spreadDelta;
    }

    if(_option.side== OptionSide.Sell){
      _delta = -_delta;
    }
  }
  
  function delta(uint256 _price, uint256 _strike, uint256 _vol, uint256 _amount) public pure returns(int256 _delta){
    uint256 _moneyness = _price.ethdiv(_strike);
    int256 _d = SafeCast.toInt256(2 *  (_moneyness * BASE).sqrt().ethdiv(_vol)) - SafeCast.toInt256(2 * BASE.ethdiv(_vol)) + SafeCast.toInt256(_vol/ 2);
    _delta = SafeCast.toInt256(_d.logistic().ethmul(_amount));
  }

  function calcRiskPremium(uint256 _maxExposure, int256 _currentExposure, int256 _newExposure, uint256 _runningVol,uint256 _volCapacityFactor ) public pure returns(uint256){
    int256 _riskPremium = calcRiskPremiumAMM(_maxExposure, _currentExposure,  _runningVol, _volCapacityFactor).average(calcRiskPremiumAMM(_maxExposure, _newExposure, _runningVol, _volCapacityFactor));
    require((SafeCast.toInt256(_runningVol) + _riskPremium) > 0,"Incorrect vol premium");
    return SafeCast.toUint256(SafeCast.toInt256(_runningVol) + _riskPremium); 
  }

  function calcRiskPremiumAMM(uint256 _max, int256 _input, uint256 _constant, uint256 _volCapacityFactor) public pure returns(int256) {
    int256 _capacity = SafeCast.toInt256(BASE); // capacity should be in (0,2)
    if(_input < 0){_capacity +=  SafeCast.toInt256(uint256(-_input).muldiv(_volCapacityFactor, _max));}
    if(_input > 0){ _capacity -= SafeCast.toInt256(uint256(_input).muldiv(_volCapacityFactor, _max));}
    require(_capacity>=0 , "Capacity breached.");
    return SafeCast.toInt256(_constant.ethdiv(uint256(_capacity))) - SafeCast.toInt256(_constant);}
  
  function isExpiring(Option storage _option) external view returns (bool){ 
    return (_option.status== OptionStatus.Active) && (_option.maturity <= block.timestamp);}

}
