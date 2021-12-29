// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./FullMath.sol";
import "./interfaces/IVolatilityChain.sol";

contract VolatilityChain is Ownable, AccessControl, IVolatilityChain{
  using FullMath for uint256;
  using EnumerableSet for EnumerableSet.UintSet;

  bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE");
  AggregatorV3Interface internal priceInterface;
  bytes32 public tokenHash;
  string public description;
  EnumerableSet.UintSet tenors;

  mapping(uint256=>mapping(uint256=>PriceStamp)) private priceBook;
  mapping(uint256=>uint256) public latestBookTime;
  uint256 internal priceDecimals;
  uint256 internal priceMultiplier;
  uint256 internal quoteAdjustment;

  uint256 public volatilityUpdateCounter;
  uint256 public volatilityUpdateTime;
  mapping(uint256=> VolParam) public volatilityParameters;
  uint256 public volParamDecimals;
  uint256 internal parameterMultiplier;

  constructor( address _priceSourceId, uint256 _parameterDecimals, string memory _tokenName )  {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(UPDATE_ROLE, msg.sender);
    tokenHash = keccak256(abi.encodePacked(_tokenName));
    tenors.add(1 days);
    tenors.add(7 days);
    tenors.add(30 days);

    priceInterface = AggregatorV3Interface(_priceSourceId);
    description = priceInterface.description();
    priceMultiplier = 10 ** priceInterface.decimals();
    quoteAdjustment = 10 ** (18 - priceInterface.decimals());
    volParamDecimals = _parameterDecimals;
    parameterMultiplier = 10 ** _parameterDecimals;}

  function getVol(uint256 _tenor) external override view returns(uint256 _vol){
    _vol = 0;
    if(tenors.contains(_tenor)){ _vol = priceBook[_tenor][latestBookTime[_tenor]].volatility;}
    if(!tenors.contains(_tenor)){
      uint256 _upperTenor = 0;
      uint256 _lowerTenor = 0;
      uint256 _upperVol = 0;
      uint256 _lowerVol = 0;
      for(uint i = 0;i< tenors.length();i++){
        uint256 _tenorI = tenors.at(i);
        if(_tenorI >_tenor && (_tenorI < _upperTenor || _upperTenor == 0) ){ _upperTenor = _tenorI; _upperVol = priceBook[_tenorI][latestBookTime[_tenorI]].volatility; }
        if(_tenorI <_tenor && (_tenorI > _lowerTenor || _lowerTenor == 0) ){ _lowerTenor = _tenorI; _lowerVol = priceBook[_tenorI][latestBookTime[_tenorI]].volatility; }}
      if(_upperTenor == 0 && _lowerTenor > 0) { _vol = _lowerVol.muldiv(_tenor.sqrt() , _lowerTenor.sqrt());}
      if(_lowerTenor==0 && _upperTenor > 0) {_vol = _upperVol.muldiv( _tenor.sqrt()) , _upperTenor.sqrt());}
      if(_upperTenor >0 && _lowerTenor >0){ _vol = _lowerVol.muldiv( _upperTenor - _tenor, _upperTenor - _lowerTenor) + _upperVol.muldiv( _tenor - _lowerTenor, _upperTenor - _lowerTenor);}}
      _vol *= quoteAdjustment;}

  function queryPrice() external override view returns(uint256, uint256){
    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
    return (uint256(_price) * quoteAdjustment, uint256(_timeStamp));}

  function update() external onlyRole(UPDATE_ROLE){
    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
    uint256 _updatePrice = uint256(_price);

    for(uint i = 0;i< tenors.length();i++) {
      uint256 _tenor = tenors.at(i);
      if(_updatePrice > priceBook[_tenor][latestBookTime[_tenor]].highest){
        priceBook[_tenor][latestBookTime[_tenor]].highest=_updatePrice;}
      if(_updatePrice<priceBook[_tenor][latestBookTime[_tenor]].lowest){
         priceBook[_tenor][latestBookTime[_tenor]].lowest=_updatePrice;}

      if(_timeStamp>= (latestBookTime[_tenor] + _tenor)){
        priceBook[_tenor][latestBookTime[_tenor]].endTime = _timeStamp;
        priceBook[_tenor][latestBookTime[_tenor]].close = _updatePrice;
        uint256 _periodMove = (priceBook[_tenor][latestBookTime[_tenor]].open < _updatePrice)? (_updatePrice.muldiv( priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open) - priceMultiplier) : (priceMultiplier - _updatePrice.muldiv( priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open ));
        uint256 _largestMove = Math.max(priceBook[_tenor][latestBookTime[_tenor]].highest.muldiv(priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open) - priceMultiplier , priceMultiplier - priceBook[_tenor][latestBookTime[_tenor]].lowest.muldiv( priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open ));

        priceBook[_tenor][_timeStamp].startTime = _timeStamp;
        priceBook[_tenor][_timeStamp].volatility = (volatilityParameters[_tenor].ltVolWeighted + (_periodMove * _periodMove).muldiv( volatilityParameters[_tenor].q, parameterMultiplier) + (priceBook[_tenor][latestBookTime[_tenor]].volatility * priceBook[_tenor][latestBookTime[_tenor]].volatility).muldiv( volatilityParameters[_tenor].p, parameterMultiplier)).sqrt();
        priceBook[_tenor][_timeStamp].accentus = (volatilityParameters[_tenor].ltVolWeighted + (_largestMove * _largestMove).muldiv( volatilityParameters[_tenor].q, parameterMultiplier) + (priceBook[_tenor][latestBookTime[_tenor]].accentus * priceBook[_tenor][latestBookTime[_tenor]].accentus).muldiv( volatilityParameters[_tenor].p, parameterMultiplier)).sqrt();
        priceBook[_tenor][_timeStamp].open = priceBook[_tenor][_timeStamp].highest = priceBook[_tenor][_timeStamp].lowest = _updatePrice;

        latestBookTime[_tenor] = _timeStamp;
        emit NewVolatilityChainBlock(_tenor, _timeStamp, priceBook[_tenor][_timeStamp]);} }

    volatilityUpdateTime = _timeStamp;
    volatilityUpdateCounter ++;}

  function resetVolParams(uint256 _tenor, VolParam memory _volParams) external onlyOwner{
    if(!tenors.contains(_tenor)){
      tenors.add(_tenor);}
    require((_volParams.w + _volParams.p + _volParams.q)==parameterMultiplier);
    volatilityParameters[_tenor] = _volParams;
    volatilityParameters[_tenor].ltVolWeighted = (volatilityParameters[_tenor].ltVol*volatilityParameters[_tenor].ltVol).muldiv( volatilityParameters[_tenor].w, parameterMultiplier);

    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
    uint256 _updatePrice = uint256(_price);

    latestBookTime[_tenor] = _timeStamp;
    priceBook[_tenor][_timeStamp].startTime = _timeStamp;
    priceBook[_tenor][_timeStamp].volatility = priceBook[_tenor][_timeStamp].accentus = volatilityParameters[_tenor].initialVol;
    priceBook[_tenor][_timeStamp].open = priceBook[_tenor][_timeStamp].highest = priceBook[_tenor][_timeStamp].lowest = _updatePrice;}

  function removeTenor(uint256 _tenor) external onlyOwner{
    require(tenors.contains(_tenor));
    tenors.remove(_tenor);}

  function getPriceBook(uint256 _tenor) external view returns(PriceStamp memory){
    require(tenors.contains(_tenor), "Input option tenor is not allowed.");
    return priceBook[_tenor][latestBookTime[_tenor]];}

  function getTokenHash() external override view returns(bytes32){return tokenHash;}}
