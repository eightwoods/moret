/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MoretInterfaces.sol";
import "./MarketLibrary.sol";

contract MoretMarketMaker is ERC20, AccessControl, EOption
{
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  uint256 private constant ethMultiplier = 10 ** 18;

  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;

  IUniswapV2Router02 internal uniswapRouter;
  address internal lendingPoolAddressProvider;
  ERC20 internal underlyingToken;

  IOptionVault internal optionVault;

  uint256 public lockedPremium = 0;
  uint256 public callExposure = 0;
  uint256 public putExposure = 0;
  uint256 public shortPosition = 0;

  uint256 public swapSlp = 2 * 10**16;
  uint256 public lendingPoolRateMode = 1;

  address public underlyingAddress;
  address public fundingAddress;

  constructor(
      string memory _name,
      string memory _symbol,
      address _underlyingAddress,
      address _fundingAddress,
      address _optionAddress,
      address _swapRouterAddress,
      address _lendingPoolAddressProvider
      )
      ERC20(_name, _symbol)
      {
          _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
          _setupRole(ADMIN_ROLE, msg.sender);

          uniswapRouter = IUniswapV2Router02(_swapRouterAddress);
          lendingPoolAddressProvider = _lendingPoolAddressProvider;

          fundingAddress = _fundingAddress;
          underlyingAddress = _underlyingAddress;
          underlyingToken = ERC20(underlyingAddress);
          optionVault = IOptionVault(_optionAddress);

          _mint(msg.sender, ethMultiplier);
      }


      function recordOptionPurhcase(address _purchaser, uint256 _id,
        uint256 _newPremium, uint256 _newCallExposure, uint256 _newPutExposure)
        external
      {
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

    function updateHedges(uint256 _deadline) external payable onlyRole(ADMIN_ROLE)
    {
         int256 _targetDelta = calcTotalDelta();
         uint256 _newShortPosition = shortPosition;
         (uint256 _price,) = optionVault.queryPrice();

         if(_targetDelta<-int256(shortPosition))
         {
           // repay all borrowing first
           adjustBorrowing(_targetDelta);
           // swap to funding
           uint256 _swapToFunding = Math.min(underlyingToken.balanceOf(address(this)), uint256(-int256(shortPosition)-_targetDelta));
           if(_swapToFunding>0){
             uint[] memory _swappedAmountsToFunding = swapToken(_swapToFunding,
               MulDiv(_swapToFunding, MulDiv(_price , ethMultiplier - swapSlp, ethMultiplier),  optionVault.priceMultiplier() ),
               underlyingAddress,
               fundingAddress,
                _deadline);
             _newShortPosition += _swappedAmountsToFunding[0];
           }
         }
         if(_targetDelta>-int256(shortPosition))
         {
           // swap to underlying
           uint256 _currentFunding = IERC20(fundingAddress).balanceOf(address(this));
           uint256 _swapFunding = MulDiv(_currentFunding, Math.min(shortPosition, uint256(_targetDelta+int256(shortPosition))), shortPosition);

           if(_swapFunding>0){
             uint[] memory _swappedAmountsToUnderlying = swapToken(_swapFunding,
               MulDiv(_swapFunding, optionVault.priceMultiplier() , MulDiv(_price , ethMultiplier + swapSlp, ethMultiplier) ),
               fundingAddress,
               underlyingAddress,
                _deadline);
             _newShortPosition -= MulDiv(shortPosition, _swappedAmountsToUnderlying[0], _currentFunding);
           }
           // borrow
           adjustBorrowing(_targetDelta);
         }

         shortPosition = _newShortPosition;
    }

    function adjustBorrowing(int256 _targetDelta) internal onlyRole(ADMIN_ROLE){
      int256 _repayOrBorrow = MarketLibrary.calcRepayOrBorrow(_targetDelta, address(this), lendingPoolAddressProvider, underlyingAddress);
      address _lendingPoolAddress = ILendingPoolAddressesProvider(lendingPoolAddressProvider).getLendingPool();

      if(_repayOrBorrow < 0) // repay
      {
          ILendingPool(_lendingPoolAddress).repay(underlyingAddress, uint256(-_repayOrBorrow), lendingPoolRateMode, address(this));
          ILendingPool(_lendingPoolAddress).withdraw(underlyingAddress,
            MarketLibrary.calcWithdrawCollateral(address(this), lendingPoolAddressProvider, underlyingAddress),
            address(this));
      }
      if(_repayOrBorrow > 0) // borrow
      {
          ILendingPool(_lendingPoolAddress).deposit(underlyingAddress,
            MarketLibrary.calcDepositCollateral(uint256(_repayOrBorrow), address(this), lendingPoolAddressProvider, underlyingAddress),
            address(this), 0);
          ILendingPool(_lendingPoolAddress).borrow(underlyingAddress, uint256(_repayOrBorrow), lendingPoolRateMode,  0, address(this));
      }
    }

    function swapToken(uint256 _amountIn, uint256 _amountOutMinimum, address _tokenIn, address _tokenOut,  uint256 _deadline)
    internal onlyRole(ADMIN_ROLE) returns(uint256[] memory _swappedAmounts)
    {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        return uniswapRouter.swapExactTokensForTokens(
          _amountIn,
          _amountOutMinimum,
          path,
          address(this),
          _deadline
           );
    }

    function addCapital(uint256 _depositAmount) external payable{
        uint256 _averageGrossCapital = calcCapital(false, true);
        require(_averageGrossCapital>0);

        uint256 _mintMPTokenAmount = MulDiv(_depositAmount, ethMultiplier, _averageGrossCapital);

        require(underlyingToken.transferFrom(msg.sender, address(this), _depositAmount));

        _mint(msg.sender, _mintMPTokenAmount);

        emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);
    }


    function withdrawCapital(uint256 _burnMPTokenAmount) external {
        uint256 _withdrawValue = MulDiv(calcCapital(true, true),  _burnMPTokenAmount , ethMultiplier);

        _burn(msg.sender, _burnMPTokenAmount);

        require(underlyingToken.transfer(msg.sender, _withdrawValue));

        emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);
    }

    function calcCapital(bool _net, bool _average) public view returns(uint256){
        (uint256 _price,) = optionVault.queryPrice();
        uint256 _capital = MulDiv(IERC20(fundingAddress).balanceOf(address(this)), optionVault.priceMultiplier() , _price ) + underlyingToken.balanceOf(address(this)) ;

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

    function resetSwapSlippageAllowance(uint256 _multiplier) external onlyRole(ADMIN_ROLE){
        swapSlp = _multiplier;
    }

    function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
    function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionVault.getOption(activeOptionsPerOwner[_address].at(_index));}

    receive() external payable{}

}
