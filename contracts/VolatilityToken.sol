// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/MathLib.sol";

contract VolatilityToken is ERC20, AccessControl{
    using MathLib for uint256;
    using Math for uint256;

    bytes32 public constant EXCHANGE = keccak256("EXCHANGE");

    uint256 public tenor;
    address public underlying;
    ERC20 public funding;

    // constructor, ownership is transferred to Moret gov token which can mint and burn the tokens.
    constructor(ERC20 _funding, address _underlying, uint256 _tenor, string memory _name, string memory _symbol, address _exchange ) ERC20(_name, _symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        funding = _funding;
        tenor = _tenor;
        underlying = _underlying;
        grantRole(EXCHANGE, _exchange);}

    function getMintAmount(uint256 _premium, uint256 _vol) public view returns(uint256 _mintAmount, uint256 _volPrice){
        uint256 _supply = totalSupply();
        _volPrice = _supply > 0? _vol.max(funding.balanceOf(address(this)).ethdiv(_supply)): _vol;
        _mintAmount = _premium.ethdiv(_volPrice);}

    function getBurnAmount(uint256 _premium, uint256 _vol) public view returns(uint256 _burnAmount, uint256 _volPrice){
        uint256 _supply = totalSupply();
        _volPrice = _supply > 0? _vol.min(funding.balanceOf(address(this)).ethdiv(_supply)): _vol;
        _burnAmount = _premium.ethdiv(_volPrice);}

    function mint(address _account, uint256 _amount) public onlyRole(EXCHANGE) {_mint(_account, _amount);}
    function burn(address _account, uint256 _amount) public onlyRole(EXCHANGE) {_burn(_account, _amount);}
    function pay(address _account, uint256 _amount) public onlyRole(EXCHANGE){require(funding.transfer(_account, _amount), '-VS');}
}
