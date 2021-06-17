pragma solidity ^0.8.4;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/* import "../interfaces/Interfaces.sol"; */

import "./FullMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import "https://github.com/smartcontractkit/chainlink/blob/master/evm-contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

 contract VolatilityChain is Ownable, AccessControl
 {
       using EnumerableSet for EnumerableSet.UintSet;

     bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE");

   AggregatorV3Interface internal priceInterface;
   bytes32 public tokenHash;
   string public description;

  EnumerableSet.UintSet tenors;


   mapping(uint256=>mapping(uint256=>PriceStamp)) private priceBook;
   mapping(uint256=>uint256) private latestBookTime;
   uint256 public decimals;
   uint256 private priceMultiplier;

    uint256 public volatilityUpdateCounter;
    uint256 public volatilityUpdateTime;
    mapping(uint256=> VolParam) public volatilityParameters;
   uint256 public volParamDecimals;
   uint256 private parameterMultiplier;

   struct PriceStamp{
    uint256 startTime;
    uint256 endTime;
    uint256 open;
    uint256 highest;
    uint256 lowest;
    uint256 volatility;
  }

  struct VolParam{
      uint256 initialVol;
      uint256 ltVol;
      uint256 ltVolWeighted;
      uint256 w; // parameter for long-term average
      uint256 p; // parameter for moving average
      uint256 q; // paramter for auto regression
  }

   constructor(
     address _priceSourceId,
     uint256 _parameterDecimals,
      string memory _tokenName
     )  {

         _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

         tokenHash = keccak256(abi.encodePacked(_tokenName));


      tenors.add(1 days);

    priceInterface = AggregatorV3Interface(_priceSourceId);
    description = priceInterface.description();
    decimals = priceInterface.decimals();
    priceMultiplier = 10 ** decimals;

    volParamDecimals = _parameterDecimals;
    parameterMultiplier = 10 ** _parameterDecimals;

   }

   function getVol(uint256 _tenor) external view returns(uint256)
   {
       require(tenors.contains(_tenor), "Input option tenor is not allowed.");
     return priceBook[_tenor][latestBookTime[_tenor]].volatility;
    }

  function queryPrice() public view returns(uint256, uint256){
    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
   return (uint256(_price), uint256(_timeStamp));
  }

   function update() external onlyRole(UPDATE_ROLE){
     (uint _updatePrice, uint _timeStamp) = queryPrice();

     for(uint i = 0;i< tenors.length();i++)
     {
       uint256 _tenor = tenors.at(i);

       if(_updatePrice > priceBook[_tenor][latestBookTime[_tenor]].highest)
       {
         priceBook[_tenor][latestBookTime[_tenor]].highest=_updatePrice;
       }
       if(_updatePrice<priceBook[_tenor][latestBookTime[_tenor]].lowest)
       {
         priceBook[_tenor][latestBookTime[_tenor]].lowest=_updatePrice;
       }

       if(_timeStamp>= (latestBookTime[_tenor] + _tenor))
       {
         PriceStamp memory _currentStamp = priceBook[_tenor][latestBookTime[_tenor]];
         uint256 _latestMove = Math.max(MulDiv(_currentStamp.highest, priceMultiplier, _currentStamp.open) - priceMultiplier , priceMultiplier - MulDiv(_currentStamp.lowest, priceMultiplier, _currentStamp.open ));
         uint256 _latestVolatility = Sqrt(volatilityParameters[_tenor].ltVolWeighted + MulDiv(_latestMove * _latestMove, volatilityParameters[_tenor].q, parameterMultiplier) + MulDiv(_currentStamp.volatility * _currentStamp.volatility, volatilityParameters[_tenor].p, parameterMultiplier));

         priceBook[_tenor][latestBookTime[_tenor]].endTime = _timeStamp;

         priceBook[_tenor][_timeStamp].startTime = _timeStamp;
         priceBook[_tenor][_timeStamp].volatility = _latestVolatility;
         priceBook[_tenor][_timeStamp].open = priceBook[_tenor][_timeStamp].highest = priceBook[_tenor][_timeStamp].lowest = _updatePrice;

         latestBookTime[_tenor] = _timeStamp;

         emit VolatilityUpdated(_timeStamp, _tenor, _updatePrice, _latestVolatility);

       }

     }

     volatilityUpdateTime = _timeStamp;
     volatilityUpdateCounter ++;
     emit OneUpdateCompleted(_timeStamp, _updatePrice, volatilityUpdateCounter);
   }

   function resetVolParamsList(uint256[] memory _tenorList, VolParam memory _volParams) public onlyOwner{
     require((_volParams.w + _volParams.p + _volParams.q)==parameterMultiplier);

     for(uint256 i = 0;i<_tenorList.length;i++){
       if(!tenors.contains(_tenorList[i]))
       {
         tenors.add(_tenorList[i]);
       }
       resetVolParams(_tenorList[i], _volParams);
      }
   }

   function resetVolParams(uint256 _tenor, VolParam memory _volParams) public onlyOwner{
       require(tenors.contains(_tenor));
       require((_volParams.w + _volParams.p + _volParams.q)==parameterMultiplier);
       volatilityParameters[_tenor] = _volParams;
       volatilityParameters[_tenor].ltVolWeighted = MulDiv(volatilityParameters[_tenor].ltVol*volatilityParameters[_tenor].ltVol, volatilityParameters[_tenor].w, parameterMultiplier);

        (uint _updatePrice, uint _timeStamp) = queryPrice();
        latestBookTime[_tenor] = _timeStamp;
       priceBook[_tenor][_timeStamp].startTime = _timeStamp;
       priceBook[_tenor][_timeStamp].volatility = volatilityParameters[_tenor].initialVol;
       priceBook[_tenor][_timeStamp].open = priceBook[_tenor][_timeStamp].highest = priceBook[_tenor][_timeStamp].lowest = _updatePrice;

        emit NewParameters(_tenor, volatilityParameters[_tenor]);
   }

   function removeTenor(uint256 _tenor) public onlyOwner{
     require(tenors.contains(_tenor));
     tenors.remove(_tenor);
   }

   /* function displayTenors() public view returns(uint256[] memory)
{
  uint256[] memory _displayTenors;
  for(uint256 i = 0;i<tenors.length();i++)
  {
    _displayTenors.push(tenors.at(i));
  }
  return _displayTenors;
} */
   function displayPriceBook(uint256 _tenor) external view returns(PriceStamp memory){
        require(tenors.contains(_tenor), "Input option tenor is not allowed.");
       return priceBook[_tenor][latestBookTime[_tenor]];
   }

    event OneUpdateCompleted(uint256 _updateTime, uint256 _updatePrice, uint256 _counter);
    event VolatilityUpdated(uint256 _updateTime, uint256 _tenor, uint256 _updatePrice, uint256 _updateVolatility);
    event NewTenor(uint256 _newTenor);
    event NewParameters(uint256 _tenor, VolParam _volParams);
 }
