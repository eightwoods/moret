// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILendingPoolAddressesProvider {
  function getAddress(bytes32 id) external view returns (address);
  function getLendingPool() external view returns (address);}