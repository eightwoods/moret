/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./MoretInterfaces.sol";
import "./OptionVault.sol";
import "./VolatilityToken.sol";
import "./MarketMakerNative.sol";

contract ExchangeNative is AccessControl, IOption
{
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    OptionLibrary.Percent public settlementFee = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6);
    OptionLibrary.Percent public volTransactionFees = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6);
      address payable public contractAddress;

    MarketMakerNative internal marketMaker;
    OptionVault internal optionVault;

    mapping(uint256=>VolatilityToken) public volTokensList;

    constructor(
      address payable _marketMakerAddress,
      address _optionAddress,
      address payable _volTokenAddress
      )
    {
      _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);

      optionVault = OptionVault(_optionAddress);
      marketMaker = MarketMakerNative(_marketMakerAddress);
      VolatilityToken _volToken = VolatilityToken(_volTokenAddress);
      volTokensList[_volToken.tenor()] = _volToken;
      contractAddress = payable(address(this));
    }

    function queryOptionCost(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType, uint256 _amount)
    external view returns(uint256)
    {
        (uint256 _premium, uint256 _fee) = optionVault.queryOptionCost(_tenor, _strike, _poType, _amount,
          settlementFee, marketMaker.calcUtilityAddon(_amount, _poType) );
        return _premium + _fee;
    }

    function purchaseOption(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType, uint256 _amount)
    external payable{
      require(optionVault.containsTenor(_tenor), "Unsupported option tenor.");
      require((_poType == OptionLibrary.PayoffType.Call) || (_poType==OptionLibrary.PayoffType.Put), "Unsupported option type.");

      (uint256 _premium, uint256 _fee) = optionVault.queryOptionCost(_tenor, _strike, _poType, _amount, settlementFee, marketMaker.calcUtilityAddon(_amount, _poType) );

      uint256 _id = optionVault.addOption(_tenor, _strike, _poType, _amount, _premium, _fee );
      require(msg.value >= optionVault.queryDraftOptionCost(_id, false), "Entered premium incorrect.");
      payable(address(marketMaker)).transfer(optionVault.queryOptionPremium(_id));

      optionVault.stampActiveOption(_id);

      marketMaker.recordOptionPurhcase(msg.sender, _id, optionVault.queryOptionPremium(_id),
        optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Call),
        optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Put));

      emit newOptionBought(msg.sender, block.timestamp, _id, msg.value, false);
    }

    function purchaseOptionInVol(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType, uint256 _amount,
      uint256 _payInCost)
      external{
      require(optionVault.containsTenor(_tenor), "Unsupported option tenor.");
      require((_poType == OptionLibrary.PayoffType.Call) || (_poType==OptionLibrary.PayoffType.Put), "Unsupported option type.");

      (uint256 _premium, uint256 _fee) = optionVault.queryOptionCost(_tenor, _strike, _poType, _amount, settlementFee, marketMaker.calcUtilityAddon(_amount, _poType) );

      uint256 _id = optionVault.addOption(_tenor, _strike, _poType, _amount, _premium, _fee );
      require(_payInCost >= optionVault.queryDraftOptionCost(_id, true), "Entered premium incorrect.");

      require(volTokensList[_tenor].transferFrom(msg.sender, contractAddress, _payInCost), 'Failed payment.');

      volTokensList[_tenor].approve(address(volTokensList[_tenor]), _payInCost);
      volTokensList[_tenor].recycle(contractAddress, _payInCost);
      payable(address(marketMaker)).transfer(optionVault.queryOptionPremium(_id));

      optionVault.stampActiveOption(_id);

      marketMaker.recordOptionPurhcase(msg.sender, _id, optionVault.queryOptionPremium(_id),
        optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Call),
        optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Put));

      emit newOptionBought(msg.sender, block.timestamp, _id, _payInCost, true);
    }

    function exerciseOption(uint256 _id) external  {
        optionVault.validateOption(_id, msg.sender);

        uint256 _payoffValue = optionVault.getOptionPayoffValue(_id);
        require(_payoffValue < contractAddress.balance, "Balance insufficient.");

        optionVault.stampExercisedOption(_id);
        payable(msg.sender).transfer(_payoffValue);

        marketMaker.recordOptionRemoval(msg.sender, _id, optionVault.queryOptionPremium(_id),
          optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Call),
          optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Put));

        emit optionExercised(_id, block.timestamp);
    }

    function expireOption(uint256 _id) internal {
        if(optionVault.isOptionExpiring(_id))
        {
            uint256 _payoffValue = optionVault.getOptionPayoffValue(_id);
            require(_payoffValue < contractAddress.balance, "Balance insufficient.");

            optionVault.stampExpiredOption(_id);

            address payable _optionHolder = optionVault.getOptionHolder(_id);
            payable(_optionHolder).transfer(_payoffValue);

            marketMaker.recordOptionRemoval(msg.sender, _id, optionVault.queryOptionPremium(_id),
              optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Call),
              optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Put));
        }
    }


      function addVolToken(address payable _tokenAddress) external onlyRole(ADMIN_ROLE)
      {
          VolatilityToken _volToken = VolatilityToken(_tokenAddress);
          require(_volToken.descriptionHash() == optionVault.descriptionHash());
          require(optionVault.containsTenor(_volToken.tenor()));

          volTokensList[_volToken.tenor()] = _volToken;

      }

      function quoteVolatilityCost(uint256 _tenor, uint256 _volAmount) public view returns(uint256, uint256)
      {
          require(optionVault.containsTenor(_tenor));

          (uint256 _price,) = optionVault.queryPrice();

          uint256 _value = volTokensList[_tenor].calculateMintValue(_volAmount, _price, optionVault.queryVol(_tenor));
          uint256 _fee = _value * volTransactionFees.numerator/ volTransactionFees.denominator;

          return (_value, _fee);
      }

      function purchaseVolatilityToken(uint256 _tenor, uint256 _volAmount)
      external payable {
          (uint256 _value, uint256 _fee) = quoteVolatilityCost(_tenor, _volAmount);
          require(msg.value >= (_value + _fee));

          volTokensList[_tenor].mint{value: _value}(msg.sender, _volAmount);

          emit newVolatilityTokenBought(msg.sender, block.timestamp, _tenor, _volAmount);
      }

      function sweepBalance() external onlyRole(ADMIN_ROLE){
            payable(msg.sender).transfer(contractAddress.balance);
      }

      function resetSettlementFees(uint256 _fee, uint256 _denominator) external onlyRole(ADMIN_ROLE){
          settlementFee = OptionLibrary.Percent(_fee, _denominator);
      }

      function resetVolTransactionFees(uint256 _fee, uint256 _denominator) external onlyRole(ADMIN_ROLE){
          volTransactionFees = OptionLibrary.Percent(_fee, _denominator);
      }

      function priceDecimals() external view returns(uint256){ return optionVault.priceDecimals();}
      function queryVol(uint256 _tenor) external view returns(uint256){return optionVault.queryVol(_tenor);}

          receive() external payable{}

}
