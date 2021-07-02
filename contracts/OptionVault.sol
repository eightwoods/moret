/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./MoretInterfaces.sol";

contract OptionVault is AccessControl
{
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;
  using OptionLibrary for OptionLibrary.Option;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  bytes32 public constant MARKET_MAKER_ROLE = keccak256("MARKET_MAKER_ROLE");

  mapping(uint256=> OptionLibrary.Option) internal optionsList;
  uint256 public optionCounter = 0;

  AggregatorV3Interface internal priceInterface;
  IVolatilityChain internal volatilityChain;
  EnumerableSet.AddressSet allowedMarketMakerAddresses;

  uint256 public priceMultiplier;
  uint256 public priceDecimals;
  uint256 internal pctDenominator = 10 ** 6;
  EnumerableSet.UintSet tenors;

  OptionLibrary.Percent public volPremiumFixedAddon = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6) ;
  OptionLibrary.Percent public deltaRange = OptionLibrary.Percent(8 * 10 ** 5, 10 ** 6) ;

  constructor(
      address _chainlinkAddress,
      address _volChainAddress
      )
      {
          _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
          _setupRole(ADMIN_ROLE, msg.sender);
          _setupRole(MARKET_MAKER_ROLE, msg.sender);

          priceInterface = AggregatorV3Interface(_chainlinkAddress);
          volatilityChain = IVolatilityChain(_volChainAddress);

          priceDecimals = priceInterface.decimals();
          priceMultiplier = 10 ** priceDecimals;

          tenors.add(1 days);
      }

    function descriptionHash() external view returns (bytes32)
    {
      return keccak256(abi.encodePacked(priceInterface.description()));
    }

    function addTenor(uint256 _tenor) external onlyRole(ADMIN_ROLE){
      require(!tenors.contains(_tenor));
      tenors.add(_tenor);
    }
    function removeTenor(uint256 _tenor) external onlyRole(ADMIN_ROLE){
      require(tenors.contains(_tenor));
      tenors.remove(_tenor);
    }
    function containsTenor(uint256 _tenor) external view returns (bool){
      return(tenors.contains(_tenor));
    }

    function addMarketMaker(address _adr) external onlyRole(ADMIN_ROLE){
      require(!allowedMarketMakerAddresses.contains(_adr));
      allowedMarketMakerAddresses.add(_adr);
    }
    function removeMarketMaker(address _adr) external onlyRole(ADMIN_ROLE){
      require(allowedMarketMakerAddresses.contains(_adr));
      allowedMarketMakerAddresses.remove(_adr);
    }

    function queryPrice() public view returns(uint256, uint256){
      (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
     return (uint256(_price), uint256(_timeStamp));
    }

    function queryVol(uint256 _tenor) public view returns (uint256){
      require(tenors.contains(_tenor));
      return volatilityChain.getVol(_tenor);
    }

    function queryOptionCost(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType, uint256 _amount,
      OptionLibrary.Percent memory _feeAddon, OptionLibrary.Percent memory _volAddon)
      external view returns(uint256, uint256)
    {
        require(tenors.contains(_tenor));
        require((_poType==OptionLibrary.PayoffType.Call) || (_poType==OptionLibrary.PayoffType.Put));

        (uint256 _price,) = queryPrice();
        uint256 _volatility = volatilityChain.getVol(_tenor);

        return  (OptionLibrary.calcPremium(_price, _volatility, _strike, _poType, _amount, _volAddon, priceMultiplier),
         OptionLibrary.calcFee(_amount, _feeAddon));
    }

    function checkVolSkew(uint256 _tenor, uint256 _strike) external view returns (uint256, uint256, uint256)
    {
        (uint256 _price,) = queryPrice();
        uint256 _volatility = volatilityChain.getVol(_tenor);
        return (_price, _volatility, OptionLibrary.calcVolSkew(_strike, _price, _volatility, priceMultiplier));
    }

    function addOption(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType,
      uint256 _amount, uint256 _premium, uint256 _fee)
    external onlyRole(MARKET_MAKER_ROLE) returns(uint256)
    {
        require(tenors.contains(_tenor), "Wrong option tenor.");
        require((_poType==OptionLibrary.PayoffType.Call) || (_poType==OptionLibrary.PayoffType.Put), "Use call or put option.");

        (uint256 _price,) = queryPrice();
        uint256 _volatility = volatilityChain.getVol(_tenor);

        optionCounter++;
        uint256 _id = optionCounter;
        optionsList[_id] = OptionLibrary.Option(
            _poType,
            msg.sender,
            OptionLibrary.OptionStatus.Draft,
            _id,
            block.timestamp,
            0,
            _tenor,
            0,
            _amount,
            _price,
            _strike,
            _volatility,
            _premium,
            _fee);

        return _id;
    }

    function queryDraftOptionCost(uint256 _id, bool _inVol) external view returns(uint256)
    {
        require(optionsList[_id].status== OptionLibrary.OptionStatus.Draft);
        return optionsList[_id].getCost(_inVol);
    }

    function queryDraftOptionFee(uint256 _id) external view returns(uint256)
    {
        require(optionsList[_id].status== OptionLibrary.OptionStatus.Draft);
        return optionsList[_id].fee;
    }

    function queryOptionPremium(uint256 _id) external view returns(uint256)
    {
        return optionsList[_id].premium;
    }
    function queryOptionExposure(uint256 _id, OptionLibrary.PayoffType _poType) external view returns(uint256)
    {
      if(optionsList[_id].poType==_poType)
      {
          return optionsList[_id].amount;
      }
      return 0;
    }

    function getOptionPayoffValue(uint256 _id) external view returns(uint256)
    {
        (uint256 _price,) = queryPrice();
        return optionsList[_id].calcPayoffValue(_price);
    }

    function getOptionHolder(uint256 _id) external view returns (address payable){
      return payable(optionsList[_id].holder);
    }

    function calculateContractDelta(uint256 _id) external view returns(int256){
      int256 _delta = 0;
      if(optionsList[_id].status== OptionLibrary.OptionStatus.Active)
      {
       (uint256 _price, ) = queryPrice();

        uint256 _vol1DAdjusted = (volatilityChain.getVol(86400) * deltaRange.numerator / deltaRange.denominator);
        uint256 _lowerRange = _price - (_price* _vol1DAdjusted/ priceMultiplier);
        uint256 _upperRange = _price * 2 - _lowerRange;

        _delta = int256(optionsList[_id].amount) / 2;
        if (optionsList[_id].poType==OptionLibrary.PayoffType.Call)
        {
          if(_upperRange < optionsList[_id].strike)
          {
            _delta = 0;
          }
          if(_lowerRange > optionsList[_id].strike)
          {
            _delta = int256(optionsList[_id].amount);
          }
        }

        if(optionsList[_id].poType==OptionLibrary.PayoffType.Put)
        {
            _delta *= -1;
          if(_upperRange < optionsList[_id].strike)
          {
            _delta = -int256(optionsList[_id].amount);
          }
          if(_lowerRange > optionsList[_id].strike)
          {
            _delta = 0;
          }
        }
      }
        return _delta;
    }


    function validateOption(uint256 _id, address _holder) external view {
      require(optionsList[_id].holder== _holder, "Not the owner.");
      require((optionsList[_id].effectiveTime + optionsList[_id].tenor) >= block.timestamp, "Option has expired.");
      require(optionsList[_id].status==OptionLibrary.OptionStatus.Active, "Not active option.");
    }

    function isOptionExpiring(uint256 _id) external view returns (bool)
    {
      return (optionsList[_id].status== OptionLibrary.OptionStatus.Draft) && ((optionsList[_id].effectiveTime + optionsList[_id].tenor) <= block.timestamp);
    }

    function stampActiveOption(uint256 _id) external onlyRole(MARKET_MAKER_ROLE) {
        optionsList[_id].effectiveTime = block.timestamp;
        optionsList[_id].status = OptionLibrary.OptionStatus.Active;
    }

    function stampExercisedOption(uint256 _id) external onlyRole(MARKET_MAKER_ROLE){
        optionsList[_id].exerciseTime = block.timestamp;
        optionsList[_id].status = OptionLibrary.OptionStatus.Exercised;
    }

    function stampExpiredOption(uint256 _id)  external onlyRole(MARKET_MAKER_ROLE){
        optionsList[_id].status = OptionLibrary.OptionStatus.Expired;
    }

    function getOption(uint256 _id) external view returns(OptionLibrary.Option memory) {
        return optionsList[_id];
    }

}
