// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract VolatilityToken is ERC20, AccessControl
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
    uint256 private constant ethMultiplier = 10 ** 18;
    uint256 public tenor;
    bytes32 public tokenHash;

    constructor(string memory _tokenName, uint256 _tenor, string memory _name, string memory _symbol ) ERC20(_name, _symbol) {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    tenor = _tenor;
    tokenHash = keccak256(abi.encodePacked(_tokenName));}

    function mint(address _account, uint256 _amount) public payable onlyRole(EXCHANGE_ROLE) {_mint(_account, _amount);}
    function burn(address _account, uint256 _amount) public onlyRole(EXCHANGE_ROLE){ _burn(_account, _amount);}
}
