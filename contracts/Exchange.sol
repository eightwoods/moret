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
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE"); // setting parameters and see the overall positions
  bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");
  // OptionLibrary.Percent public volTransactionFees = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6);
  // address public contractAddress;
  // address public marketMakerAddress;
  // ERC20 internal underlyingToken; // used to pay premiums (vol token is alternative)
  // mapping(uint256=>VolatilityToken) public volTokensList;

  MoretMarketMaker internal marketMaker;
  IOptionVault internal optionVault;
  ILendingPoolAddressesProvider internal lendingPoolAddressProvider;
  address internal swapRouterAddress;
  address internal aggregatorAddress;

  uint256 private constant ethMultiplier = 10 ** 18;
  uint256 public volRiskPremiumMaxRatio = 18 * (10 ** 17);
  uint256 lendingPoolRateMode = 2;
  bool internal useAggregator;
  uint256 public exchangeSlippageMax = 10 ** 16; // 1% max slippage allowed
  uint256 public exchangeDeadlineLag = 20; // 20s slippage time
  uint256 public exchangeSlippageUp = 0;
  uint256 public exchangeSlippageDown = 0;
  uint256 public loanInterest = 0;

  constructor( address _marketMakerAddress,address _optionAddress, address _swapRouterAddress, address _aggregatorAddress, address _lendingPoolAddressProvider){// address payable _volTokenAddress)
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(MINER_ROLE, msg.sender);
    optionVault = IOptionVault(_optionAddress);
    // marketMakerAddress = _marketMakerAddress;
    marketMaker = MoretMarketMaker(_marketMakerAddress);
    // VolatilityToken _volToken = VolatilityToken(_volTokenAddress);
    // volTokensList[_volToken.tenor()] = _volToken;
    // contractAddress = payable(address(this));
    // underlyingToken = ERC20(marketMaker.underlyingAddress());
    swapRouterAddress = _swapRouterAddress;
    aggregatorAddress = _aggregatorAddress;
    lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProvider);
    useAggregator = false;}

  function queryOptionCost(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256, uint256){
    uint256 _vol = queryOptionVolatility(_tenor, _strike, _amount, _side);
    return optionVault.queryOptionCost(_tenor, _strike, _amount, _vol, _poType, _side);}

  function queryOptionVolatility(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.OptionSide _side) public view returns(uint256 _vol){  
    _vol = optionVault.queryVol(_tenor); // running vol
    (uint256 _price,, uint256 _priceMultiplier) = optionVault.queryPrice();
    _vol += calcRiskPremium(_price, _priceMultiplier, _vol, _strike, _amount, _side);}

  function calcRiskPremium(uint256 _price, uint256 _priceMultiplier, uint256 _vol, uint256 _strike, uint256 _amount,OptionLibrary.OptionSide _side) internal view returns(uint256) {
    uint256 _maxGamma = MulDiv(OptionLibrary.calcGamma(_price, _price, _priceMultiplier, _vol), MulDiv(marketMaker.calcCapital(false, false), _priceMultiplier, _price), ethMultiplier );
    int256 _currentGamma = marketMaker.getAggregateGamma(false); // include sells.
    int256 _newGamma = _currentGamma + int256(MulDiv(OptionLibrary.calcGamma(_price, _strike, _priceMultiplier, _vol), _amount, ethMultiplier )) * (_side==OptionLibrary.OptionSide.Sell? -1: int(1));
    uint256 _K = MulDiv(_vol, volRiskPremiumMaxRatio, ethMultiplier);
    return (calcRiskPremiumAMM(_maxGamma, _currentGamma,  _K) + calcRiskPremiumAMM(_maxGamma, _newGamma, _K)) / 2;}

  function calcRiskPremiumAMM(uint256 _max, int256 _input, uint256 _constant) internal pure returns(uint256) {
    int256 _capacity = int256(ethMultiplier); // capacity should be in (0,2)
    if(_input < 0){_capacity +=  int256(MulDiv(uint256(-_input), ethMultiplier, _max));}
    if(_input > 0){ _capacity -= int256(MulDiv(uint256(_input) , ethMultiplier, _max));}
    require(_capacity<=0 || _capacity >= 2,"Capacity limit breached.");
    return MulDiv(_constant, ethMultiplier, uint256(_capacity)) - _constant;}

  function purchaseOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _payInCost, uint256 _price, uint256 _volatility) external {
    (uint256 _premium, uint256 _cost) = queryOptionCost(_tenor, _strike, _amount, _poType, _side );      
    require(_payInCost >= _cost, "Incorrect cost paid.");
    uint256 _id = optionVault.addOption(_tenor, _strike, _amount, _poType, _side, _premium, _cost, _price, _volatility);
    require(ERC20(marketMaker.fundingAddress()).transferFrom(msg.sender, address(marketMaker), _payInCost), 'Failed payment.');  
    // emit newOptionBought(msg.sender, optionVault.getOption(_id), _payInCost, false);
    optionVault.stampActiveOption(_id);
    marketMaker.recordOptionPurchase(msg.sender, _id);}

  function executeHedgeTrades() external onlyRole(MINER_ROLE){
    (uint256 _targetUnderlying, int256 _chgDebt, int256 _chgCollateral) = marketMaker.calcHedgeTrade();
    if(_chgDebt > 0){ 
      if(_chgCollateral>0) marketMaker.depositCollateral(uint256(_chgCollateral), lendingPoolAddressProvider.getLendingPool());
      marketMaker.borrowLoans(uint256(_chgDebt),lendingPoolAddressProvider.getLendingPool(), lendingPoolRateMode);
      if(_chgCollateral<0) marketMaker.withdrawCollateral(uint256(-_chgCollateral), lendingPoolAddressProvider.getLendingPool());
      swapToFunding(uint256(_chgDebt));}
    if(_chgDebt < 0){  
      swapToUnderlying(uint256(-_chgDebt));
      marketMaker.repayLoans(uint256(-_chgDebt), lendingPoolAddressProvider.getLendingPool(), lendingPoolRateMode);
      if(_chgCollateral<0) marketMaker.withdrawCollateral(uint256(-_chgCollateral), lendingPoolAddressProvider.getLendingPool());
      if(_chgCollateral>0) marketMaker.depositCollateral(uint256(_chgCollateral), lendingPoolAddressProvider.getLendingPool());}
    uint256 _currentMarketMakerUnderlying = ERC20(marketMaker.underlyingAddress()).balanceOf(address(marketMaker));
    if( _currentMarketMakerUnderlying > _targetUnderlying){
      swapToFunding(_currentMarketMakerUnderlying - _targetUnderlying);}
    if(_currentMarketMakerUnderlying < _targetUnderlying){
      swapToUnderlying(_targetUnderlying - _currentMarketMakerUnderlying);}}

  function swapToUnderlying(uint256 _underlyingAmount) internal  returns(uint256 _paidCost){
    _paidCost = 0;
    if(useAggregator) (_paidCost,) = marketMaker.swapToUnderlyingAtAggregator(_underlyingAmount, swapRouterAddress, exchangeSlippageMax);
    if(!useAggregator) { 
      uint256[] memory _swappedAmounts = marketMaker.swapToUnderlyingAtVenue(_underlyingAmount, swapRouterAddress, exchangeSlippageMax, exchangeDeadlineLag);
      _paidCost = _swappedAmounts[0];}}

  function swapToFunding(uint256 _underlyingAmount) internal  returns(uint256 _returnedFunding){
    _returnedFunding = 0;
    if(useAggregator) _returnedFunding = marketMaker.swapToFundingAtAggregator(_underlyingAmount, swapRouterAddress, exchangeSlippageMax);
    if(!useAggregator) { 
      uint256[] memory _swappedAmounts =marketMaker.swapToFundingAtVenue(_underlyingAmount, swapRouterAddress, exchangeSlippageMax, exchangeDeadlineLag);
      _returnedFunding = _swappedAmounts[1];}}

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

  // function getOptionPayoffValue(uint256 _id) external view returns(uint256){return optionVault.getContractPayoff(_id);}

    /* unction exerciseOption(uint256 _id) external  {
        optionVault.validateOption(_id, msg.sender);

        uint256 _payoffValue = optionVault.getOptionPayoffValue(_id);

        optionVault.stampExercisedOption(_id);

        require(underlyingToken.transfer(msg.sender, _payoffValue), "Transfer failed.");

        marketMaker.recordOption(msg.sender, _id, false);

        emit optionExercised(msg.sender, optionVault.getOption(_id), _payoffValue);
    } */

  // function expireOption(uint256 _id) external {
  //       if(optionVault.isOptionExpiring(_id, marketMaker.updateInterval()))
  //       {
  //           (uint256 _payoffValue, uint256 _fromMarketMaker,uint256 _toMarketMaker ) = optionVault.getOptionPayoffValue(_id);

  //           if(_fromMarketMaker >0 )
  //           {
  //             marketMaker.payExchange(_fromMarketMaker, contractAddress);
  //           }

  //           if(_toMarketMaker >0 )
  //           {
  //             require(underlyingToken.transfer(marketMakerAddress, _toMarketMaker));
  //           }

  //           require(_payoffValue < underlyingToken.balanceOf(contractAddress), "Balance insufficient.");

  //           optionVault.stampExpiredOption(_id);

  //           address _optionHolder = optionVault.getOptionHolder(_id);
  //           require(underlyingToken.transfer(_optionHolder, _payoffValue), "Transfer failed.");

  //           marketMaker.recordOption(msg.sender, _id, false);
  //       }
  //   }

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

      // function sweepBalance() external onlyRole(ADMIN_ROLE){
      //       require(underlyingToken.transfer(msg.sender, underlyingToken.balanceOf(contractAddress)), "Withdrawal failed.");
      // }

      // function resetVolTransactionFees(uint256 _fee, uint256 _denominator) external onlyRole(ADMIN_ROLE){
      //     volTransactionFees = OptionLibrary.Percent(_fee, _denominator);
      // }
      

      // function calcUtilisation(uint256 _amount, uint256 _strike, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side)
      // public view returns(uint256, uint256){
      //     uint256 _grossCapital = marketMaker.calcCapital(false, false);
      //     uint256 _netCapital = marketMaker.calcCapital(true, false);
      //     uint256 _incrementalCapital = optionVault.queryOptionCapitalV2(_amount, _strike, _poType, _side, marketMaker.capitalRatio());
      //     require((_netCapital+_incrementalCapital)<= _grossCapital, "Insufficient capital.");

      //     return (MulDiv(_grossCapital-_netCapital, ethMultiplier, _grossCapital), 
      //       MulDiv(_grossCapital-_netCapital-_incrementalCapital, ethMultiplier, _grossCapital));

      //     /* uint256 _newCallExposure = (_poType==OptionLibrary.PayoffType.Call)?
      //       ((_side==OptionLibrary.OptionSide.Buy)? (marketMaker.callExposure() + _amount):
      //         (marketMaker.callExposure() - Math.min(marketMaker.callExposure(), _amount)) )
      //       : marketMaker.callExposure();
      //     uint256 _newPutExposure = (_poType==OptionLibrary.PayoffType.Put)?
      //       ((_side==OptionLibrary.OptionSide.Buy)? (marketMaker.putExposure()+_amount):
      //         (marketMaker.putExposure() - Math.min(marketMaker.putExposure(), _amount)) )
      //       : marketMaker.putExposure();

      //     return (MulDiv(Math.max(marketMaker.callExposure(), marketMaker.putExposure()), ethMultiplier, _grossCapital ),
      //       MulDiv(Math.max(_newCallExposure, _newPutExposure) , ethMultiplier, _grossCapital )); */
      // }

      function resetRiskPremiumMaxRatio(uint256 _newRatio) external onlyRole(ADMIN_ROLE){ volRiskPremiumMaxRatio=_newRatio;}
      function queryPrice() external view returns(uint256, uint256, uint256){return optionVault.queryPrice();}
      function queryVol(uint256 _tenor) external view returns(uint256){return optionVault.queryVol(_tenor);}
}
