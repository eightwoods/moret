// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./VolatilityToken.sol";
import "./MoretMarketMaker.sol";
import "./interfaces/EOption.sol";

contract Exchange is AccessControl, EOption{
  using FullMath for uint256;
  using MarketLibrary for uint256;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  mapping(uint256=>VolatilityToken) public volTokenAddressList;

  MoretMarketMaker internal immutable marketMaker;
  OptionVault internal immutable optionVault;
  uint256 internal immutable fundingDecimals;
  uint256 internal immutable underlyingDecimals;
  ERC20 internal immutable fundingToken;

  uint256 internal constant SECONDS_1Y = 31536000; // 365 * 24 * 60 * 60

  uint256 public volCapacityFactor = 0.5e18;
  uint256 public minTradeAmount = 1e14;
  uint256 public loanInterest = 0; // Annualised interest rate in 1e18
  uint256 public hedgingSlippage = 3e15; // 0.3% for hedging slippage (similar to DEX tx fees)
  bool public allowTrading = true;

  constructor(MoretMarketMaker _marketMaker, OptionVault _vault){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    optionVault = _vault;
    marketMaker = _marketMaker;
    fundingToken = ERC20(_vault.funding());
    fundingDecimals = ERC20(_vault.funding()).decimals();
    underlyingDecimals = ERC20(_vault.underlying()).decimals();}

  // Returns premium, costs (if sell option, cost includes collateral) and implied volatility
  function calcCost(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256 , uint256 , uint256 ){
    (uint256 _price,) = optionVault.queryPrice();
    return calcOptionCost(_tenor, _price, _strike, _amount, _poType, _side, true);}

  function calcOptionCost(uint256 _tenor, uint256 _price, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, bool _inDecimals) public view returns(uint256 _premium, uint256 _cost, uint256 _vol){
    _vol = queryOptionVolatility(_tenor, _strike, _amount, _side);
    uint256 _interest = loanInterest.muldiv(_tenor, SECONDS_1Y);
    _premium = OptionLibrary.calcPremium(_price, _vol, _strike, _poType, _amount, _interest, hedgingSlippage);
    _cost = OptionLibrary.calcCost(_price, _strike, _amount, _poType, _side, _premium);
    if(_inDecimals){
      _premium = _premium.toDecimals(fundingDecimals);
    _cost = _cost.toDecimals(fundingDecimals);}}

  function queryOptionVolatility(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.OptionSide _side) public view returns(uint256 _vol){  
    _vol = optionVault.queryVol(_tenor); // running vol
    (uint256 _price,) = optionVault.queryPrice();
    require(_amount.ethmul(_price)<=marketMaker.calcCapital(true,false),'insufficient capital');
    int256 _riskPremium = calcRiskPremium(_price, _vol, _strike, _amount, _side);
    require((SafeCast.toInt256(_vol)+_riskPremium) > 0,"Incorrect vol premium");
    _vol = SafeCast.toUint256(SafeCast.toInt256(_vol)+_riskPremium);}

  function calcRiskPremium(uint256 _price, uint256 _vol, uint256 _strike, uint256 _amount, OptionLibrary.OptionSide _side) internal view returns(int256) {
    uint256 _maxGamma = OptionLibrary.calcGamma(_price, _price, _vol).muldiv(marketMaker.calcCapital(false, false), _price);
    int256 _currentGamma = optionVault.calculateAggregateGamma(); // include sells.
    int256 _newGamma = _currentGamma + SafeCast.toInt256(OptionLibrary.calcGamma(_price, _strike, _vol).ethmul(_amount)) * (_side==OptionLibrary.OptionSide.Sell? -1: int(1));
    return (OptionLibrary.calcRiskPremiumAMM(_maxGamma, _currentGamma,  _vol, volCapacityFactor) + OptionLibrary.calcRiskPremiumAMM(_maxGamma, _newGamma, _vol, volCapacityFactor)) / 2;}

  function purchaseOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    require(minTradeAmount<= _amount, "Trade amount below minimum.");
    (uint256 _price, ) = optionVault.queryPrice();
    (uint256 _premium, uint256 _cost, uint256 _vol) = calcOptionCost(_tenor, _price, _strike, _amount, _poType, _side, true);      
    require(_payInCost >= _cost, "Incorrect cost paid.");
    uint256 _id = optionVault.addOption(_tenor, _strike, _amount, _poType, _side, _premium, _cost, _price, _vol, msg.sender);
    require(fundingToken.transferFrom(msg.sender, address(marketMaker), _payInCost), 'Failed payment.');  
    optionVault.stampActiveOption(_id, msg.sender);
    emit NewOption(msg.sender, _id, _payInCost, false);}

  function getOptionPayoffValue(uint256 _id) external view returns(uint256 _payback){
    (,_payback) = optionVault.getContractPayoff(_id);}

  function calcVolAmount(uint256 _tenor, uint256 _amount, OptionLibrary.OptionSide _side) public view returns(uint256 _volAmount, uint256 _vol, uint256 _premium, uint256 _cost, uint256 _price){
    require(address(volTokenAddressList[_tenor])!=address(0), "Tenor is not set");
    (_price, ) = optionVault.queryPrice();
    (uint256 _premiumDef, , uint256 _volTemp) = calcOptionCost(_tenor, _price, _price, _amount, OptionLibrary.PayoffType.Call, _side, false); 
    _volAmount = _premiumDef.ethdiv(_volTemp).toDecimals(volTokenAddressList[_tenor].decimals());
    (_premium, _cost, _vol) = calcOptionCost(_tenor, _price, _price, _amount, OptionLibrary.PayoffType.Call, _side, true);}

  function buyVol(uint256 _tenor, uint256 _amount, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount, , uint256 _premium, , ) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Buy);
    require(_payInCost >= _premium, "Cost incorrect");
    require(fundingToken.transferFrom(msg.sender, address(this), _premium), "vol payment error");
    volTokenAddressList[_tenor].mint(msg.sender, _volAmount);}
  
  function sellVol(uint256 _tenor, uint256 _amount, uint256 _payInVol) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount,  ,  uint256 _premium,  ,  ) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Sell);
    require(_payInVol >= _volAmount, "Cost incorrect");

    volTokenAddressList[_tenor].burn(msg.sender, _volAmount);
    require(fundingToken.transfer(msg.sender, _premium), "payment error");}  

  function buyOptionInVol(uint256 _tenor, uint256 _amount, OptionLibrary.PayoffType _poType, uint256 _payInVol) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount, uint256 _vol, uint256 _premium, uint256 _cost, uint256 _price) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Buy);
    require(_payInVol >= _volAmount, "Cost incorrect");

    volTokenAddressList[_tenor].burn(msg.sender, _volAmount);
    uint256 _id = optionVault.addOption(_tenor, _price, _amount, _poType, OptionLibrary.OptionSide.Buy, _premium, _cost, _price, _vol, msg.sender);
    require(fundingToken.transfer(address(marketMaker), _premium), 'payment error');  
    optionVault.stampActiveOption(_id, msg.sender);
    emit NewOption(msg.sender, _id, _volAmount, true);}

  function sellOptionInVol(uint256 _tenor, uint256 _amount, OptionLibrary.PayoffType _poType, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount, uint256 _vol, uint256 _premium, uint256 _cost, uint256 _price) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Sell);
    uint256 _totalCost = _premium + _cost;
    require(_payInCost >= _totalCost, "Cost incorrect");

    require(fundingToken.transferFrom(msg.sender, address(marketMaker), _cost), 'payment error'); 
    require(fundingToken.transferFrom(msg.sender, address(this), _premium), 'payment error');  
    uint256 _id = optionVault.addOption(_tenor, _price, _amount, _poType, OptionLibrary.OptionSide.Sell, _premium, _cost, _price, _vol, msg.sender);
    volTokenAddressList[_tenor].mint(msg.sender, _volAmount);
    optionVault.stampActiveOption(_id, msg.sender);
    emit NewOption(msg.sender, _id, _volAmount, true);}

  function addVolToken(uint256 _tenor, address _tokenAddress) external onlyRole(ADMIN_ROLE){ 
    require(VolatilityToken(_tokenAddress).tenor()==_tenor && VolatilityToken(_tokenAddress).tokenHash()==optionVault.tokenHash(), 'mismatched token address');
    volTokenAddressList[_tenor] = VolatilityToken(_tokenAddress);
    emit VolTokenAddition(_tenor, _tokenAddress); }

  function removeVolToken(uint256 _tenor) external onlyRole(ADMIN_ROLE){ 
    volTokenAddressList[_tenor] = VolatilityToken(address(0));
    emit VolTokenRemoved(_tenor);}

  function vaultAddress() external view returns(address){return address(optionVault);}
  function marketMakerAddress() external view returns(address) {return address(marketMaker);}

  function resetLoanRate(uint256 _loanInterest) external onlyRole(ADMIN_ROLE){ 
    loanInterest = _loanInterest;
    emit ResetParameter(100, _loanInterest);}

  function resetVolCapacityFactor(uint256 _newFactor) external onlyRole(ADMIN_ROLE){ 
    volCapacityFactor =_newFactor;
    emit ResetParameter(101, _newFactor);}

  function resetMinAmount(uint256 _newAmount) external onlyRole(ADMIN_ROLE){
    minTradeAmount = _newAmount;
    emit ResetParameter(102, _newAmount);
  }

  function resetTrading(bool _allowTrading) external onlyRole(DEFAULT_ADMIN_ROLE) {
    allowTrading=_allowTrading;
    emit ResetParameter(102, _allowTrading ? 1 : 0);}

}
