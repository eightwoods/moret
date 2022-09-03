// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Create2.sol";
import "../governance/Govern.sol";
// import "../interfaces/EMoret.sol";

contract PoolGovernorFactory {
    event ProxyCreated(address poolGov, address pool);

    function deploy(bytes32 salt, address _pool) external{
        address _a = Create2.deploy( 0, salt, abi.encodePacked(type(Govern).creationCode, abi.encode(_pool)));
        emit ProxyCreated(_a, _pool);
        }
}