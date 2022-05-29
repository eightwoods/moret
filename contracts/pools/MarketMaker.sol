// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/EOption.sol";
import "../governance/Moret.sol";
import "../VolatilityChain.sol";

contract MarketMaker is  EOption{
  address public  hedgingBot; // hedge bot addresses
  bytes32 public  description; // description of pool and its hedging strategies
  Moret public  govToken; // Records of which routes are available for hedging strategies
  address public exchange; // EXCHANGE could be able to extract payments from MarketMaker
  ERC20 public funding;
  address public underlying;

  // hedging parameters
  uint256 public loanInterest = 0; // Annualised interest rate for option pricing; default: 0%
  uint256 public hedgingCost = 0.003e18; // Trading cost for hedging; default: 0.3%

  // contructor. Arguments: pool tokens, volatility oracle, option vault and bot address
  constructor(address _bot, bytes32 _description, address _underlying, address _exchange, address _govToken) {
    hedgingBot = _bot;
    description = _description;
    govToken = Moret(_govToken);
    funding = govToken.funding();
    exchange = _exchange;
    underlying = _underlying;
    }  

  // function for sending option payout, only callable by the unique Exchange contract
  function settlePayment(address _to, uint256 _amount) external {
    require(msg.sender == exchange,'-X');
    if(_amount > 0){
      require(funding.transfer(_to, _amount));}}

  // functions to make market by hedging underlyings
  // trade swaps/loans via allowed routes (in MoretBook) such as 1Inch. Arguments: amount to be paid, paid token, route via which the transaction happens, calldata for the transaction bytes data pre-compiled externally, gas allowed for the transaction
  function trade(address _fromAddress, uint256 _fromAmt, address payable _spender, bytes calldata _calldata, uint256 _gas) external {
    require(msg.sender == hedgingBot, '-H');
    require(govToken.existEligibleRoute(address(_spender)), '-R');
    require(ERC20(_fromAddress).approve(_spender, _fromAmt));
    (bool success, bytes memory data) = _spender.call{gas: _gas}(_calldata);
    emit HedgeResponse(msg.sender, address(this), success, data);}

  // Reset functions for parameters
  function setLoanInterest(uint256 _newParameter) external{
    require(msg.sender == hedgingBot, '-H');
    loanInterest = _newParameter;
    emit ResetParameter(101, _newParameter);}

  function getVolatilityChain() external view returns(VolatilityChain){
    return govToken.getVolatilityChain(underlying);}
}
