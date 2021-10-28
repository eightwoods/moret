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

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
  mapping(uint256=> OptionLibrary.Option) internal optionsList;
  uint256 public optionCounter = 0;

  IVolatilityChain internal volatilityChain;
  uint256 internal ethMultiplier = 10 ** 18;

  OptionLibrary.Percent public volPremiumFixedAddon = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6) ;
  OptionLibrary.Percent public deltaRange = OptionLibrary.Percent(8 * 10 ** 5, 10 ** 6) ;

  constructor( address _volChainAddress ){
          _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
          _setupRole(ADMIN_ROLE, msg.sender);
          _setupRole(EXCHANGE_ROLE, msg.sender);
          volatilityChain = IVolatilityChain(_volChainAddress); }
  
  function descriptionHash() external view returns (bytes32)  { return keccak256(abi.encodePacked(volatilityChain.getDecription()));}

  function queryOptionCost(uint256 _tenor, uint256 _strike,uint256 _amount, uint256 _vol, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) external view returns(uint256 _premium, uint256 _cost) {
      (uint256 _price,, uint256 _priceMultiplier) = volatilityChain.queryPrice();
      _premium = OptionLibrary.calcPremium(_price, _vol, _strike, _poType, _amount, _priceMultiplier);
      _cost = _premium;
      if(_side == OptionLibrary.OptionSide.Sell){
        uint256 _notional = MulDiv(_amount, _price,_priceMultiplier);
        require(_notional>= _premium);
        _cost = _notional - _premium;}}

    // function calcVolCurve(uint256 _util, uint256 _histoVol, uint256 _accentus) internal view returns (uint256)
    // {
    //   if(_accentus < _histoVol)
    //   {
    //     return _histoVol;
    //   }
    //   return (_util <= ethMultiplier)? (_histoVol + MulDiv(_accentus - _histoVol, _util, ethMultiplier))
    //     : (_accentus + MulDiv(_accentus - _histoVol, 2 * (_util - ethMultiplier), ethMultiplier));
    // }

    // function checkVolSkew(uint256 _tenor, uint256 _strike) external view returns (uint256, uint256, uint256)
    // {
    //     (uint256 _price,) = volatilityChain.queryPrice();
    //     (uint256 _volatility, ) = volatilityChain.getVol(_tenor);
    //     return (_price, _volatility, OptionLibrary.calcVolSkew(_strike, _price, _volatility, volatilityChain.getPriceMultiplier()));
    // }

  function addOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _premium, uint256 _cost, uint256 _price, uint256 _volatility) external onlyRole(EXCHANGE_ROLE) returns(uint256 _id) {
    // (uint256 _price,, uint256 _priceMultiplier) = volatilityChain.queryPrice();
    // (uint256 _volatility, ) = volatilityChain.getVol(_tenor);
    optionCounter++;
    _id = optionCounter;
    optionsList[_id] = OptionLibrary.Option(_poType, _side, OptionLibrary.OptionStatus.Draft, msg.sender, _id, block.timestamp,  0, _tenor, 0,  0, _amount, _price, _strike, _volatility, _premium, _cost);}

    // function queryDraftOptionCost(uint256 _id, bool _inVol) external view returns(uint256)
    // {
    //     require(optionsList[_id].status== OptionLibrary.OptionStatus.Draft);
    //     uint256 _cost = optionsList[_id].getCost(_inVol);
    //     if(optionsList[_id].side == OptionLibrary.OptionSide.Sell){
    //       require(_cost<optionsList[_id].amount, "Sell option premium incorrect.");
    //       _cost = optionsList[_id].amount - _cost;
    //     }
    //     return _cost;
    // }

    // function queryDraftOptionFee(uint256 _id) external view returns(uint256)
    // {
    //     require(optionsList[_id].status== OptionLibrary.OptionStatus.Draft);
    //     return optionsList[_id].fee;
    // }

  function getOptionHolder(uint256 _id) external view returns(address) { return optionsList[_id].holder;}
  function queryOptionPremium(uint256 _id) external view returns(uint256) {return optionsList[_id].premium;}
    
    // function queryOptionCapital(uint256 _id, uint256 _capitalRatio) external view returns(uint256)
    // {
    //   require(_capitalRatio<=ethMultiplier, "CapitalRatio is too big.");
    //   uint256 _capital = 0;
    //   if(optionsList[_id].side==OptionLibrary.OptionSide.Buy)
    //   {
    //     _capital=MulDiv(optionsList[_id].amount, _capitalRatio, ethMultiplier) + MulDiv(optionsList[_id].premium, ethMultiplier-_capitalRatio, ethMultiplier);
    //   }
    //   return _capital;
    // }

  function queryOptionNotional(uint256 _id, bool _ignoreSells) external view returns(uint256 _notional){
    _notional=optionsList[_id].amount;
    if(optionsList[_id].side==OptionLibrary.OptionSide.Sell || !_ignoreSells){_notional=0;}}

    // function queryOptionCapitalV2(uint256 _amount, uint256 _strike, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _capitalRatio) external view returns(uint256)
    // {
    //   require(_capitalRatio<=ethMultiplier, "CapitalRatio is too big.");
    //   uint256 _capital = 0;
    //   if(_side==OptionLibrary.OptionSide.Buy)
    //   {
        
    //     _capital=MulDiv(_amount, _capitalRatio, ethMultiplier) + MulDiv(calcPayoffValue(_amount, _strike, _poType), ethMultiplier-_capitalRatio, ethMultiplier);
    //   }
    //   return _capital;
    // }

  // function calcPayoffValue(uint256 _amount, uint256 _strike, OptionLibrary.PayoffType _poType) public view returns(uint256) {
  //   (uint256 _price,,) = volatilityChain.queryPrice();
  //   uint256 _intrinsicValue = 0;
  //   if((_poType == OptionLibrary.PayoffType.Call) && (_price > _strike)){ _intrinsicValue = _price - _strike; }
  //   if((_poType == OptionLibrary.PayoffType.Put) && (_price<_strike)){ _intrinsicValue = _strike - _price;}
  //   return MulDiv(_intrinsicValue ,  _amount , _price);}
    
  function queryOptionExposure(uint256 _id, OptionLibrary.PayoffType _poType) external view returns(uint256 _exposure){
    _exposure = 0;
    if(optionsList[_id].poType==_poType){return optionsList[_id].amount;}}

  function getContractPayoff(uint256 _id) external view returns(uint256 _payoff, uint256 _payback){
    (uint256 _price,, uint256 _priceMultiplier) = volatilityChain.queryPrice();
    _payoff = optionsList[_id].calcPayoff(_price, _priceMultiplier);
    _payback = _payoff;
    if(optionsList[_id].side == OptionLibrary.OptionSide.Sell){ 
      uint256 _notional = optionsList[_id].calcNotionalExposure(_price,_priceMultiplier);
      require(_notional >= _payoff, "Payoff incorrect.");
      _payback = _notional - _payoff;}}

  function calculateContractDelta(uint256 _id, uint256 _price, uint256 _priceMultiplier, bool _ignoreSells) external view returns(int256 _delta){
    _delta = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active && !(_ignoreSells && optionsList[_id].side==OptionLibrary.OptionSide.Sell)){
      uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - Math.min(optionsList[_id].maturity, block.timestamp));
      _delta = int256(MulDiv(OptionLibrary.calcDelta(_price, optionsList[_id].strike, _priceMultiplier, _vol), optionsList[_id].amount, ethMultiplier ));
      if(optionsList[_id].poType==OptionLibrary.PayoffType.Put) {_delta = -int256(optionsList[_id].amount) + _delta; }
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell){ _delta = -_delta;}}}
    
  function calculateContractGamma(uint256 _id, uint256 _price, uint256 _priceMultiplier, bool _ignoreSells) external view returns(int256 _gamma){
    _gamma = 0;
    if(optionsList[_id].status== OptionLibrary.OptionStatus.Active && !(_ignoreSells && optionsList[_id].side==OptionLibrary.OptionSide.Sell)){
      uint256 _vol = volatilityChain.getVol(optionsList[_id].maturity - Math.min(optionsList[_id].maturity, block.timestamp));
      _gamma = int256(MulDiv(OptionLibrary.calcGamma(_price, optionsList[_id].strike, _priceMultiplier, _vol), optionsList[_id].amount, ethMultiplier ));
      if(optionsList[_id].side==OptionLibrary.OptionSide.Sell){ _gamma = -_gamma;}}}
      
  function calculateSpotGamma() external view returns(int256 _gamma){
    uint256 _vol = volatilityChain.getVol(86400);
    _gamma = int256(OptionLibrary.calcGamma(1, 1, 1, _vol));}
    
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

    function getOption(uint256 _id) external view returns(OptionLibrary.Option memory) {
        return optionsList[_id];
    }

    function queryVol(uint256 _tenor) external view returns(uint256){return volatilityChain.getVol(_tenor);}
    function queryPrice() external view returns(uint256, uint256, uint256){return volatilityChain.queryPrice();}
    // function priceMultiplier() external view returns (uint256){return volatilityChain.getPriceMultiplier();}
    function priceDecimals() external view returns(uint256) {return volatilityChain.getPriceDecimals();}
}
