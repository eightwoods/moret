/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "./MoretInterfaces.sol";
import "./FullMath.sol";

contract MarketMakerNative is ERC20, AccessControl, EOption
{
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  uint256 private constant ethMultiplier = 10 ** 18;

  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;
  EnumerableSet.AddressSet holderList;

  IUniswapV2Router02 internal uniswapRouter;
  IOptionVault internal optionVault;

  uint256 public lockedPremium = 0;
  uint256 public callExposure = 0;
  uint256 public putExposure = 0;
  int256 public hedgePositionAmount = 0;

  /* OptionLibrary.Percent public maxCollateralisation = OptionLibrary.Percent(10 * 10 ** 5, 10 ** 6);
  OptionLibrary.Percent public volPremiumMultiplier = OptionLibrary.Percent(10 ** 5 , 10 ** 6) ;
  OptionLibrary.Percent public volPremiumPenalty = OptionLibrary.Percent(5 * 10 ** 5, 10 ** 6) ; */
  OptionLibrary.Percent public swapSlippageAllowance = OptionLibrary.Percent (2 * 10**4, 10**6);

  /* address internal constant UNISWAP_ROUTER_ADDRESS = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
  address internal constant PRICING_ADDRESS = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
  address internal constant FUNDING_ADDRESS = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; */
  address public WETH;
  address public stableCoinAddress;

  constructor(
      string memory _name,
      string memory _symbol,
      address _wethAddress,
      address _fundingAddress,
      address _optionAddress,
      address _swapRouterAddress
      ) payable
      ERC20(_name, _symbol)
      {
          _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
          _setupRole(ADMIN_ROLE, msg.sender);

          uniswapRouter = IUniswapV2Router02(_swapRouterAddress);
          optionVault = IOptionVault(_optionAddress);

          stableCoinAddress = _fundingAddress;
          WETH = _wethAddress;//uniswapRouter.WETH();

          _mint(msg.sender, ethMultiplier);
      }


      function recordOptionPurhcase(address _purchaser, uint256 _id,
        uint256 _newPremium, uint256 _newCallExposure, uint256 _newPutExposure)
        external
      {
        if(!holderList.contains(_purchaser))
        {
            holderList.add(_purchaser);
        }

        activeOptionsPerOwner[_purchaser].add(_id);
        activeOptions.add(_id);
        lockedPremium += _newPremium;
        callExposure += _newCallExposure;
        putExposure += _newPutExposure;
      }

      function recordOptionRemoval(address _purchaser, uint256 _id,
        uint256 _removePremium, uint256 _removeCallExposure, uint256 _removePutExposure)
        external
      {
        activeOptionsPerOwner[_purchaser].remove(_id);
        activeOptions.remove(_id);

        lockedPremium -= _removePremium;
        callExposure -= _removeCallExposure;
        putExposure -= _removePutExposure;
      }

    function calcTotalDelta() public view returns(int256)
    {
      uint256 _totalContracts = activeOptions.length();
      int256 _totalDelta= 0;

      for(uint256 i=0;i<_totalContracts;i++)
      {
          uint256 _id = uint256(activeOptions.at(i));

        _totalDelta += optionVault.calculateContractDelta(_id);
      }
      return _totalDelta;
    }

    function updateHedges(uint256 _deadline) external onlyRole(ADMIN_ROLE)
    {
        int256 _targetDelta = calcTotalDelta();
        int256 _changesInDelta_m1_0 = 0;

        if(_targetDelta<0){_changesInDelta_m1_0+= _targetDelta;}
        if(hedgePositionAmount<0){_changesInDelta_m1_0-= hedgePositionAmount;}

        int _swappedUnderlying = 0;

        if(_changesInDelta_m1_0<0)
        {
            uint256 _newStable = uint256(-_changesInDelta_m1_0);
            uint256[] memory _swappedAmounts = swapToStable(_newStable,  _deadline);
            _swappedUnderlying -= int256(_swappedAmounts[0]);
        }
        if(_changesInDelta_m1_0>0)
        {
            uint256 _unwindStable = uint256(_changesInDelta_m1_0);
            uint256[] memory _swappedAmounts = swapToUnderlying( _unwindStable,  _deadline);
            _swappedUnderlying += int256(_swappedAmounts[1]);
        }

        hedgePositionAmount += _swappedUnderlying;
    }

    function swapToStable(uint256 _newStable, uint256 _deadline) public onlyRole(ADMIN_ROLE) returns(uint256[] memory _swappedAmounts)
    {
        (uint256 _price,) = optionVault.queryPrice();
        uint256 _priceLimit = _price * (swapSlippageAllowance.denominator + swapSlippageAllowance.numerator)/ swapSlippageAllowance.denominator;
        uint256 _amountInMaximum = (_newStable * optionVault.priceMultiplier() / _priceLimit );

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(stableCoinAddress);

        return uniswapRouter.swapETHForExactTokens{value: _amountInMaximum}(_newStable, path, payable(address(this)), _deadline);
    }

    function swapToUnderlying(uint256 _unwindStable, uint256 _deadline) public onlyRole(ADMIN_ROLE) returns(uint256[] memory _swappedAmounts)
    {
      (uint256 _price,) = optionVault.queryPrice();
      uint256 _priceLimit = _price *(swapSlippageAllowance.denominator + swapSlippageAllowance.numerator)/ swapSlippageAllowance.denominator;
      uint256 _amountOutMinimum = (_unwindStable * optionVault.priceMultiplier() / _priceLimit);

      address[] memory path = new address[](2);
      path[0] = address(stableCoinAddress);
      path[1] = address(WETH);

      return uniswapRouter.swapExactTokensForETH(_unwindStable, _amountOutMinimum, path, payable(address(this)), _deadline);
    }

    function quoteCapitalCost(uint256 _mpAmount) external view returns(uint256){
        return MulDiv(_mpAmount, calcCapital(false, true), ethMultiplier);
    }

    function addCapital(uint256 _depositAmount) external payable{
        uint256 _averageGrossCapital = calcCapital(false, true);
        require(_averageGrossCapital>0, "Zero Gross Capital.");

        uint256 _mintMPTokenAmount = MulDiv(_depositAmount, ethMultiplier, _averageGrossCapital);
        require(msg.value>=_depositAmount);

        _mint(msg.sender, _mintMPTokenAmount);
        emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);
    }

    function withdrawCapital(uint256 _burnMPTokenAmount) external {
        uint256 _withdrawValue = MulDiv(calcCapital(true, true) ,  _burnMPTokenAmount , ethMultiplier);

        _burn(msg.sender, _burnMPTokenAmount);
        payable(msg.sender).transfer(_withdrawValue);

        emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);
    }

    function calcCapital(bool _net, bool _average) public view returns(uint256){
        (uint256 _price,) = optionVault.queryPrice();
        uint256 _capital = ERC20(stableCoinAddress).balanceOf(payable(address(this))) * optionVault.priceMultiplier() / _price;
        _capital += payable(address(this)).balance ;

        if(_net)
        {
          _capital -= (_capital <= (callExposure+ putExposure)? _capital: (callExposure+ putExposure));
          _capital -= (_capital <= lockedPremium? _capital: lockedPremium)  ;
        }

        if(_average)
        {
          _capital = _capital * ethMultiplier / totalSupply();
        }
        return _capital;
    }

    function calcUtilisation(uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side)
    external view returns(uint256, uint256){
        uint256 _grossCapital = calcCapital(false, false);

        uint256 _newCallExposure = (_poType==OptionLibrary.PayoffType.Call)?
          ((_side==OptionLibrary.OptionSide.Buy)? (callExposure+_amount): (callExposure - Math.min(callExposure, _amount)) )
          : callExposure;
        uint256 _newPutExposure = (_poType==OptionLibrary.PayoffType.Put)?
          ((_side==OptionLibrary.OptionSide.Buy)? (putExposure+_amount): (putExposure - Math.min(putExposure, _amount)) )
          : putExposure;

        return (MulDiv(Math.max(callExposure, putExposure), ethMultiplier, _grossCapital ),
          MulDiv(Math.max(_newCallExposure, _newPutExposure) , ethMultiplier, _grossCapital ));
    }
/*
    function calcUtilityAddon(uint256 _amount, OptionLibrary.PayoffType  _poType) external view returns(OptionLibrary.Percent memory){
        (uint256 _utilityBefore, uint256 _utilityAfter, uint256 _denominator) = calcUtilityRatios(_amount, _poType);
        require(_utilityBefore < maxCollateralisation.numerator, "Max collateralisation breached.");
        require(_utilityAfter < maxCollateralisation.numerator, "Max collateralisation breached.");

        uint256 _addonBefore = volPremiumMultiplier.numerator * _utilityBefore / volPremiumMultiplier.denominator;
        if(_utilityBefore> _denominator)
        {
            _addonBefore += volPremiumPenalty.numerator *( _utilityBefore - _denominator)/ volPremiumPenalty.denominator;
        }

        uint256 _addonAfter = (volPremiumMultiplier.numerator * _utilityAfter/ volPremiumMultiplier.denominator);
        if(_utilityAfter> _denominator)
        {
            _addonAfter += (volPremiumPenalty.numerator* ( _utilityAfter - _denominator) / volPremiumPenalty.denominator);
        }

        return OptionLibrary.Percent((_addonBefore + _addonAfter) / 2, _denominator);
    } */

    function sweepBalance() external onlyRole(ADMIN_ROLE){
        payable(msg.sender).transfer(payable(address(this)).balance);
    }

    /* function resetMaxCollateralisation(uint256 _multiplier, uint256 _denominator) external onlyRole(ADMIN_ROLE){
        maxCollateralisation = OptionLibrary.Percent(_multiplier, _denominator);
    }

    function resetVolPremiumMultiplier(uint256 _multiplier, uint256 _denominator) external onlyRole(ADMIN_ROLE){
        volPremiumMultiplier = OptionLibrary.Percent(_multiplier, _denominator);
    }

    function resetVolPremiumPenalty(uint256 _multiplier, uint256 _denominator) external onlyRole(ADMIN_ROLE){
        volPremiumPenalty = OptionLibrary.Percent(_multiplier, _denominator);
    } */

    function resetSwapSlippageAllowance(uint256 _multiplier, uint256 _denominator) external onlyRole(ADMIN_ROLE){
        swapSlippageAllowance = OptionLibrary.Percent(_multiplier, _denominator);
    }

    /* function getHolderCount() external view returns(uint256){return holderList.length();}
    function getHolderAddress(uint256 _index) external view returns(address) {return holderList.at(_index);} */
    function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
    function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionVault.getOption(activeOptionsPerOwner[_address].at(_index));}
    /* function getOptionPayoff(uint256 _id) external view returns(uint256){return optionVault.getOptionPayoffValue(_id);} */
    function priceDecimals() external view returns(uint256){ return optionVault.priceDecimals();}

    receive() external payable{}

}
