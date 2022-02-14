// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract VolatilityToken is ERC20, AccessControl
{
    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
    uint256 public tenor;
    bytes32 public tokenHash;

    constructor(string memory _tokenName, uint256 _tenor, string memory _name, string memory _symbol, address _exchangeAddress ) ERC20(_name, _symbol) {
        _setupRole(EXCHANGE_ROLE, _exchangeAddress);
        tenor = _tenor;
        tokenHash = keccak256(bytes(_tokenName));}

    function mint(address _account, uint256 _amount) public payable onlyRole(EXCHANGE_ROLE) {_mint(_account, _amount);}
    function burn(address _account, uint256 _amount) public onlyRole(EXCHANGE_ROLE){ 
        require(allowance(_account, msg.sender)>=_amount, "Allowance error");
        _burn(_account, _amount);}
}
