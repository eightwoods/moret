// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Create2.sol";
import "../governance/Moret.sol";
import "./MarketMaker.sol";
import "../Exchange.sol";

contract MarketMakerFactory {
    Moret public immutable govToken;
    Exchange public immutable exchange;
    uint256 public count = 0;

    // events
    event MarketMakerCreated(address indexed underlyingAddress, address marketMaker);

    constructor(Moret _govToken, Exchange _exchange) {
        require(_govToken.broker().exchange() == address(_exchange), 'xExchange'); // make sure exchange address is affliated/fixed with Moret
        govToken = _govToken;
        exchange = _exchange;
        }

    function computeAddress(bytes32 salt, address _hedgingBot, address _underlying, bytes32 _description) external view returns (address) {
        bytes32 _bytecodeHash = keccak256(getCreationCode(_hedgingBot, _underlying, _description));
        return Create2.computeAddress(
                salt, //keccak256(abi.encodePacked(salt)),
                _bytecodeHash,
                address(this)
            );}

    function deploy(bytes32 salt, address _hedgingBot, address _underlying, bytes32 _description) external {
        count += 1;
        bytes memory _bytecode = getCreationCode(_hedgingBot, _underlying, _description);
        address proxy = Create2.deploy(
            0,
            salt, //keccak256(abi.encodePacked(salt)),
            _bytecode
        );
        emit MarketMakerCreated(_underlying, proxy);}

    function getCreationCode(address _hedgingBot, address _underlying, bytes32 _description) public view returns(bytes memory){
        require(_hedgingBot != address(0), 'MF0A');
        bytes memory _marketMakerBytecode = type(MarketMaker).creationCode;
        _marketMakerBytecode = abi.encodePacked(_marketMakerBytecode, abi.encode(_hedgingBot, _description, _underlying, exchange, govToken));
        return _marketMakerBytecode;}
    

}