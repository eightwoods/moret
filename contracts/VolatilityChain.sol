// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./libraries/MathLib.sol";
import "./interfaces/IVolatilityChain.sol";

contract VolatilityChain is Ownable, AccessControl, IVolatilityChain{
  using MathLib for uint256;
  using EnumerableSet for EnumerableSet.UintSet;

  bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE");
  AggregatorV3Interface internal priceInterface;
  bytes32 public tokenHash;
  EnumerableSet.UintSet tenors;

  mapping(uint256=>mapping(uint256=>PriceStamp)) private priceBook;
  mapping(uint256=>uint256) public latestBookTime;
  mapping(uint256=>EnumerableSet.UintSet) internal latestBookTimeSet;

  uint256 internal immutable priceMultiplier;

  mapping(uint256=> VolParam) internal volatilityParameters;
  mapping(uint256=>uint256) public sqrtRatios; 
  uint256 internal immutable volParamDecimals;
  uint256 internal immutable parameterMultiplier;

  uint256 internal constant SECONDS_1Y = 31536000; // 365 * 24 * 60 * 60
  uint256 internal constant TOLERANCE = 60; // 60s tolerance for updating timestamp

  constructor(AggregatorV3Interface _priceSource, uint256 _parameterDecimals, string memory _tokenName, address _updateAddress )  {
    require(_updateAddress != address(0), "0addr");

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); 

    _setupRole(UPDATE_ROLE, _updateAddress);
    tokenHash = keccak256(bytes(_tokenName));
    require(tenors.add(1 days),'-1d');
    require(tenors.add(7 days),'-7d');
    require(tenors.add(30 days),'-30d');

    priceInterface = _priceSource;
    priceMultiplier = 10 ** _priceSource.decimals();
    volParamDecimals = _parameterDecimals;
    parameterMultiplier = 10 ** _parameterDecimals;}

  function queryVol(uint256 _tenor) external override view returns(uint256 _vol){
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

      _vol = _vol.ethdiv(priceMultiplier);}

  function queryPrice() external override view returns(uint256){
    (,int _price,,,) = priceInterface.latestRoundData();
    return SafeCast.toUint256(_price).ethdiv(priceMultiplier);}

  function update(uint256 _tenor) external onlyRole(UPDATE_ROLE){
    require(tenors.contains(_tenor),"no such tenor");
    (,int _price,,uint _priceTime,) = priceInterface.latestRoundData();
    uint256 _updatePrice = SafeCast.toUint256(_price);
    
    // find the last time stamp available prior to the tenor period
    uint256 _baseTime = latestBookTime[_tenor];
    // EnumerableSet.UintSet storage _bookTimeSet = latestBookTimeSet[_tenor];
    uint256 _stampCount = latestBookTimeSet[_tenor].length();
    if(_stampCount > 0){
      for(uint256 i = _stampCount;i> 0;i--){
        uint256 _iTime = latestBookTimeSet[_tenor].at(i-1);
        
        if (_iTime <= (_priceTime - _tenor + TOLERANCE)) {
          if(_baseTime > (_priceTime - _tenor + TOLERANCE)){
            _baseTime = _iTime;
          }
          else{
            if (_iTime > _baseTime){
              require(latestBookTimeSet[_tenor].remove(_baseTime),'-baseTime');
              _baseTime = _iTime;
              }
            else if (_iTime < _baseTime){
              require(latestBookTimeSet[_tenor].remove(_iTime),'-iTime');
          }}}}}
    
    // update vols
    PriceStamp storage _baseStamp = priceBook[_tenor][_baseTime];
    PriceStamp storage _newStamp = priceBook[_tenor][_priceTime];
    _newStamp.startTime = _baseTime;
    _newStamp.endTime = _priceTime;
    _newStamp.open = _baseStamp.close;
    _newStamp.close = _updatePrice;

    uint256 _open = _newStamp.open;
    uint256 _priceMove = (_open < _updatePrice)? (_updatePrice.muldiv(priceMultiplier, _open) - priceMultiplier) : (priceMultiplier - _updatePrice.muldiv( priceMultiplier, _open));
    _priceMove = _priceMove.muldiv(_tenor.sqrt(), (_priceTime-_baseTime).sqrt());

    VolParam storage _volParameter = volatilityParameters[_tenor];
    _newStamp.volatility = (_volParameter.ltVolWeighted + (_priceMove * _priceMove).muldiv( _volParameter.q, parameterMultiplier) + (_baseStamp.volatility * _baseStamp.volatility).muldiv( _volParameter.p, parameterMultiplier)).sqrt();

    latestBookTime[_tenor] = _priceTime;
    require(latestBookTimeSet[_tenor].add(_priceTime),'-priceTime');
    emit NewVolatilityChainBlock(_tenor, _priceTime, _updatePrice, _newStamp.volatility, _baseTime);}

  function resetVolParams(uint256 _tenor, VolParam memory _volParams) external onlyOwner{
    if(!tenors.contains(_tenor)){
      require(tenors.add(_tenor),'-t');}

    sqrtRatios[_tenor] = SECONDS_1Y.ethdiv(_tenor).sqrt() * 1e9; // in 18 decimal places
    
    require((_volParams.w + _volParams.p + _volParams.q)==parameterMultiplier, '-SUM');
    volatilityParameters[_tenor] = _volParams;
    volatilityParameters[_tenor].ltVolWeighted = (volatilityParameters[_tenor].ltVol*volatilityParameters[_tenor].ltVol).muldiv( volatilityParameters[_tenor].w, parameterMultiplier);

    (,int _price,,uint _priceTime,) = priceInterface.latestRoundData();
    uint256 _updatePrice = SafeCast.toUint256(_price);

    latestBookTime[_tenor] = _priceTime;
    latestBookTimeSet[_tenor].add(_priceTime);

    PriceStamp storage _priceStamp = priceBook[_tenor][_priceTime];
    _priceStamp.startTime = _priceStamp.endTime = _priceTime;
    _priceStamp.volatility = volatilityParameters[_tenor].initialVol;
    _priceStamp.open = _priceStamp.close = _updatePrice;
    emit ResetVolChainParameter(_tenor, block.timestamp, msg.sender);}

  function removeTenor(uint256 _tenor) external onlyOwner{
    require(tenors.contains(_tenor), '-tenor');
    require(tenors.remove(_tenor), '-remove');
    emit RemovedTenor(_tenor, block.timestamp, msg.sender);}

  function getPriceBook(uint256 _tenor) external view returns(PriceStamp memory){
    require(tenors.contains(_tenor), "Input tenor not allowed.");
    return priceBook[_tenor][latestBookTime[_tenor]];}

  function getSqrtRatio(uint256 _tenor) external view returns(uint256){
    if(tenors.contains(_tenor)){
      return sqrtRatios[_tenor];
    }
    else{
      return SECONDS_1Y.ethdiv(_tenor).sqrt() * 1e9; // in 18 decimal places
    }
    }

  function getLatestBookTimeSet(uint256 _tenor) external view returns(uint256[] memory){
    return latestBookTimeSet[_tenor].values();
  }
}
