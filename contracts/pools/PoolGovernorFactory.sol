// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../governance/MoretGovernor.sol";
// import "./Pool.sol";

contract PoolGovernorFactory {
    // events
    event ProxyCreated(address poolGov, address pool);

    // function computeAddress(uint256 salt, address _pool) public view returns (address) {
    //     bytes memory _bytecode = type(MoretGovernor).creationCode;
    //     _bytecode = abi.encodePacked(_bytecode, abi.encode(_pool));
    //     bytes32 _bytecodeHash = keccak256(_bytecode);
    //     return Create2.computeAddress(
    //             keccak256(abi.encodePacked(salt)),
    //             _bytecodeHash,
    //             address(this)
    //         );}

    function deploy(bytes32 salt, address _pool) public{
        // bytes memory _bytecode = getCreationCode(_pool); //abi.encodePacked(_bytecodeHash);
        bytes memory _bytecode = type(MoretGovernor).creationCode;
        _bytecode = abi.encodePacked(_bytecode, abi.encode(_pool));
        
        address proxy = Create2.deploy(
            0,
            salt,
            _bytecode
        );
        emit ProxyCreated(proxy, _pool);}

    // function getCreationCode(address _pool) public pure returns(bytes memory){
        
    //     return _bytecode;}

    // function createPoolGovernor(Pool _pool, TimelockController _timelock, bytes32 _salt) external {
    //     // bytes32 _salt = keccak256(abi.encodePacked(address(_pool)));
    //     count += 1;
    //     address _poolGov;
    //     bytes memory _poolGovBytecode = type(MoretGovernor).creationCode;
    //     _poolGovBytecode = abi.encodePacked(_poolGovBytecode, abi.encode(_pool, _timelock));
    //     assembly{
    //         _poolGov := create2(0, add(_poolGovBytecode, 0x20), mload(_poolGovBytecode), _salt)
    //         if iszero(extcodesize(_poolGov)) {revert(0,0)}
    //     }
    //     // _timelock.grantRole(_timelock.PROPOSER_ROLE(), _poolGov);
    //     emit PoolGovernorCreated(_poolGov, _salt);}
}