// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./VolatilityToken.sol";
import "./MoretMarketMaker.sol";
import "./FullMath.sol";

contract Exchange is AccessControl, EOption{
  bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");
  // OptionLibrary.Percent public volTransactionFees = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6);
  // address public contractAddress;
  address public marketMakerAddress;
  // ERC20 internal underlyingToken; // used to pay premiums (vol token is alternative)
  // mapping(uint256=>VolatilityToken) public volTokensList;

  MoretMarketMaker internal marketMaker;
  IOptionVault internal optionVault;

  uint256 public volRiskPremiumMaxRatio= 18 * (10 ** 17);
  uint256 public loanInterest = 0;

  // ILendingPoolAddressesProvider internal lendingPoolAddressProvider;
  // address internal swapRouterAddress;
  // address internal aggregatorAddress;

  // uint256 private constant ethMultiplier = 10 ** 18;
  bool public allowTrading = true;
  // uint256 lendingPoolRateMode = 2;
  // bool internal useAggregator;
  // uint256 public exchangeSlippageMax = 10 ** 16; // 1% max slippage allowed
  // uint256 public exchangeDeadlineLag = 20; // 20s slippage time

  constructor( address _marketMakerAddress,address _optionAddress){// address payable _volTokenAddress)
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINER_ROLE, msg.sender);
    optionVault = IOptionVault(_optionAddress);
    marketMakerAddress = _marketMakerAddress;
    marketMaker = MoretMarketMaker(_marketMakerAddress);
    // VolatilityToken _volToken = VolatilityToken(_volTokenAddress);
    // volTokensList[_volToken.tenor()] = _volToken;
    // contractAddress = address(this);
    // underlyingToken = ERC20(marketMaker.underlyingAddress());
    // swapRouterAddress = _swapRouterAddress;
    // aggregatorAddress = _aggregatorAddress;
    // lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProvider);
    // useAggregator = false;
    }

  function calcOptionCost(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256 _premium, uint256 _cost, uint256 _price, uint256 _vol){
    _vol = queryOptionVolatility(_tenor, _strike, _amount, _side);
    uint256 _adjustedStrike = OptionLibrary.adjustSlippage(_strike, false, marketMaker.swapSlippage(), 0); // downward
    if((_poType==OptionLibrary.PayoffType.Put && _side == OptionLibrary.OptionSide.Buy) || (_poType==OptionLibrary.PayoffType.Call && _side == OptionLibrary.OptionSide.Sell)){ 
      _adjustedStrike = OptionLibrary.adjustSlippage(_strike,true, marketMaker.swapSlippage(), loanInterest);}
    (_premium, _cost, _price) = optionVault.queryOptionCost(_adjustedStrike, _amount, _vol, _poType, _side);
    _premium = MarketLibrary.cvtDecimals(_premium, marketMaker.fundingAddress());
    _cost = MarketLibrary.cvtDecimals(_cost, marketMaker.fundingAddress());}

  function queryOptionVolatility(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.OptionSide _side) public view returns(uint256 _vol){  
    _vol = optionVault.queryVol(_tenor); // running vol
    (uint256 _price,) = optionVault.queryPrice();
    _vol += calcRiskPremium(_price, _vol, _strike, _amount, _side);}

  function calcRiskPremium(uint256 _price, uint256 _vol, uint256 _strike, uint256 _amount,OptionLibrary.OptionSide _side) internal view returns(uint256) {
    uint256 _maxGamma = MulDiv(OptionLibrary.calcGamma(_price, _price, _vol), marketMaker.calcCapital(false, false), _price);
    int256 _currentGamma = marketMaker.getAggregateGamma(false); // include sells.
    int256 _newGamma = _currentGamma + int256(MulDiv(OptionLibrary.calcGamma(_price, _strike, _vol), _amount, OptionLibrary.Multiplier() )) * (_side==OptionLibrary.OptionSide.Sell? -1: int(1));
    uint256 _K = MulDiv(_vol, volRiskPremiumMaxRatio, OptionLibrary.Multiplier());
    return (calcRiskPremiumAMM(_maxGamma, _currentGamma,  _K) + calcRiskPremiumAMM(_maxGamma, _newGamma, _K)) / 2;}

  function calcRiskPremiumAMM(uint256 _max, int256 _input, uint256 _constant) internal pure returns(uint256) {
    int256 _capacity = int256(OptionLibrary.Multiplier()); // capacity should be in (0,2)
    if(_input < 0){_capacity +=  int256(MulDiv(uint256(-_input), OptionLibrary.Multiplier(), _max));}
    if(_input > 0){ _capacity -= int256(MulDiv(uint256(_input) , OptionLibrary.Multiplier(), _max));}
    require(_capacity<=0 || _capacity >= 2,"Capacity limit breached.");
    return MulDiv(_constant, OptionLibrary.Multiplier(), uint256(_capacity)) - _constant;}

  function purchaseOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _payInCost) external {
    require(allowTrading,"Trading stopped!");
    (uint256 _premium, uint256 _cost, uint256 _price, uint256 _vol) = calcOptionCost(_tenor, _strike, _amount, _poType, _side );      
    require(_payInCost >= _cost, "Incorrect cost paid.");
    uint256 _id = optionVault.addOption(_tenor, _strike, _amount, _poType, _side, _premium, _cost, _price, _vol, msg.sender);
    require(ERC20(marketMaker.fundingAddress()).transferFrom(msg.sender, address(marketMaker), _payInCost), 'Failed payment.');  
    // emit newOptionBought(msg.sender, optionVault.getOption(_id), _payInCost, false);
    optionVault.stampActiveOption(_id);
    marketMaker.recordOptionPurchase(msg.sender, _id);}

  function getOptionPayoffValue(uint256 _id) external view returns(uint256 _payback){
    (,_payback) = optionVault.getContractPayoff(_id);}

/* 
    function purchaseOptionInVol(uint256 _tenor, uint256 _strike, OptionLibrary.PayoffType _poType,
      uint256 _amount, uint256 _payInCost)
      external
      {
      uint256 _premium = queryOptionCost(_tenor, _strike, _amount, _poType,OptionLibrary.OptionSide.Buy );
      uint256 _fee = MulDiv(_premium, settlementFee.numerator, settlementFee.denominator);

      uint256 _id = optionVault.addOption(_tenor, _strike, _poType, OptionLibrary.OptionSide.Buy, _amount, _premium - _fee, _fee );
      require(_payInCost >= optionVault.queryDraftOptionCost(_id, true), "Entered premium incorrect.");

      require(volTokensList[_tenor].transferFrom(msg.sender, contractAddress, _payInCost), 'Failed payment.');

      volTokensList[_tenor].approve(volTokensList[_tenor].contractAddress(), _payInCost);
      volTokensList[_tenor].recycleInToken(contractAddress, _payInCost, underlyingToken);
      require(underlyingToken.transfer(marketMakerAddress, optionVault.queryOptionPremium(_id)), 'Failed premium payment.');

      optionVault.stampActiveOption(_id);

      marketMaker.recordOption(msg.sender, _id, true,
        optionVault.queryOptionPremium(_id),
        optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Call),
        optionVault.queryOptionExposure(_id, OptionLibrary.PayoffType.Put));

      emit newOptionBought(msg.sender, optionVault.getOption(_id), _payInCost, true);

    } */


      // function addVolToken(address payable _tokenAddress) external onlyRole(ADMIN_ROLE)
      // {
      //     VolatilityToken _volToken = VolatilityToken(_tokenAddress);
      //     /* require(_volToken.descriptionHash() == optionVault.descriptionHash());
      //     require(optionVault.containsTenor(_volToken.tenor())); */

      //     volTokensList[_volToken.tenor()] = _volToken;

      // }

      // function quoteVolatilityCost(uint256 _tenor, uint256 _volAmount) public view returns(uint256, uint256)
      // {
      //     /* require(optionVault.containsTenor(_tenor)); */

      //     (uint256 _price,) = optionVault.queryPrice();
      //     (uint256 _volatility, ) = optionVault.queryVol(_tenor);

      //     uint256 _value = volTokensList[_tenor].calculateMintValue(_volAmount, _price, _volatility);
      //     uint256 _fee = _value * volTransactionFees.numerator/ volTransactionFees.denominator;

      //     return (_value, _fee);
      // }

      // function purchaseVolatilityToken(uint256 _tenor, uint256 _volAmount, uint256 _payInCost)
      // external {
      //     (uint256 _value, uint256 _fee) = quoteVolatilityCost(_tenor, _volAmount);
      //     require(_payInCost >= (_value + _fee));

      //     underlyingToken.transferFrom(msg.sender, address(volTokensList[_tenor]), _value);
      //     volTokensList[_tenor].mint{value: _value}(msg.sender, _volAmount);

      //     emit newVolatilityTokenBought(msg.sender, block.timestamp, _tenor, _volAmount);
      // }

    function resetLoanRate(uint256 _loanInterest) external onlyRole(MINER_ROLE){ loanInterest = _loanInterest;}
    function resetRiskPremiumMaxRatio(uint256 _newRatio) external onlyRole(DEFAULT_ADMIN_ROLE){ volRiskPremiumMaxRatio=_newRatio;}
    function resetTrading(bool _allowTrading) external onlyRole(DEFAULT_ADMIN_ROLE) {allowTrading=_allowTrading;}
    function queryPrice() external view returns(uint256, uint256){return optionVault.queryPrice();}
    function queryVol(uint256 _tenor) external view returns(uint256){return optionVault.queryVol(_tenor);}
}
