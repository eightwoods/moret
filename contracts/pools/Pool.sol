// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "../interfaces/EOption.sol";
import "../governance/Moret.sol";
import "./MarketMaker.sol";

contract Pool is ERC20, ERC20Permit, ERC20Votes, Ownable, EOption{
    address public immutable exchange;
    MarketMaker public immutable marketMaker; // the fixed market maker contract to make markets by providing capital and running hedging programs.
    
    // Governable parameters
    uint256 public exerciseFee= 0.005e18;  // Fees paid to exercise bots for exercising expiring option contracts; default: 0.5%
    uint256 public volCapacityFactor = 0.5e18; // volatility capacity factor which determines the curvature of AMM functions; default: 0.5
    uint256 public minVolPrice = 0.5e18; // min annualised vol for trading volatility tokens
    
    // constructor, used only in PoolFactor contract
    constructor(string memory _name, string memory _symbol, address _marketMaker) ERC20(_name, _symbol) ERC20Permit(_name){
        marketMaker = MarketMaker(_marketMaker);
        marketMaker.getVolatilityChain(); // use this function to check if underlying exists.
        exchange = marketMaker.exchange();}

    // Reset functions for parameters
    function setPoolParameters(uint256 _parameterId, uint256 _newParameter) public onlyOwner(){ 
        if(_parameterId == 1){
            exerciseFee = _newParameter;}
        else if(_parameterId == 2){
            volCapacityFactor = _newParameter;}
        else if (_parameterId == 3){
            minVolPrice = _newParameter;}
        emit ResetParameter(_parameterId, _newParameter);}

    // generic mintable functions
    function mint(address to, uint256 amount) public {
        require(msg.sender == exchange);
        _mint(to,amount);}

    function burn(address account, uint256 amount) public {
        require(msg.sender == exchange);
        _burn(account, amount);}

    // The functions below are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}
