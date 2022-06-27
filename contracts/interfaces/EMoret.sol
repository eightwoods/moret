// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface EMoret{
    // event UpdateToken(address _underlying, address _oracle);
    // event UpdateVolToken(address _underlying, uint256 _tenor, address _volToken);
    event UpdateRoute(address _route, bool _addition);
    event UpdateProtocolFees(uint256 _fee);
    // event UpdateProtocolRecipient(address _address);
    event WithdrawPoolTokens(address _pool, uint256 _amount);
    // event InvestPoolTokens(address _pool, uint256 _amount);
    // event DivestFromGov(address _receipient, uint256 _amount);
    event ExchangePoolTokens(address _pool, address _sender, uint256 _amount, uint256 _moretAmount);
    
    }