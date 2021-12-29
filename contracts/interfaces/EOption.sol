// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface EOption{
    event NewOption(address indexed _purchaser, OptionLibrary.Option _option, uint256 _cost, bool _inVol);
    event Exercise(address indexed _purchaser, OptionLibrary.Option _option, uint256 _payoff);
    event VolTokenAddition(uint256 indexed _tenor, address _tokenAddress);
    event VolTokenRemoved(uint256 indexed _tenor);
    event ResetParameter(uint256 indexed _parameterId, uint256 _parameter);
    event ResetAddress(uint256 indexed _addressId, address _address);
    event Response(bool success, bytes data);}