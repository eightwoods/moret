/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./FullMath.sol";

contract MoretToken is ERC20Capped, AccessControl
{
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  address payable contractAddress;
  uint256 private constant ethMultiplier = 10 ** 18;

  constructor(
      string memory _name,
      string memory _symbol)
      ERC20(_name, _symbol)
  {
      contractAddress = payable(address(this));

      _mint(msg.sender, 10 **  ethMultiplier);
      _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
      _setupRole(ADMIN_ROLE, msg.sender);
  }





}
