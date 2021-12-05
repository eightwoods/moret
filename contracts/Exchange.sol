// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MoretInterfaces.sol";
import "./VolatilityToken.sol";
import "./MoretMarketMaker.sol";

contract Exchange is AccessControl, EOption{
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  address public vaultAddress;
  address public marketMakerAddress;
  mapping(uint256=>address) public volTokenAddressList;

  MoretMarketMaker internal marketMaker;
  OptionVault internal optionVault;

  uint256 public volCapacityFactor = 5 * (10 ** 17);
  uint256 public loanInterest = 0;
  bool public allowTrading = true;

  constructor( address _marketMakerAddress,address _vaultAddress){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    vaultAddress = _vaultAddress;
    optionVault = OptionVault(_vaultAddress);
    marketMakerAddress = _marketMakerAddress;
    marketMaker = MoretMarketMaker(_marketMakerAddress);}

  function calcCost(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256 , uint256 , uint256 ){
    (uint256 _price,) = optionVault.queryPrice();
    return calcOptionCost(_tenor, _price, _strike, _amount, _poType, _side);}

  function calcOptionCost(uint256 _tenor, uint256 _price, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256 _premium, uint256 _cost, uint256 _vol){
    _vol = queryOptionVolatility(_tenor, _strike, _amount, _side);
    // uint256 _adjustedStrike = OptionLibrary.adjustStrike(_strike, _poType, _side, marketMaker.swapSlippage(), loanInterest); 
    (_premium, _cost) = OptionLibrary.calcOptionCost(_price, _strike, _amount, _vol, _poType, _side);
    _premium = MarketLibrary.cvtDecimals(_premium, optionVault.funding());
    _cost = MarketLibrary.cvtDecimals(_cost, optionVault.funding());}

  function queryOptionVolatility(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.OptionSide _side) public view returns(uint256 _vol){  
    _vol = optionVault.queryVol(_tenor); // running vol
    (uint256 _price,) = optionVault.queryPrice();
    require(MulDiv(_amount, _price, OptionLibrary.Multiplier())<=marketMaker.calcCapital(true,false),'insufficient capital');
    int256 _riskPremium = calcRiskPremium(_price, _vol, _strike, _amount, _side);
    require((int256(_vol)+_riskPremium) > 0,"Incorrect vol premium");
    _vol = uint256(int256(_vol)+_riskPremium);}

  function calcRiskPremium(uint256 _price, uint256 _vol, uint256 _strike, uint256 _amount, OptionLibrary.OptionSide _side) internal view returns(int256) {
    uint256 _maxGamma = MulDiv(OptionLibrary.calcGamma(_price, _price, _vol), marketMaker.calcCapital(false, false), _price);
    int256 _currentGamma = optionVault.calculateAggregateGamma(); // include sells.
    int256 _newGamma = _currentGamma + int256(MulDiv(OptionLibrary.calcGamma(_price, _strike, _vol), _amount, OptionLibrary.Multiplier() )) * (_side==OptionLibrary.OptionSide.Sell? -1: int(1));
    return (OptionLibrary.calcRiskPremiumAMM(_maxGamma, _currentGamma,  _vol, volCapacityFactor) + OptionLibrary.calcRiskPremiumAMM(_maxGamma, _newGamma, _vol, volCapacityFactor)) / 2;}

  function purchaseOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _price, ) = optionVault.queryPrice();
    (uint256 _premium, uint256 _cost, uint256 _vol) = calcOptionCost(_tenor, _price, _strike, _amount, _poType, _side );      
    require(_payInCost >= _cost, "Incorrect cost paid.");
    uint256 _id = optionVault.addOption(_tenor, _strike, _amount, _poType, _side, _premium, _cost, _price, _vol, msg.sender);
    require(ERC20(optionVault.funding()).transferFrom(msg.sender, marketMakerAddress, _payInCost), 'Failed payment.');  
    optionVault.stampActiveOption(_id, msg.sender);
    emit newOptionBought(msg.sender, optionVault.getOption(_id), _payInCost, false);}

  function getOptionPayoffValue(uint256 _id) external view returns(uint256 _payback){
    (,_payback) = optionVault.getContractPayoff(_id);}

  function calcVolAmount(uint256 _tenor, uint256 _amount, OptionLibrary.OptionSide _side) public view returns(uint256 _volAmount, uint256 _vol, uint256 _premium, uint256 _cost, uint256 _price){
    require(volTokenAddressList[_tenor]!=address(0), "Tenor is not set");
    (_price, ) = optionVault.queryPrice();
    (_premium, _cost, _vol) = calcOptionCost(_tenor, _price, _price, _amount, OptionLibrary.PayoffType.Call, _side); 
    _volAmount = MarketLibrary.cvtDecimals(MulDiv(_premium, OptionLibrary.Multiplier(), _vol), volTokenAddressList[_tenor]);}

  function buyVol(uint256 _tenor, uint256 _amount, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount, , uint256 _premium, , ) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Buy);
    require(_payInCost >= _premium, "Cost incorrect");
    require(ERC20(optionVault.funding()).transferFrom(msg.sender, address(this), _premium), "vol payment error");
    VolatilityToken(volTokenAddressList[_tenor]).mint(msg.sender, _volAmount);
    emit volatilityTokenBought(msg.sender, block.timestamp, _tenor, _volAmount, _premium);}
  
  function sellVol(uint256 _tenor, uint256 _amount, uint256 _payInVol) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount,  ,  uint256 _premium,  ,  ) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Sell);
    require(_payInVol >= _volAmount, "Cost incorrect");
    require(ERC20(optionVault.funding()).balanceOf(address(this))>=_premium, "insufficient usdc in exchange.");

    VolatilityToken(volTokenAddressList[_tenor]).burn(msg.sender, _volAmount);
    require(ERC20(optionVault.funding()).transfer(msg.sender, _premium), "payment error");
    emit volatilityTokenSold(msg.sender, block.timestamp, _tenor, _volAmount, _premium);}  

  function buyOptionInVol(uint256 _tenor, uint256 _amount, OptionLibrary.PayoffType _poType, uint256 _payInVol) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount, uint256 _vol, uint256 _premium, uint256 _cost, uint256 _price) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Buy);
    require(_payInVol >= _volAmount, "Cost incorrect");
    require(ERC20(optionVault.funding()).balanceOf(address(this))>=_premium, "insufficient usdc in exchange.");

    VolatilityToken(volTokenAddressList[_tenor]).burn(msg.sender, _volAmount);
    uint256 _id = optionVault.addOption(_tenor, _price, _amount, _poType, OptionLibrary.OptionSide.Buy, _premium, _cost, _price, _vol, msg.sender);
    require(ERC20(optionVault.funding()).transfer(marketMakerAddress, _premium), 'payment error');  
    optionVault.stampActiveOption(_id, msg.sender);
    emit newOptionBought(msg.sender, optionVault.getOption(_id), _volAmount, true);}

  function sellOptionInVol(uint256 _tenor, uint256 _amount, OptionLibrary.PayoffType _poType, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _volAmount, uint256 _vol, uint256 _premium, uint256 _cost, uint256 _price) = calcVolAmount(_tenor, _amount, OptionLibrary.OptionSide.Sell);
    uint256 _totalCost = _premium + _cost;
    require(_payInCost >= _totalCost, "Cost incorrect");

    require(ERC20(optionVault.funding()).transferFrom(msg.sender, marketMakerAddress, _cost), 'payment error'); 
    require(ERC20(optionVault.funding()).transferFrom(msg.sender, address(this), _premium), 'payment error');  
    uint256 _id = optionVault.addOption(_tenor, _price, _amount, _poType, OptionLibrary.OptionSide.Sell, _premium, _cost, _price, _vol, msg.sender);
    VolatilityToken(volTokenAddressList[_tenor]).mint(msg.sender, _volAmount);
    optionVault.stampActiveOption(_id, msg.sender);
    emit newOptionBought(msg.sender, optionVault.getOption(_id), _volAmount, true);}

  function addVolToken(uint256 _tenor, address _tokenAddress) external onlyRole(ADMIN_ROLE){ 
    require(VolatilityToken(volTokenAddressList[_tenor]).tenor()==_tenor && VolatilityToken(volTokenAddressList[_tenor]).tokenHash()==optionVault.tokenHash(), 'mismatched token address');
    volTokenAddressList[_tenor] = _tokenAddress; }
  function removeVolToken(uint256 _tenor) external onlyRole(ADMIN_ROLE){ volTokenAddressList[_tenor] = address(0);}
  
  function resetLoanRate(uint256 _loanInterest) external onlyRole(ADMIN_ROLE){ loanInterest = _loanInterest;}
  function resetVolCapacityFactor(uint256 _newFactor) external onlyRole(ADMIN_ROLE){ volCapacityFactor =_newFactor;}
  function resetTrading(bool _allowTrading) external onlyRole(DEFAULT_ADMIN_ROLE) {allowTrading=_allowTrading;}
}
