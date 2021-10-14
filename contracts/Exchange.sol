// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./OptionVault.sol";
import "./VolatilityToken.sol";
import "./MoretMarketMaker.sol";
import "./FullMath.sol";

contract Exchange is AccessControl, EOption
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    OptionLibrary.Percent public settlementFee = OptionLibrary.Percent(10 ** 3, 10 ** 6);
    OptionLibrary.Percent public volTransactionFees = OptionLibrary.Percent(5 * 10 ** 3, 10 ** 6);
    address payable public contractAddress;

    address public marketMakerAddress;
    MoretMarketMaker internal marketMaker;
    OptionVault internal optionVault;
      ERC20 internal underlyingToken;
    // mapping(uint256=>VolatilityToken) public volTokensList;

    uint256 private constant ethMultiplier = 10 ** 18;
    uint256 public maxUtilisation = 10 ** 18;
    uint256 public volatilityRiskPremiumConstant = 50 * 10 ** 16;
    uint256 public volatilitySkewConstant = 50 * 10 ** 16;

    constructor(
      address payable _marketMakerAddress,
      address _optionAddress
      // address payable _volTokenAddress
      )
    {
       _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);

      optionVault = OptionVault(_optionAddress);
      marketMakerAddress = _marketMakerAddress;
      marketMaker = MoretMarketMaker(_marketMakerAddress);
      // VolatilityToken _volToken = VolatilityToken(_volTokenAddress);
      // volTokensList[_volToken.tenor()] = _volToken;
      contractAddress = payable(address(this));

      underlyingToken = ERC20(marketMaker.underlyingAddress());
    }

    function queryOptionCost(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256){
      uint256 _vol = queryOptionVolatility(_tenor, _strike, _amount, _poType, _side);
      return optionVault.queryOptionCost(_tenor, _strike, _amount, _vol, _poType, _side);}

    // Vol = running vol + risk premium + skew premium 
    function queryOptionVolatility(uint256 _tenor, uint256 _strike, uint256 _amount,
      OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) public view returns(uint256 _vol){
      _vol = optionVault.queryVol(_tenor); // running vol
      if(_side == OptionLibrary.OptionSide.Buy){
        (_price,, _priceMultiplier) = optionVault.queryPrice();
        _vol += calcRiskPremium(_price, _priceMultiplier, _vol, _strike, _amount) + MulDiv(calcSkewPremium(_price, _priceMultiplier, _vol, _strike, _amount), MulDiv(_price>_strike? _price - _strike: _strike- _price, _priceMultiplier, _price), _priceMultiplier);}}

    function calcRiskPremium(uint256 _price, uint256 _priceMultiplier, uint256 _vol, uint256 _strike, uint256 _amount) public view returns(uint256) {
      uint256 _maxGamma = MulDiv(OptionLibrary.calcGamma(_price, _price, _priceMultiplier, _vol), MulDiv(marketMaker.calcCapital(false, false), _priceMultiplier, _price), ethMultiplier );
      int256 _currentGamma = marketMaker.getAggregateGamma(false); // include sells.
      int256 _newGamma = _currentGamma + int256(MulDiv(OptionLibrary.calcGamma(_price, _strike, _priceMultiplier, _vol), _amount, ethMultiplier )) * (_side==OptionLibrary.OptionSide.Sell? -1: 1);
      return (calcRiskPremiumAMM(_maxGamma, _currentGamma < 0 ? 0 : uint256(_currentGamma),  volatilityRiskPremiumConstant) + calcRiskPremiumAMM(_maxGamma, _newGamma < 0 ? 0 : uint256(_newGamma), volatilityRiskPremiumConstant)) / 2;}

    function calcSkewPremium(uint256 _price, uint256 _priceMultiplier, uint256 _vol, uint256 _strike, uint256 _amount) public view returns(uint256){
      uint256 _maxDelta = marketMaker.calcCapital(false, false);
      int256 _currentDelta = marketMaker.getAggregateDelta(false, true); // include sells.
      int256 _newDelta = int256(MulDiv(OptionLibrary.calcDelta(_price, _strike, _priceMultiplier, _vol), _amount, ethMultiplier ));
      if(_strike < _price){_newDelta = _amount - _newDelta;}  
      if(_side==OptionLibrary.OptionSide.Sell) {_newDelta *= -1;}
      _newDelta += _currentDelta;
      return (calcRiskPremiumAMM(_maxDelta, _newDelta < 0 ? 0 : uint256(_newDelta), volatilitySkewConstant ) + calcRiskPremiumAMM(_maxDelta, _newDelta < 0 ? 0 : uint256(_newDelta), volatilitySkewConstant)) / 2;}

    function calcRiskPremiumAMM(uint256 _max, uint256 _input, uint256 _constant) internal view returns(uint256) {
      require(_input<_max,"Capacity limit breached.");
      uint256 _capacity = ethMultiplier - MulDiv(_input, ethMultiplier, _max);
      return MulDiv(_constant, ethMultiplier, _capacity) - _constant;}


    function purchaseOption(uint256 _tenor, uint256 _strike, 
      OptionLibrary.PayoffType _poType,
      OptionLibrary.OptionSide _side,
      uint256 _amount, uint256 _payInCost)
      external
      {
        require(settlementFee.numerator < settlementFee.denominator);
      uint256 _premium = queryOptionCost(_tenor, _strike, _amount, _poType, _side );
      uint256 _fee = 0;//MulDiv(_premium, settlementFee.numerator, settlementFee.denominator);

      uint256 _id = optionVault.addOption(_tenor, _strike, _poType, _side, _amount, _premium - _fee, _fee );
      require(_payInCost >= optionVault.queryDraftOptionCost(_id, false), "Entered premium incorrect.");
      require(underlyingToken.transferFrom(msg.sender, contractAddress, _payInCost), 'Failed payment.');  

      if(_side == OptionLibrary.OptionSide.Buy){  
        require(underlyingToken.transfer(marketMakerAddress, optionVault.queryOptionPremium(_id)), 'Failed premium payment.');
      }
      
      if(_side == OptionLibrary.OptionSide.Sell){
        uint256 _netCapital = marketMaker.calcCapital(true, false);
        uint256 _premiumCollect = Math.max(_amount, _payInCost)-_payInCost;
        require(_netCapital > _premiumCollect, "Insufficient capital for options.");
        marketMaker.payExchange(_premiumCollect, contractAddress);
      }
      
      optionVault.stampActiveOption(_id, marketMaker.updateInterval());

      marketMaker.recordOption(msg.sender, _id, true);
      
      emit newOptionBought(msg.sender, optionVault.getOption(_id), _payInCost, false);
    }
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

    function getOptionPayoffValue(uint256 _id) external view returns(uint256){
      (uint256 _payoff,,) = optionVault.getOptionPayoffValue(_id);
      return _payoff;
    }

    /* unction exerciseOption(uint256 _id) external  {
        optionVault.validateOption(_id, msg.sender);

        uint256 _payoffValue = optionVault.getOptionPayoffValue(_id);

        optionVault.stampExercisedOption(_id);

        require(underlyingToken.transfer(msg.sender, _payoffValue), "Transfer failed.");

        marketMaker.recordOption(msg.sender, _id, false);

        emit optionExercised(msg.sender, optionVault.getOption(_id), _payoffValue);
    } */

    function expireOption(uint256 _id) internal {
        if(optionVault.isOptionExpiring(_id, marketMaker.updateInterval()))
        {
            (uint256 _payoffValue, uint256 _fromMarketMaker,uint256 _toMarketMaker ) = optionVault.getOptionPayoffValue(_id);

            if(_fromMarketMaker >0 )
            {
              marketMaker.payExchange(_fromMarketMaker, contractAddress);
            }

            if(_toMarketMaker >0 )
            {
              require(underlyingToken.transfer(marketMakerAddress, _toMarketMaker));
            }

            require(_payoffValue < underlyingToken.balanceOf(contractAddress), "Balance insufficient.");

            optionVault.stampExpiredOption(_id);

            address _optionHolder = optionVault.getOptionHolder(_id);
            require(underlyingToken.transfer(_optionHolder, _payoffValue), "Transfer failed.");

            marketMaker.recordOption(msg.sender, _id, false);
        }
    }

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

      function resetSettlementFees(uint256 _fee, uint256 _denominator) external onlyRole(ADMIN_ROLE){
          settlementFee = OptionLibrary.Percent(_fee, _denominator);
      }

      function resetVolTransactionFees(uint256 _fee, uint256 _denominator) external onlyRole(ADMIN_ROLE){
          volTransactionFees = OptionLibrary.Percent(_fee, _denominator);
      }

      function resetMaxUtilisation(uint256 _maxUtil) external onlyRole(ADMIN_ROLE){
          maxUtilisation = _maxUtil;
      }

      function calcUtilisation(uint256 _amount, uint256 _strike, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side)
      public view returns(uint256, uint256){
          uint256 _grossCapital = marketMaker.calcCapital(false, false);
          uint256 _netCapital = marketMaker.calcCapital(true, false);
          uint256 _incrementalCapital = optionVault.queryOptionCapitalV2(_amount, _strike, _poType, _side, marketMaker.capitalRatio());
          require((_netCapital+_incrementalCapital)<= _grossCapital, "Insufficient capital.");

          return (MulDiv(_grossCapital-_netCapital, ethMultiplier, _grossCapital), 
            MulDiv(_grossCapital-_netCapital-_incrementalCapital, ethMultiplier, _grossCapital));

          /* uint256 _newCallExposure = (_poType==OptionLibrary.PayoffType.Call)?
            ((_side==OptionLibrary.OptionSide.Buy)? (marketMaker.callExposure() + _amount):
              (marketMaker.callExposure() - Math.min(marketMaker.callExposure(), _amount)) )
            : marketMaker.callExposure();
          uint256 _newPutExposure = (_poType==OptionLibrary.PayoffType.Put)?
            ((_side==OptionLibrary.OptionSide.Buy)? (marketMaker.putExposure()+_amount):
              (marketMaker.putExposure() - Math.min(marketMaker.putExposure(), _amount)) )
            : marketMaker.putExposure();

          return (MulDiv(Math.max(marketMaker.callExposure(), marketMaker.putExposure()), ethMultiplier, _grossCapital ),
            MulDiv(Math.max(_newCallExposure, _newPutExposure) , ethMultiplier, _grossCapital )); */
      }

      function priceDecimals() external view returns(uint256){ return optionVault.priceDecimals();}
      function queryPrice() external view returns(uint256, uint256){return optionVault.queryPrice();}
      function queryVol(uint256 _tenor) external view returns(uint256, uint256){return optionVault.queryVol(_tenor);}

}
