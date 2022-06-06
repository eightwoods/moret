// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ILendingPoolAddressesProvider {
  function getPoolAdmin() external view returns (address);
  function getAddress(bytes32 id) external view returns (address);
  function getLendingPool() external view returns (address);}