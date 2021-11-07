/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity 0.8.9;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./FullMath.sol";

contract OptionVault is AccessControl{
  using OptionLibrary for OptionLibrary.Option;
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  mapping(uint256=> OptionLibrary.Option) internal optionsList;
  uint256 public optionCounter = 0;
  IVolatilityChain internal volatilityChain;

  constructor( address _volChainAddress ){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(EXCHANGE_ROLE, msg.sender);
    volatilityChain = IVolatilityChain(_volChainAddress); }
  
  function descriptionHash() external view returns (bytes32)  { return keccak256(abi.encodePacked(volatilityChain.getDecription()));}

  function queryOptionCost(uint256 _strike, uint256 _amount, uint256 _vol, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) external view returns(uint256 _premium, uint256 _cost, uint256 _price) {
    (_price,) = volatilityChain.queryPrice();
    _premium = OptionLibrary.calcPremium(_price, _vol, _strike, _poType, _amount);
    _cost = _premium;
    if(_side == OptionLibrary.OptionSide.Sell){
      uint256 _notional = MulDiv(_amount, _price, OptionLibrary.Multiplier());
      require(_notional>= _premium);
      _cost = _notional - _premium;}}

  function addOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _premium, uint256 _cost, uint256 _price, uint256 _volatility) external onlyRole(EXCHANGE_ROLE) returns(uint256 _id) {
    optionCounter++;
    _id = optionCounter;
    optionsList[_id] = OptionLibrary.Option(_poType, _side, OptionLibrary.OptionStatus.Draft, msg.sender, _id, block.timestamp,  0, _tenor, 0,  0, _amount, _price, _strike, _volatility, _premium, _cost);}

  function getOptionHolder(uint256 _id) external view returns(address) { return optionsList[_id].holder;}
  function queryOptionPremium(uint256 _id) external view returns(uint256) {return optionsList[_id].premium;}

  function queryOptionNotional(uint256 _id, bool _ignoreSells) external view returns(uint256 _notional){
    _notional=optionsList[_id].amount;
    if(optionsList[_id].side==OptionLibrary.OptionSide.Sell && _ignoreSells){_notional=0;}}

  function getContractPayoff(uint256 _id) external view returns(uint256 _payoff, uint256 _payback){
    (uint256 _price,) = volatilityChain.queryPrice();
    _payoff = optionsList[_id].calcPayoff(_price);
    _payback = _payoff;
    if(optionsList[_id].side == OptionLibrary.OptionSide.Sell){ 
      uint256 _notional = optionsList[_id].calcNotionalExposure(_price);
      require(_notional >= _payoff, "Payoff incorrect.");
      _payback = _notional - _payoff;}}

  function calculateContractDelta(uint256 _id, uint256 _price, bool _ignoreSells) external view returns(int256 _delta){
    _delta = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active && !(_ignoreSells && optionsList[_id].side==OptionLibrary.OptionSide.Sell)){
      uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - Math.min(optionsList[_id].maturity, block.timestamp));
      _delta = int256(MulDiv(OptionLibrary.calcDelta(_price, optionsList[_id].strike, _vol), optionsList[_id].amount, OptionLibrary.Multiplier() ));
      if(optionsList[_id].poType==OptionLibrary.PayoffType.Put) {_delta = -int256(optionsList[_id].amount) + _delta; }
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell){ _delta = -_delta;}}}
    
  function calculateContractGamma(uint256 _id, uint256 _price, bool _ignoreSells) external view returns(int256 _gamma){
    _gamma = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active && !(_ignoreSells && optionsList[_id].side==OptionLibrary.OptionSide.Sell)){
      uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - Math.min(optionsList[_id].maturity, block.timestamp));
      _gamma = int256(MulDiv(OptionLibrary.calcGamma(_price, optionsList[_id].strike, _vol), optionsList[_id].amount, OptionLibrary.Multiplier() ));
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell){ _gamma = -_gamma;}}}
      
  function calculateSpotGamma() external view returns(int256 _gamma){
    uint256 _vol = volatilityChain.getVol(86400);
    _gamma = int256(OptionLibrary.calcGamma(OptionLibrary.Multiplier(), OptionLibrary.Multiplier(), _vol));}
    
  // function validateOption(uint256 _id, address _holder) external view {
  //   require(optionsList[_id].holder== _holder, "Not the owner.");
  //   require(optionsList[_id].maturity >= block.timestamp, "Option has expired.");
  //   require(optionsList[_id].status==OptionLibrary.OptionStatus.Active, "Not active option.");}

  function isOptionExpiring(uint256 _id) external view returns (bool){ return (optionsList[_id].status== OptionLibrary.OptionStatus.Active) && (optionsList[_id].maturity <= block.timestamp);}

  function stampActiveOption(uint256 _id) external onlyRole(EXCHANGE_ROLE) {
    optionsList[_id].effectiveTime = block.timestamp;
    optionsList[_id].maturity = optionsList[_id].effectiveTime + optionsList[_id].tenor;
    optionsList[_id].status = OptionLibrary.OptionStatus.Active;}

  // function stampExercisedOption(uint256 _id) external onlyRole(EXCHANGE_ROLE){
  //     optionsList[_id].exerciseTime = block.timestamp;
  //     optionsList[_id].status = OptionLibrary.OptionStatus.Exercised;}

  function stampExpiredOption(uint256 _id)  external onlyRole(EXCHANGE_ROLE){
    optionsList[_id].exerciseTime = block.timestamp;
    optionsList[_id].status = OptionLibrary.OptionStatus.Expired;}

  function getOption(uint256 _id) external view returns(OptionLibrary.Option memory) {return optionsList[_id];}
  function queryVol(uint256 _tenor) external view returns(uint256){return volatilityChain.getVol(_tenor);}
  function queryPrice() external view returns(uint256, uint256){return volatilityChain.queryPrice();}
  // function priceDecimals() external view returns(uint256) {return volatilityChain.getPriceDecimals();}
}
