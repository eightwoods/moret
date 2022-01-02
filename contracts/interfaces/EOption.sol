// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../OptionLibrary.sol";

interface EOption{
    event NewOption(address indexed _purchaser, OptionLibrary.Option _option, uint256 _cost, bool _inVol);
    event Expire(address indexed _purchaser, OptionLibrary.Option _option, uint256 _payoff);
    event StampNewOption(uint256 indexed _id, uint256 _timestamp);
    event StampExpire(uint256 indexed _id, uint256 _timestamp);
    event VolTokenAddition(uint256 indexed _tenor, address _tokenAddress);
    event VolTokenRemoved(uint256 indexed _tenor);
    event ResetParameter(uint256 indexed _parameterId, uint256 _parameter);
    event ResetAddress(uint256 indexed _addressId, address _address);
    event Response(bool success, bytes data);}