// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/EOption.sol";
import "../governance/Moret.sol";
import "../governance/MoretBroker.sol";
import "../VolatilityChain.sol";

contract MarketMaker is  EOption{
  address public immutable hedgingBot; // hedge bot addresses
  bytes32 public immutable description; // description of pool and its hedging strategies
  Moret public immutable govToken; // Records of which routes are available for hedging strategies
  address public immutable exchange; // EXCHANGE could be able to extract payments from MarketMaker
  address public immutable funding;
  address public immutable underlying;

  // hedging parameters
  uint256 public loanInterest = 0; // Annualised interest rate for option pricing; default: 0%
  uint256 public hedgingCost = 0.003e18; // Trading cost for hedging; default: 0.3%

  // contructor. Arguments: pool tokens, volatility oracle, option vault and bot address
  constructor(address _bot, bytes32 _description, address _underlying, address _exchange, address _govToken) {
    hedgingBot = _bot;
    description = _description;
    govToken = Moret(_govToken);
    funding = address(govToken.broker().funding());
    exchange = _exchange;
    underlying = _underlying;
    }  

  // function for sending option payout, 
  // !!! only callable by the unique Exchange contract address !!!
  function settlePayment(address _to, uint256 _amount) external {
    require(msg.sender == exchange, '-mmpX');
    require(_to != address(0), "0addr");
    if(_amount > 0){
      require(ERC20(funding).transfer(_to, _amount), '-transfer');}}

  // functions to make market by hedging underlyings, trade swaps/loans via allowed routes (e.g. 1Inch). 
  // Arguments: from address, amount to be paid, route via which the transaction happens, calldata for the transaction bytes data pre-compiled externally, gas allowed for the transaction
  function trade(address _fromAddress, uint256 _fromAmt, address payable _spender, bytes calldata _calldata, uint256 _gas) external {
    require(msg.sender == hedgingBot, '-tH');
    require(govToken.existEligibleRoute(address(_spender)), '-R'); // only routes in the eligible route list are allowed
    require(ERC20(_fromAddress).approve(_spender, _fromAmt), '-approve');
    (bool success, bytes memory data) = _spender.call{gas: _gas}(_calldata);
    emit HedgeResponse(msg.sender, address(this), success, data);}

  // Reset functions for parameters
  function setParameter(uint256 _paramId, uint256 _newParameter) external{
    require(msg.sender == hedgingBot, '-spH');
    if(_paramId == 101){loanInterest = _newParameter;}
    else{hedgingCost=_newParameter;}
    emit ResetParameter(_paramId, _newParameter);}

  function getVolatilityChain() external view returns(VolatilityChain){
    return govToken.getVolatilityChain(underlying);}
}
