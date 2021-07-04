/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "./OptionLibrary.sol";

interface EOption{
    event newOptionBought(address indexed _purchaser, OptionLibrary.Option _option, uint256 _cost, bool _inVol);
    event optionExercised(address indexed _purchaser, OptionLibrary.Option _option, uint256 _payoff);
    event capitalAdded(address _recipient, uint256 _mintMPTokenAmount, uint256 _addedValue);
    event capitalWithdrawn(address _recipient, uint256 _burnMPTokenAmount, uint256 _withdrawValue);
    event newVolatilityTokenBought(address _purchaser, uint256 _time, uint256 _tenor, uint256 _amount);
/*
      event newTenor(uint256 _tenor);
      event newVolatilityToken(address _tokenAddress);

      event newOptionCreated(OptionLibrary.Option _newOption);

      event optionExercised(OptionLibrary.Option _option);
      event volTokenRecycled(uint256 _tokenAmount);
      event cashSweep();

      event newGovernanceFees(uint256 _fee);
      event newUniswapFees(uint24 _fee);
      event newDeltaRange(uint256 _range);

      event hedgePositionUpdated(int256 _underlyingAmount, int256 _stableAmount, uint256 _transactedPrice);
       */
}

interface IVolatilityChain{
  event volatilityChainBlockAdded(uint256 indexed _tenor, uint256 _timeStamp, PriceStamp _book);

  struct PriceStamp{
    uint256 startTime;
    uint256 endTime;
    uint256 open;
    uint256 highest;
    uint256 lowest;
    uint256 close;
    uint256 volatility;
    uint256 accentus;
  }

  struct VolParam{
      uint256 initialVol;
      uint256 ltVol;
      uint256 ltVolWeighted;
      uint256 w; // parameter for long-term average
      uint256 p; // parameter for moving average
      uint256 q; // paramter for auto regression
  }

  function getVol(uint256 _tenor) external view returns(uint256, uint256);
  function queryPrice() external view returns(uint256, uint256);
  function getPriceDecimals() external view returns (uint256);
  function getPriceMultiplier() external view returns (uint256);
  function getDecription() external view returns (string memory);
}


interface IOptionVault{
  function calculateContractDelta(uint256 _id) external view returns(int256);
  function getOption(uint256 _id) external view returns(OptionLibrary.Option memory);
  function getOptionPayoffValue(uint256 _id) external view returns(uint256);

  function queryVol(uint256 _tenor) external view returns(uint256, uint256);
  function queryPrice() external view returns(uint256, uint256);
  function priceMultiplier() external view returns (uint256);
  function priceDecimals() external view returns(uint256);
}

/* interface IOptionContract{
  function descriptionHash() external view returns (bytes32);
  function containsTenor(uint256 _tenor) external returns (bool);
  function queryOptionCost(uint256 _tenor, uint256 _strike, PayoffType _poType, uint256 _amount, Percent _fee) external view returns(uint256);
  function addOption(uint256 _tenor, uint256 _strike, PayoffType _poType, uint256 _amount, Percent _fee) external view returns(uint256);
  function queryDraftOptionCost(uint256 _id) external view returns(uint256);
  function queryDraftOptionFee(uint256 _id) external view returns(uint256);
  function queryDraftOptionCostInVolToken(uint256 _id) external view returns(uint256);
  function stampActiveOption(uint256 _id) external;
  function stampExercisedOption(uint256 _id) external ;
  function stampExpiredOption(uint256 _id)  external;
}

interface IGovernanceToken{

}

interface IVolatilityToken{
  function descriptionHash() external view returns (bytes32);
  function tenor() external view returns (uint256);
  function recycle(address payable _recipient, uint256 _tokenAmount) external;
}

interface IMoretMarketMaker{

} */
