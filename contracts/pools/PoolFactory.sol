// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../governance/MoretBroker.sol";
import "../Exchange.sol";
import "./MarketMaker.sol";
import "./Pool.sol";

contract PoolFactory {
    // events
    event PoolCreated(address pool);

    function computeAddress(bytes32 salt, string memory _name, string memory _symbol, address _marketMaker) public view returns (address) {
        bytes32 _bytecodeHash = keccak256(getCreationCode(_name, _symbol, _marketMaker));
        return Create2.computeAddress(
                salt, //keccak256(abi.encodePacked(salt)),
                _bytecodeHash,
                address(this)
            );}

    function deploy(bytes32 salt, string memory _name, string memory _symbol, address _marketMaker, address _broker) public {
        bytes memory _bytecode = getCreationCode(_name, _symbol, _marketMaker);
        address proxy = Create2.deploy(
            0,
            salt,//keccak256(abi.encodePacked(salt)),
            _bytecode
        );

        Pool _pool = Pool(proxy);
        // _pool.transferOwnership(_timelock);
        MoretBroker(_broker).addPool(_pool, false);

        emit PoolCreated(proxy);}

    function getCreationCode(string memory _name, string memory _symbol, address _marketMaker) public pure returns(bytes memory){
        require(address(_marketMaker) != address(0), 'PF0A');
        bytes memory _poolBytecode = type(Pool).creationCode;
        _poolBytecode = abi.encodePacked(_poolBytecode, abi.encode(_name, _symbol, _marketMaker));
        return _poolBytecode;}
}