/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BondingCurve{

  ERC20 internal token;

  construct
    (address tokenAddress,
      uint256 ){
      token = ERC20(tokenAddress);
  }




}
