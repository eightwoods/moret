// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./FullMath.sol";
import "./interfaces/IVolatilityChain.sol";

contract VolatilityChain is Ownable, AccessControl, IVolatilityChain{
  using FullMath for uint256;
  using EnumerableSet for EnumerableSet.UintSet;

  bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE");
  AggregatorV3Interface internal priceInterface;
  bytes32 public tokenHash;
  EnumerableSet.UintSet tenors;

  mapping(uint256=>mapping(uint256=>PriceStamp)) private priceBook;
  mapping(uint256=>uint256) public latestBookTime;

  uint256 internal immutable priceMultiplier;

  uint256 public volatilityUpdateCounter;
  uint256 public volatilityUpdateTime;

  mapping(uint256=> VolParam) internal volatilityParameters;
  uint256 internal immutable volParamDecimals;
  uint256 internal immutable parameterMultiplier;

  constructor( AggregatorV3Interface _priceSource, uint256 _parameterDecimals, string memory _tokenName )  {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(UPDATE_ROLE, msg.sender);
    tokenHash = keccak256(bytes(_tokenName));
    tenors.add(1 days);
    tenors.add(7 days);
    tenors.add(30 days);

    priceInterface = _priceSource;
    priceMultiplier = 10 ** _priceSource.decimals();
    volParamDecimals = _parameterDecimals;
    parameterMultiplier = 10 ** _parameterDecimals;}

  function getVol(uint256 _tenor) external view returns(uint256 _vol){
    _vol = 0;
    if(tenors.contains(_tenor)){ 
      _vol = priceBook[_tenor][latestBookTime[_tenor]].volatility;}
    else {
      uint256 _upperTenor = 0;
      uint256 _lowerTenor = 0;
      uint _tenorsCount = tenors.length();

      for(uint i = 0;i< _tenorsCount;i++){
        uint256 _tenorI = tenors.at(i);
        if(_tenorI >_tenor && (_tenorI < _upperTenor || _upperTenor == 0) ){ 
          _upperTenor = _tenorI; }
        if(_tenorI <_tenor && (_tenorI > _lowerTenor || _lowerTenor == 0) ){ 
          _lowerTenor = _tenorI; }}

      if(_upperTenor == 0 && _lowerTenor > 0) { 
        uint256 _lowerVol = priceBook[_lowerTenor][latestBookTime[_lowerTenor]].volatility;
        _vol = _lowerVol.muldiv(_tenor.sqrt() , _lowerTenor.sqrt());}
      else if(_lowerTenor==0 && _upperTenor > 0) {
        uint256 _upperVol = priceBook[_upperTenor][latestBookTime[_upperTenor]].volatility;
        _vol = _upperVol.muldiv( _tenor.sqrt() , _upperTenor.sqrt());}
      else if(_upperTenor >0 && _lowerTenor >0){ 
        uint256 _lowerVol = priceBook[_lowerTenor][latestBookTime[_lowerTenor]].volatility;
        uint256 _upperVol = priceBook[_upperTenor][latestBookTime[_upperTenor]].volatility;
        uint256 _tenorInterval = _upperTenor - _lowerTenor;
        _vol = _lowerVol.muldiv( _upperTenor - _tenor,  _tenorInterval) + _upperVol.muldiv( _tenor - _lowerTenor, _tenorInterval);}}

      _vol *= _vol.ethdiv(priceMultiplier);}

  function queryPrice() external view returns(uint256, uint256){
    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
    return (SafeCast.toUint256(_price).ethdiv(priceMultiplier), _timeStamp);}

  function update() external onlyRole(UPDATE_ROLE){
    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
    uint256 _updatePrice = SafeCast.toUint256(_price);
    uint _tenorsCount = tenors.length();

    for(uint i = 0;i< _tenorsCount;i++) {
      uint256 _tenor = tenors.at(i);
      uint256 _latestTimeStamp = latestBookTime[_tenor];
      PriceStamp storage _priceStamp = priceBook[_tenor][_latestTimeStamp];
      if(_updatePrice > _priceStamp.highest){
        _priceStamp.highest=_updatePrice;}
      if(_updatePrice<_priceStamp.lowest){
         _priceStamp.lowest=_updatePrice;}

      if(_timeStamp>= (_latestTimeStamp + _tenor)){
        _priceStamp.endTime = _timeStamp;
        _priceStamp.close = _updatePrice;
        uint256 _open = _priceStamp.open;
        uint256 _periodMove = (_open < _updatePrice)? (_updatePrice.muldiv( priceMultiplier, _open) - priceMultiplier) : (priceMultiplier - _updatePrice.muldiv( priceMultiplier, _open ));
        uint256 _largestMove = Math.max(_priceStamp.highest.muldiv(priceMultiplier, _open) - priceMultiplier , priceMultiplier - _priceStamp.lowest.muldiv( priceMultiplier, _open ));

        PriceStamp storage _newPriceStamp = priceBook[_tenor][_timeStamp];
        VolParam storage _volParameter = volatilityParameters[_tenor];
        _newPriceStamp.startTime = _timeStamp;
        _newPriceStamp.volatility = (_volParameter.ltVolWeighted + (_periodMove * _periodMove).muldiv( _volParameter.q, parameterMultiplier) + (_priceStamp.volatility * _priceStamp.volatility).muldiv( _volParameter.p, parameterMultiplier)).sqrt();
        _newPriceStamp.accentus = (_volParameter.ltVolWeighted + (_largestMove * _largestMove).muldiv( _volParameter.q, parameterMultiplier) + (_priceStamp.accentus * _priceStamp.accentus).muldiv( _volParameter.p, parameterMultiplier)).sqrt();
        _newPriceStamp.open = _newPriceStamp.highest = _newPriceStamp.lowest = _updatePrice;

        latestBookTime[_tenor] = _timeStamp;
        emit NewVolatilityChainBlock(_tenor, _timeStamp, _newPriceStamp);} }

    volatilityUpdateTime = _timeStamp;
    volatilityUpdateCounter ++;}

  function resetVolParams(uint256 _tenor, VolParam memory _volParams) external onlyOwner{
    if(!tenors.contains(_tenor)){
      tenors.add(_tenor);}
    require((_volParams.w + _volParams.p + _volParams.q)==parameterMultiplier);
    volatilityParameters[_tenor] = _volParams;
    volatilityParameters[_tenor].ltVolWeighted = (volatilityParameters[_tenor].ltVol*volatilityParameters[_tenor].ltVol).muldiv( volatilityParameters[_tenor].w, parameterMultiplier);

    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
    uint256 _updatePrice = SafeCast.toUint256(_price);

    latestBookTime[_tenor] = _timeStamp;
    PriceStamp storage _priceStamp = priceBook[_tenor][_timeStamp];
    _priceStamp.startTime = _timeStamp;
    _priceStamp.volatility = _priceStamp.accentus = volatilityParameters[_tenor].initialVol;
    _priceStamp.open = _priceStamp.highest = _priceStamp.lowest = _updatePrice;
    emit ResetParameter(_tenor, block.timestamp, msg.sender);}

  function removeTenor(uint256 _tenor) external onlyOwner{
    require(tenors.contains(_tenor));
    tenors.remove(_tenor);
    emit RemovedTenor(_tenor, block.timestamp, msg.sender);}

  function getPriceBook(uint256 _tenor) external view returns(PriceStamp memory){
    require(tenors.contains(_tenor), "Input option tenor is not allowed.");
    return priceBook[_tenor][latestBookTime[_tenor]];}
  }
