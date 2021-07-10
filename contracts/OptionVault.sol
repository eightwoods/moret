/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./FullMath.sol";

contract OptionVault is AccessControl
{
  using OptionLibrary for OptionLibrary.Option;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");

  mapping(uint256=> OptionLibrary.Option) internal optionsList;
  uint256 public optionCounter = 0;

  IVolatilityChain internal volatilityChain;
  uint256 internal ethMultiplier = 10 ** 18;
  uint256 internal pctDenominator = 10 ** 6;

  OptionLibrary.Percent public volPremiumFixedAddon = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6) ;
  OptionLibrary.Percent public deltaRange = OptionLibrary.Percent(8 * 10 ** 5, 10 ** 6) ;

  constructor(
      address _volChainAddress
      )
      {
          _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
          _setupRole(ADMIN_ROLE, msg.sender);
          _setupRole(EXCHANGE_ROLE, msg.sender);

          volatilityChain = IVolatilityChain(_volChainAddress);
      }

    function descriptionHash() external view returns (bytes32)
    {
      return keccak256(abi.encodePacked(volatilityChain.getDecription()));
    }

    function queryOptionCost(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType, uint256 _amount,
      uint256 _utilPrior, uint256 _utilAfter)
      external view returns(uint256)
    {
        require((_poType==OptionLibrary.PayoffType.Call) || (_poType==OptionLibrary.PayoffType.Put));

        (uint256 _price,) = volatilityChain.queryPrice();
        (uint256 _histoVol, uint256 _accentus) = volatilityChain.getVol(_tenor);

        uint256 _volatility = Math.average(calcVolCurve(_utilPrior, _histoVol, _accentus), calcVolCurve(_utilAfter, _histoVol, _accentus));

        return  OptionLibrary.calcPremium(_price, _volatility, _strike, _poType, _amount, volatilityChain.getPriceMultiplier());
    }

    function calcVolCurve(uint256 _util, uint256 _histoVol, uint256 _accentus) internal view returns (uint256)
    {
      if(_accentus < _histoVol)
      {
        return _histoVol;
      }
      return (_util <= ethMultiplier)? (_histoVol + MulDiv(_accentus - _histoVol, _util, ethMultiplier))
        : (_accentus + MulDiv(_accentus - _histoVol, 2 * (_util - ethMultiplier), ethMultiplier));
    }

    function checkVolSkew(uint256 _tenor, uint256 _strike) external view returns (uint256, uint256, uint256)
    {
        (uint256 _price,) = volatilityChain.queryPrice();
        (uint256 _volatility, ) = volatilityChain.getVol(_tenor);
        return (_price, _volatility, OptionLibrary.calcVolSkew(_strike, _price, _volatility, volatilityChain.getPriceMultiplier()));
    }

    function addOption(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side,
      uint256 _amount, uint256 _premium, uint256 _fee)
    external onlyRole(EXCHANGE_ROLE) returns(uint256)
    {
        require((_poType==OptionLibrary.PayoffType.Call) || (_poType==OptionLibrary.PayoffType.Put), "Use call or put option.");

        (uint256 _price,) = volatilityChain.queryPrice();
        (uint256 _volatility, ) = volatilityChain.getVol(_tenor);

        optionCounter++;
        uint256 _id = optionCounter;
        optionsList[_id] = OptionLibrary.Option(
            _poType,
            _side,
            OptionLibrary.OptionStatus.Draft,
            msg.sender,
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
        (uint256 _price,) = volatilityChain.queryPrice();
        return optionsList[_id].calcPayoffValue(_price);
    }

    function getOptionHolder(uint256 _id) external view returns (address payable){
      return payable(optionsList[_id].holder);
    }

    function calculateContractDelta(uint256 _id) external view returns(int256){
      int256 _delta = 0;
      if(optionsList[_id].status== OptionLibrary.OptionStatus.Active)
      {
       (uint256 _price, ) = volatilityChain.queryPrice();
       (uint256 _vol, ) = volatilityChain.getVol(optionsList[_id].tenor);

        uint256 _vol1DAdjusted = MulDiv(MulDiv(_vol, Sqrt(86400), Sqrt(optionsList[_id].tenor)), deltaRange.numerator, deltaRange.denominator);
        uint256 _lowerRange = _price - (_price* _vol1DAdjusted/ volatilityChain.getPriceMultiplier());
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

    function stampActiveOption(uint256 _id) external onlyRole(EXCHANGE_ROLE) {
        optionsList[_id].effectiveTime = block.timestamp;
        optionsList[_id].status = OptionLibrary.OptionStatus.Active;
    }

    function stampExercisedOption(uint256 _id) external onlyRole(EXCHANGE_ROLE){
        optionsList[_id].exerciseTime = block.timestamp;
        optionsList[_id].status = OptionLibrary.OptionStatus.Exercised;
    }

    function stampExpiredOption(uint256 _id)  external onlyRole(EXCHANGE_ROLE){
        optionsList[_id].status = OptionLibrary.OptionStatus.Expired;
    }

    function getOption(uint256 _id) external view returns(OptionLibrary.Option memory) {
        return optionsList[_id];
    }

    function queryVol(uint256 _tenor) external view returns(uint256, uint256){return volatilityChain.getVol(_tenor);}
    function queryPrice() external view returns(uint256, uint256){return volatilityChain.queryPrice();}
    function priceMultiplier() external view returns (uint256){return volatilityChain.getPriceMultiplier();}
    function priceDecimals() external view returns(uint256) {return volatilityChain.getPriceDecimals();}
}
