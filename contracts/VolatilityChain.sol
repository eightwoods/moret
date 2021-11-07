// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./FullMath.sol";
import {IVolatilityChain} from "./MoretInterfaces.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract VolatilityChain is Ownable, AccessControl, IVolatilityChain{
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
      if(_upperTenor == 0) { _vol = _lowerVol;}
      if(_lowerTenor==0) {_vol = _upperVol;}
      if(_upperTenor >0 && _lowerTenor >0){ _vol = MulDiv(_lowerVol, _upperTenor - _tenor, _upperTenor - _lowerTenor) + MulDiv(_upperVol, _tenor - _lowerTenor, _upperTenor - _lowerTenor);}}
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
        uint256 _periodMove = (priceBook[_tenor][latestBookTime[_tenor]].open < _updatePrice)? (MulDiv(_updatePrice, priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open) - priceMultiplier) : (priceMultiplier - MulDiv(_updatePrice, priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open ));
        uint256 _largestMove = Math.max(MulDiv(priceBook[_tenor][latestBookTime[_tenor]].highest, priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open) - priceMultiplier , priceMultiplier - MulDiv(priceBook[_tenor][latestBookTime[_tenor]].lowest, priceMultiplier, priceBook[_tenor][latestBookTime[_tenor]].open ));

        priceBook[_tenor][_timeStamp].startTime = _timeStamp;
        priceBook[_tenor][_timeStamp].volatility = Sqrt(volatilityParameters[_tenor].ltVolWeighted + MulDiv(_periodMove * _periodMove, volatilityParameters[_tenor].q, parameterMultiplier) + MulDiv(priceBook[_tenor][latestBookTime[_tenor]].volatility * priceBook[_tenor][latestBookTime[_tenor]].volatility, volatilityParameters[_tenor].p, parameterMultiplier));
        priceBook[_tenor][_timeStamp].accentus = Sqrt(volatilityParameters[_tenor].ltVolWeighted + MulDiv(_largestMove * _largestMove, volatilityParameters[_tenor].q, parameterMultiplier) + MulDiv(priceBook[_tenor][latestBookTime[_tenor]].accentus * priceBook[_tenor][latestBookTime[_tenor]].accentus, volatilityParameters[_tenor].p, parameterMultiplier));
        priceBook[_tenor][_timeStamp].open = priceBook[_tenor][_timeStamp].highest = priceBook[_tenor][_timeStamp].lowest = _updatePrice;

        latestBookTime[_tenor] = _timeStamp;
        emit volatilityChainBlockAdded(_tenor, _timeStamp, priceBook[_tenor][_timeStamp]);} }

    volatilityUpdateTime = _timeStamp;
    volatilityUpdateCounter ++;}

  function resetVolParams(uint256 _tenor, VolParam memory _volParams) external onlyOwner{
    require(tenors.contains(_tenor));
    require((_volParams.w + _volParams.p + _volParams.q)==parameterMultiplier);
    volatilityParameters[_tenor] = _volParams;
    volatilityParameters[_tenor].ltVolWeighted = MulDiv(volatilityParameters[_tenor].ltVol*volatilityParameters[_tenor].ltVol, volatilityParameters[_tenor].w, parameterMultiplier);

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

  // function getPriceMultiplier() external override view returns (uint256){return priceMultiplier;}
  // function getPriceDecimals() external override view returns (uint256) {return priceDecimals;}
  function getDecription() external override view returns (string memory) {return description;}}
