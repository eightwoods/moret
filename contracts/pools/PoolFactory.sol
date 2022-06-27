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
        MoretBroker(_broker).addPool(_pool);

        emit PoolCreated(proxy);}

    function getCreationCode(string memory _name, string memory _symbol, address _marketMaker) public pure returns(bytes memory){
        require(address(_marketMaker) != address(0), 'PF0A');
        bytes memory _poolBytecode = type(Pool).creationCode;
        _poolBytecode = abi.encodePacked(_poolBytecode, abi.encode(_name, _symbol, _marketMaker));
        return _poolBytecode;}


    // function createPool(string memory _name, string memory _symbol, address _marketMaker, address _timelock, address _broker, bytes32 _salt) external{
    //     require(address(_marketMaker) != address(0), '0A');
    //     // ERC20 _underlying = _marketMaker.underlying();
    //     // uint256 _poolCount = _marketMaker.govToken().broker().getPoolsCount(address(_underlying));
    //     // string memory _name = string(abi.encodePacked(_underlying.name(), " Moret Pool #", Strings.toString(_poolCount)));
    //     // string memory _symbol = string(abi.encodePacked(_underlying.symbol(), "mp", Strings.toString(_poolCount)));

    //     // bytes32 _salt = keccak256(abi.encodePacked(_marketMaker));

    //     count += 1;
    //     address _poolAddress;
    //     bytes memory _poolBytecode = type(Pool).creationCode;
    //     _poolBytecode = abi.encodePacked(_poolBytecode, abi.encode(_name, _symbol, _marketMaker));
    //     assembly{
    //         _poolAddress := create2(0, add(_poolBytecode, 0x20), mload(_poolBytecode), _salt)
    //         if iszero(extcodesize(_poolAddress)) {revert(0,0)}
    //     }
    //     Pool _pool = Pool(_poolAddress);
    //     _pool.transferOwnership(_timelock);
    //     MoretBroker(_broker).addPool(_pool);

    //     emit PoolCreated(_poolAddress, _salt);}
}