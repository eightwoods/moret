/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "./FullMath.sol";
/* import "../interfaces/Interfaces.sol"; */
import "./VolatilityToken.sol";
import "./VolatilityChain.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/* import "https://github.com/smartcontractkit/chainlink/blob/master/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol"; */

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/* import "@openzeppelin/contracts/utils/math/Math.sol"; */
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Router02.sol";
/* import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol'; */
/* import "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol"; */

//import "https://github.com/Uniswap/uniswap-v3-periphery/blob/v1.0.0/contracts/SwapRouter.sol";
//import '@quickswap/QuickSwap-periphery/contracts/interfaces/IUniswapV2Router02.sol';


contract MarketMaker is ERC20, AccessControl
{
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;
  /* using Math for uint256; */

  address payable contractAddr;
  address payable governanceAddr;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  /* address internal constant CHAINLINK_FEED_ADDRESS = 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada; */
  address internal constant UNISWAP_ROUTER_ADDRESS = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
  /* address internal constant AAVE_LENDING_ADDRESS = 0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe; */

  address internal constant DAI_ADDRESS = 0x2d7882beDcbfDDce29Ba99965dd3cdF7fcB10A1e;
  address internal constant TOKEN_ADDRESS = 0x0000000000000000000000000000000000001010;

  /* address internal constant VOLCHAIN_ADDRESS = 0xf425f1274A20E801B9Bd8e6dF6414F0e337d5fba;
  address internal constant GOVERNANCE_ADDRESS = 0xaaebF0f601355831a64823A89AbdFF6f1e43D592; */

  VolatilityChain internal volatilityChain;
  IUniswapV2Router02 uniswapRouter;
  /* IPeripheryPayments uniswapPayments; */
  /* ILendingPool lendingPool; */

  mapping(bytes32=>ERC20) fundingTokens;
  bytes32 mainFundingHash = keccak256(abi.encodePacked("DAI"));
  EnumerableSet.Bytes32Set fundingHashList;
  ERC20 underlyingToken;

  mapping(uint256=>VolatilityToken) volTokensList;

  uint256 private constant ethMultiplier = 10 ** 18;
  uint256 private BLOCKTIME = 20;


  uint256 public constant pctDenominator = 10 ** 6;
  uint256 public maxCollateralisation = 15 * 10 ** 5;
  uint256 public volPremiumFixedAddon = 5000 ;
  uint256 public deltaRange = 8 * 10 ** 5;

  uint256 public volPremiumUtilityMultiplier = 10 ** 5 ;
  uint256 public underCollateralisationPenalty = 5 * 10 ** 5;
  /* uint256 public volPremiumHedgeCapacityAnchor = 250000 ;
  uint256 public volPremiumHedgeCapacityMultiplier = 100000 ; */

  uint256 public governanceFees = 5000;

  uint256 public uniswapSlippageAllowance;
  uint24 public uniswapFee = 10000;


  mapping(uint256=> Option) internal optionsList;
  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;
  uint256 public optionCounter = 0;
  EnumerableSet.AddressSet addressList;

  int256 public hedgePositionAmount;


    uint256 public priceMultiplier;
    uint256 public priceDecimals;
    EnumerableSet.UintSet tenors;

    enum PayoffType { Call, Put }
    enum OptionStatus { Draft, Active, Exercised, Expired}
    struct Option {
        PayoffType poType;
        address holder;
        OptionStatus status;
        uint256 id;
        uint256 createTime;
        uint256 effectiveTime;
        uint256 tenor;
        uint256 exerciseTime;

        uint256 amount; // could be negative if options are sold.
        uint256 spot;
        uint256 strike;
        uint256 volatility;
        uint256 premium;
        uint256 fee;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address chainlink_address,
        address moret_token_address,
        address vol_chain_address
        )  payable
    ERC20(_name, _symbol)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        fundingHashList.add(mainFundingHash);

      priceInterface = AggregatorV3Interface(chainlink_address);
      uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
      /* uniswapPayments = IPeripheryPayments(UNISWAP_ROUTER_ADDRESS); */
      /* lendingPool = ILendingPool(AAVE_LENDING_ADDRESS); */
      underlyingToken = ERC20(TOKEN_ADDRESS);
      fundingTokens[mainFundingHash] = ERC20(DAI_ADDRESS);
      volatilityChain = VolatilityChain(vol_chain_address);

      priceDecimals = priceInterface.decimals();
      priceMultiplier = 10 ** priceDecimals;

      contractAddr = payable(address(this));
      governanceAddr = payable(moret_token_address);

      /* underlyingToken.transferFrom(msg.sender, contractAddr, _initialCapital); */
      _mint(msg.sender, ethMultiplier);
    }

    function addVolToken(uint256 _tenor, address payable _tokenAddress) external onlyRole(ADMIN_ROLE)
    {
        if(!tenors.contains(_tenor)){
            tenors.add(_tenor);
            emit newTenor(_tenor);
        }
        volTokensList[_tenor] = VolatilityToken(_tokenAddress);

        emit newVolatilityToken(_tenor, _tokenAddress);
    }

    function removeTenor(uint256 _tenor) external onlyRole(ADMIN_ROLE) {
        require(tenors.contains(_tenor));
        tenors.remove( _tenor);
    }

    function queryPrice() public view returns(uint256, uint256){
    (,int _price,,uint _timeStamp,) = priceInterface.latestRoundData();
   return (uint256(_price), uint256(_timeStamp));
  }

    function queryPremium(uint256 _tenor, uint256 _strike, PayoffType _poType, uint256 _amount) public view returns(uint256)
    {
        require(tenors.contains(_tenor));
        require((_poType==PayoffType.Call) || (_poType==PayoffType.Put));

        (uint256 _price,) = queryPrice();
        uint256 _volatility = volatilityChain.getVol(_tenor);

        return  calcTotalPremium(_price, _volatility, _strike, _poType, _amount);
    }


    function calcTotalPremium(uint256 _price, uint256 _volatility, uint256 _strike, PayoffType _poType, uint256 _amount) public view returns(uint256){
        uint256 _intrinsicValue = calcIntrinsicValue(_strike, _price, _poType) * _amount / priceMultiplier;
        uint256 _timeValue = calcTimeValue( _price, _volatility, volPremiumFixedAddon) * _amount / priceMultiplier;
        /* uint256 _margin = MulDiv(volPremiumFixedAddon, _amount, pctDenominator); */
        uint256 _addon = calcVolPremiumAddon(_strike, _poType, _amount);

        return ((_intrinsicValue + _timeValue) * (pctDenominator + _addon) / pctDenominator) * priceMultiplier / _price;
    }


    function calcIntrinsicValue(uint256 _strike, uint256 _price, PayoffType _poType) public pure returns(uint256)
    {
        uint256 _intrinsicValue = 0;

        if((_poType==PayoffType.Call) && (_price > _strike)){
          _intrinsicValue = _price - _strike;
        }
        if((_poType==PayoffType.Put) && (_price<_strike)){
          _intrinsicValue = _strike - _price;
        }
        return _intrinsicValue;
    }

    function calcTimeValue(uint256 _price, uint256 _volatility, uint256 _volatilityPremium) public view returns(uint256)
    {
        uint256 _timeValue =  (_price * 4 * (_volatility+(_volatilityPremium * priceMultiplier / pctDenominator)) / 10 / priceMultiplier);
        return _timeValue;
    }


    function calcVolPremiumAddon(uint256 _strike, PayoffType  _poType, uint256 _amount) public view returns(uint256){
        //int256 _delta = calculateContractDelta( _strike,   _poType,  _amount);
        uint256 _utilityAddon = calcUtilityPremiumAddon(_amount, _poType);
        /* uint256 _hedgeCapacityAddon = calcHedgeCapacityPremiumAddon(_delta); */
        return _utilityAddon;//+ _hedgeCapacityAddon;
    }

    function calcUtilityPremiumAddon(uint256 _amount, PayoffType  _poType) public view returns(uint256){
        (uint256 _utilityBefore, uint256 _utilityAfter) = calcUtilityRatios(_amount, _poType);
        require(_utilityBefore < maxCollateralisation, "Max collateralisation breached.");
        require(_utilityAfter < maxCollateralisation, "Max collateralisation breached.");

        uint256 _addonBefore = volPremiumUtilityMultiplier * _utilityBefore /pctDenominator;
        if(_utilityBefore>pctDenominator)
        {
            _addonBefore += underCollateralisationPenalty *( _utilityBefore - pctDenominator)/ pctDenominator;
        }

        uint256 _addonAfter = (volPremiumUtilityMultiplier * _utilityAfter/ pctDenominator);
        if(_utilityAfter>pctDenominator)
        {
            _addonAfter += (underCollateralisationPenalty* ( _utilityAfter - pctDenominator) / pctDenominator);
        }

        return (_addonBefore + _addonAfter) / 2;
    }

    function calcUtilityRatios(uint256 _amount, PayoffType  _poType) public view returns(uint256, uint256){
        (uint256 _callExposures, uint256 _putExposures) = calculateOptionExposures();
        uint256 _grossCapital = calculateGrossCapital();
        uint256 _existingExposure = _callExposures>= _putExposures? _callExposures: _putExposures;

        if(_poType==PayoffType.Call){
          _callExposures+= _amount;
        }
        if(_poType==PayoffType.Put){
          _putExposures+= _amount;
        }
        uint256 _newExposure = _callExposures>= _putExposures? _callExposures: _putExposures;

        return ((_existingExposure * pctDenominator / _grossCapital ), (_newExposure * pctDenominator/ _grossCapital ));
    }
/*
    function calcHedgeCapacityPremiumAddon(int256 _delta) public view returns(uint256){
        (uint256 _utilityBefore, uint256 _utilityAfter) = calcHedgeCapacity(_delta);
        uint256 _addNumerator = MulDiv(volPremiumHedgeCapacityMultiplier, volPremiumHedgeCapacityAnchor, pctDenominator - volPremiumHedgeCapacityAnchor ) ;
        uint256 _addBefore = MulDiv(_addNumerator, pctDenominator - _utilityBefore, _utilityBefore);
        uint256 _addAfter = MulDiv(_addNumerator, pctDenominator - _utilityAfter, _utilityAfter);
        return (_addBefore + _addAfter) / 2;
    }

    function calcHedgeCapacity(int256 _additionalDelta) public view returns(uint256, uint256){
        uint256 _grossCapital = calculateGrossCapital();
        int256 _totalDelta = calculateTotalDelta();
        int256 _newDelta = _totalDelta + _additionalDelta;
        require((_totalDelta>-(int256)_grossCapital) && (_totalDelta<(int256)_grossCapital), "Hedge capacity used up.");
        require((_newDelta>-(int256)_grossCapital) && (_newDelta<(int256)_grossCapital), "Hedge capacity used up with new option.");
        uint256 _capacityBefore = uint256((_totalDelta -int256(_grossCapital)).min(int256(_grossCapital)-_totalDelta));
        uint256 _capacityAfter = uint256((_newDelta -int256(_grossCapital)).min(int256(_grossCapital)-_newDelta));
        return (MulDiv(_capacityBefore, ethMultiplier, _grossCapital), MulDiv(_capacityAfter, ethMultiplier, _capacityAfter));

    } */


    function calcTotalFee(uint256 _price, uint256 _amount) public view returns(uint256)
    {
        return ((_price * governanceFees / pctDenominator) * _amount / priceMultiplier);
    }

    function addOption(uint256 _tenor, uint256 _strike, PayoffType _poType, uint256 _amount)
    public
    {
        require(tenors.contains(_tenor), "Input option tenor is not allowed.");
        require((_poType==PayoffType.Call) || (_poType==PayoffType.Put), "Use either call or put option.");

        (uint256 _price,) = queryPrice();
        uint256 _volatility = volatilityChain.getVol(_tenor);
        uint256 _premium = calcTotalPremium(_price, _volatility, _strike, _poType, _amount);
        uint256 _fee = calcTotalFee(_price, _amount);

        optionCounter++;
        optionsList[optionCounter] = Option(
            _poType,
            msg.sender,
            OptionStatus.Draft,
            optionCounter,
            block.timestamp,
            0,
            _tenor,
            0,
            _amount,
            _price,
            _strike,
            _volatility,
            _premium,
            _fee);

        emit newOptionCreated(optionsList[optionCounter]);
    }

    function updateOption(uint256 _id) external{
        require(optionsList[_id].holder==msg.sender, "Option is not owned by the buyer.");
        require(optionsList[_id].status==OptionStatus.Draft, "The option is not in a draft status.");

        (uint256 _price,) = queryPrice();
        uint256 _volatility = volatilityChain.getVol(optionsList[_id].tenor);

        optionsList[_id].spot = _price;
        optionsList[_id].volatility = _volatility;
        optionsList[_id].premium = calcTotalPremium(_price, _volatility, optionsList[_id].strike, optionsList[_id].poType, optionsList[_id].amount);
        optionsList[_id].fee = calcTotalFee(_price, optionsList[_id].amount);

        emit newOptionCreated(optionsList[_id]);
    }

    function buyOption(uint256 _id,uint256 _payin) external payable{
        require(optionsList[_id].holder==msg.sender);
        require((optionsList[_id].createTime + BLOCKTIME) <= block.timestamp);
        require(optionsList[_id].status==OptionStatus.Draft);

        require( _payin == (optionsList[_id].premium + optionsList[_id].fee));

        /* require(underlyingToken.increaseAllowance(contractAddr, _payin), "Allowance setup failed."); */
        require(underlyingToken.transferFrom(msg.sender, contractAddr, optionsList[_id].premium), "Premium payment failed.");
        require(underlyingToken.transferFrom(msg.sender, governanceAddr, optionsList[_id].premium), "Premium payment failed.");

        stampActiveOption(_id);

        emit newOptionBought(optionsList[_id]);
    }

    function buyOptionInVolToken(uint256 _id) external payable{
        require(optionsList[_id].holder==msg.sender);
        require((optionsList[_id].createTime + BLOCKTIME) <= block.timestamp);
        require(optionsList[_id].status==OptionStatus.Draft);

        uint256 _feeAmount = (optionsList[_id].fee * priceMultiplier/ optionsList[_id].volatility);
        uint256 _premiumAmount = (optionsList[_id].premium * priceMultiplier / optionsList[_id].volatility);

        /* require(volTokensList[_id].increaseAllowance(contractAddr, _premiumAmount + _feeAmount), "Increase Allowance failed."); */
        require(volTokensList[_id].transferFrom(msg.sender, contractAddr, _premiumAmount));
        require(volTokensList[_id].transferFrom(msg.sender, governanceAddr, _feeAmount));

        stampActiveOption(_id);

        emit newOptionBought(optionsList[_id]);

        volTokensList[optionsList[_id].tenor].recycle(contractAddr, _premiumAmount);
        volTokensList[optionsList[_id].tenor].recycle(governanceAddr, _feeAmount);

        emit volTokenRecycled(_feeAmount+_premiumAmount);
    }

    function stampActiveOption(uint256 _id) internal{
        optionsList[_id].effectiveTime = block.timestamp;
        optionsList[_id].status = OptionStatus.Active;

        if(!addressList.contains(msg.sender))
        {
            addressList.add(msg.sender);
        }

        activeOptionsPerOwner[msg.sender].add(_id);
        activeOptions.add(_id);
    }

    function exerciseOption(uint256 _id) external payable {
        require(optionsList[_id].holder==msg.sender, "Option is not owned by the buyer.");
        require((optionsList[_id].effectiveTime + optionsList[_id].tenor) >= block.timestamp, "Option price has already expired.");
        require(optionsList[_id].status==OptionStatus.Active, "The option is not active.");

        uint256 _payoffValue = getOptionPayoffValue(_id);
        bool _sent = underlyingToken.transfer(msg.sender, _payoffValue);
        require(_sent, "Transfer failed.");

        optionsList[_id].exerciseTime = block.timestamp;
        optionsList[_id].status = OptionStatus.Exercised;

        activeOptionsPerOwner[msg.sender].remove(_id);
        activeOptions.remove(_id);

        emit optionExercised(optionsList[_id]);
    }


    function getOptionPayoffValue(uint256 _id) public view returns(uint256)
    {
        require(optionsList[_id].status == OptionStatus.Active, "Option is not active");
        (uint256 _price,) = queryPrice();
        return (calcIntrinsicValue(optionsList[_id].strike, _price, optionsList[_id].poType) * optionsList[_id].amount / _price);
    }

    function updateHedges(uint256 _deadline) external payable onlyRole(ADMIN_ROLE)
    {
        //uint256 _grossCapital = calculateGrossCapital();
        int256 _targetDelta = calculateTotalDelta();

        //int256 _changesInDeltaUnderM1 = 0; //_targetDelta.min(-int256(_grossCapital)) - hedgePositionAmount.min(-int256(_grossCapital));
        int256 _changesInDeltaM1T0 = 0; //_targetDelta.min(0).max(-int256(_grossCapital)) - hedgePositionAmount.min(0).max(-int256(_grossCapital));
        //int256 _changesInDeltaOver1 = 0;//_targetDelta.max(int256(_grossCapital)) - hedgePositionAmount.max(int256(_grossCapital));

        if(_targetDelta<0){_changesInDeltaM1T0+= _targetDelta;}
        if(hedgePositionAmount<0){_changesInDeltaM1T0-= hedgePositionAmount;}

        // uint256 _newLoanForStable = uint256(-_changesInDeltaUnderM1.min(0));
        // uint256 _repayLoanForStable = uint256(_changesInDeltaUnderM1.max(0));

        // uint256 _newLoanForUnderlying = uint256(_changesInDeltaOver1.max(0));
        // uint256 _repayLoanForUnderlying = uint256(-_changesInDeltaOver1.min(0));

        (uint256 _price, )=queryPrice();
        int _swappedETH = 0;

        if(_changesInDeltaM1T0<0)
        {
            uint256 _newStable = uint256(-_changesInDeltaM1T0);
            uint256[] memory _swappedAmounts = swapIn( _price,  _newStable,  _deadline);

            _swappedETH -= int256(_swappedAmounts[0]);
            emit hedgePositionUpdated(-int256(_swappedAmounts[0]), int256(_swappedAmounts[1]), (_swappedAmounts[1] * ethMultiplier / _newStable));
        }
        if(_changesInDeltaM1T0>0)
        {
            uint256 _unwindStable = uint256(_changesInDeltaM1T0);
            uint256[] memory _swappedAmounts = swapIn( _price,  _unwindStable,  _deadline);

            _swappedETH += int256(_swappedAmounts[1]);
            emit hedgePositionUpdated(int256(_swappedAmounts[1]), -int256(_swappedAmounts[0]), (_swappedAmounts[0] * ethMultiplier/ _unwindStable));
        }

        hedgePositionAmount += _swappedETH;
    }

    function swapIn(uint256 _price, uint256 _newStable, uint256 _deadline) public payable onlyRole(ADMIN_ROLE) returns(uint256[] memory _swappedAmounts)
    {
        uint256 _priceLimit = (_price *(pctDenominator - uniswapSlippageAllowance)/ pctDenominator);
        uint256 _amountOutMinimum = (_newStable * _priceLimit / priceMultiplier);

        address[] memory path = new address[](2);
        path[0] = address(underlyingToken);
        path[1] = address(fundingTokens[mainFundingHash]);

        return uniswapRouter.swapExactTokensForTokens(
          _newStable,
          _amountOutMinimum,
          path,
          contractAddr,
          _deadline
           );
        /* uniswapPayments.refundETH(); */

    }

    function swapOut(uint256 _price, uint256 _unwindStable, uint256 _deadline) public payable onlyRole(ADMIN_ROLE) returns(uint256[] memory _swappedAmounts)
    {
      uint256 _priceLimit = (_price *(pctDenominator + uniswapSlippageAllowance)/ pctDenominator);
      uint256 _amountInMaximum = (_unwindStable* _priceLimit/ priceMultiplier);

      address[] memory path = new address[](2);
      path[0] = address(fundingTokens[mainFundingHash]);
      path[1] = address(underlyingToken);

      return uniswapRouter.swapTokensForExactTokens(
        _unwindStable,
        _amountInMaximum,
        path,
        contractAddr,
        _deadline
         );
      /* uniswapPayments.refundETH(); */

    }


    function getOption(uint256 _id) public view returns(Option memory) {
        return optionsList[_id];
    }


    // This needs to be scheduled the same time as price update.
    function calculateTotalDelta() internal view returns(int256)
    {
      uint256 _totalContracts = activeOptions.length();
      int256 _totalDelta= 0;

      for(uint256 i=0;i<_totalContracts;i++)
      {
          uint256 _id = uint256(activeOptions.at(i));
          if(optionsList[_id].status== OptionStatus.Active)
        {

        _totalDelta += calculateContractDelta(optionsList[_id].strike, optionsList[_id].poType, optionsList[_id].amount);
      }
      }
      return _totalDelta;
    }


    function calculateContractDelta(uint256 _strike, PayoffType  _poType, uint256 _amount) public view returns(int256){
       (uint256 _price, ) = queryPrice();

          uint256 _vol1DAdjusted = (volatilityChain.getVol(86400) * deltaRange / pctDenominator);
          uint256 _lowerRange = _price - (_price* _vol1DAdjusted/ priceMultiplier);
          uint256 _upperRange = _price * 2 - _lowerRange;

        int256 _delta = int256(_amount) / 2;
        if (_poType==PayoffType.Call)
        {
          if(_upperRange < _strike)
          {
            _delta = 0;
          }
          if(_lowerRange > _strike)
          {
            _delta = int256(_amount);
          }
        }

        if(_poType==PayoffType.Put)
        {
            _delta *= -1;
          if(_upperRange < _strike)
          {
            _delta = -int256(_amount);
          }
          if(_lowerRange > _strike)
          {
            _delta = 0;
          }
        }
        return _delta;
    }


    function checkAndExpireOptions() external onlyRole(ADMIN_ROLE){
        for(uint256 k = 0; k< addressList.length(); k++)
        {
            address _holder = addressList.at(k);
            for(uint256 i=0; i<activeOptionsPerOwner[_holder].length(); i++)
            {
                uint256 _id = activeOptionsPerOwner[_holder].at(i);
                if(((optionsList[_id].effectiveTime + optionsList[_id].tenor + BLOCKTIME)< block.timestamp) && optionsList[_id].status==OptionStatus.Active){
                    optionsList[_id].status = OptionStatus.Expired;

                    activeOptions.remove(_id);
                    activeOptionsPerOwner[_holder].remove( _id);
                }
            }
        }
    }


    function getBalance() public view returns (uint) {
        return underlyingToken.balanceOf(contractAddr);
    }

    function addCapital(uint256 _depositAmount) external payable{
        uint256 _averageGrossCapital = calculateAverageGrossCapital();
        uint256 _mintMPTokenAmount = MulDiv(_depositAmount, ethMultiplier, _averageGrossCapital);

        /* require(underlyingToken.increaseAllowance(contractAddr, _depositAmount), "Allowance setup failed."); */
        require(underlyingToken.transferFrom(msg.sender, contractAddr, _depositAmount), "Transfer failed.");

        _mint(msg.sender, _mintMPTokenAmount);

        emit capitalAdded(msg.sender, msg.value, _mintMPTokenAmount);
    }

    function getTotalStableCoinBalances() public view returns(uint256){
        /* uint256 _totalBalances = 0;
        for(uint256 i = 0 ;i < fundingHashList.length(); i++)
        {
            _totalBalances += fundingTokens[fundingHashList.at(i)].balanceOf(contractAddr);
        } */
        return fundingTokens[mainFundingHash].balanceOf(contractAddr);
    }

    function calculateGrossCapital() public view returns(uint256){
        (uint256 _price, ) = queryPrice();
        return underlyingToken.balanceOf(contractAddr) + (getTotalStableCoinBalances() * priceMultiplier / _price);
    }

    function calculateAverageGrossCapital() public view returns(uint256){
        return (calculateGrossCapital() * ethMultiplier / totalSupply());
    }

    function withdrawCapital(uint256 _burnMPTokenAmount) external payable{
        uint256 _averageNetCapital = calculateAverageNetCapital();
        uint256 _withdrawValue = (_averageNetCapital *  _burnMPTokenAmount / ethMultiplier);

        _burn(msg.sender, _burnMPTokenAmount);
        bool _sent = underlyingToken.transfer(msg.sender, _withdrawValue);
        require(_sent, "Withdrawal failed.");

        emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);
    }

    function calculateAverageNetCapital() public view returns(uint256){
        uint256 _grossCapital = calculateGrossCapital();
        uint256 _premiums = calculateLockedPremiums();
        (uint256 _callExposures, uint256 _putExposures ) = calculateOptionExposures();

        uint256 _netCapital = _grossCapital - (_grossCapital <= (_callExposures+ _putExposures)? _grossCapital: (_callExposures+ _putExposures));
        _netCapital = _netCapital - (_netCapital <= _premiums? _netCapital: _premiums)  ;

        return _netCapital;
    }

    function calculateOptionExposures() public view returns(uint256, uint256)
    {
        uint256 _callExposures = 0;
        uint256 _putExposures = 0;
        for(uint256 i=0;i<activeOptions.length();i++)
        {
            uint256 _id = activeOptions.at(i);
            if(optionsList[_id].status==OptionStatus.Active)
            {
                if(optionsList[_id].poType==PayoffType.Call)
                {
                    _callExposures += optionsList[_id].amount;
                }
                if(optionsList[_id].poType==PayoffType.Put)
                {
                    _putExposures += optionsList[_id].amount;//MulDiv(optionsList[_id].amount, optionsList[_id].strike, ethMultiplier);
                }
            }
        }
        return (_callExposures, _putExposures);
    }

    function calculateLockedPremiums() public view returns(uint256)
    {
        uint256 _premiums;
        for(uint256 i=0;i<activeOptions.length();i++)
        {
            uint256 _id = activeOptions.at(i);
            if(optionsList[_id].status==OptionStatus.Active)
            {
                _premiums += optionsList[_id].premium;
            }
        }
        return _premiums;
    }

    function sweepBalance() external payable onlyRole(ADMIN_ROLE){
        uint256 _amount = underlyingToken.balanceOf(contractAddr);

        // 100k gas estimated.
        uint256 _gas = 10 ** (9+5);
        if(_amount > _gas){
          bool _sent = underlyingToken.transfer(msg.sender, _amount - _gas);
          require(_sent, "Withdrawal failed.");

          emit cashSweep(_amount);
        }

    }



        function resetUniswapFee(uint24 _fee) external onlyRole(ADMIN_ROLE){
            require(_fee== 500 || _fee==3000 || _fee==10000, "Entered Uniswap fee is not allowed.");
            uniswapFee = _fee;
            emit newUniswapFees(_fee);
        }

        function resetGovernanceFees(uint256 _fee) external onlyRole(ADMIN_ROLE){
            governanceFees = _fee;
            emit newGovernanceFees(_fee);
        }

        function resetDeltaRange(uint256 _range) external onlyRole(ADMIN_ROLE){
          deltaRange = _range;
          emit newDeltaRange(_range);
        }

    receive() external payable {}

    event newTenor(uint256 _tenor);
    event newVolatilityToken(uint256 _tenor, address _tokenAddress);

    event newOptionCreated(Option _newOption);
    event newOptionBought(Option _newOption);
    event optionExercised(Option _option);
    event volTokenRecycled(uint256 _tokenAmount);
    event cashSweep(uint256 _amount);

    event newGovernanceFees(uint256 _fee);
    event newUniswapFees(uint24 _fee);
    event newDeltaRange(uint256 _range);

    event hedgePositionUpdated(int256 _underlyingAmount, int256 _stableAmount, uint256 _transactedPrice);
    event capitalAdded(address _recipient, uint256 _mintMPTokenAmount, uint256 _addedValue);
    event capitalWithdrawn(address _recipient, uint256 _burnMPTokenAmount, uint256 _withdrawValue);
}
