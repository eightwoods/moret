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
  bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");

  uint256 private constant ethMultiplier = 10 ** 18;

  mapping(address=> EnumerableSet.UintSet) internal activeOptionsPerOwner;
  EnumerableSet.UintSet internal activeOptions;

  IOptionVault internal optionVault;

  uint256 public lockedPremium = 0;
  uint256 public callExposure = 0;
  uint256 public putExposure = 0;
  uint256 public shortPosition = 0;

  uint256 public swapSlp = 2 * 10**16;
  uint256 public lendingPoolRateMode = 1;

  address public lendingPoolAddressProviderAddress;
  address public protocolDataProviderAddress;
  address public swapRouterAddress;
  address public underlyingAddress;
  address public fundingAddress;

  constructor(
      string memory _name,
      string memory _symbol,
      address _underlyingAddress,
      address _fundingAddress,
      address _optionAddress,
      address _swapRouterAddress,
      address _lendingPoolAddressProvider,
      address _protocolDataProviderAddress
      )
      ERC20(_name, _symbol)
      {
          _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
          _setupRole(ADMIN_ROLE, msg.sender);
          _setupRole(EXCHANGE_ROLE, msg.sender);

          swapRouterAddress = _swapRouterAddress;
          lendingPoolAddressProviderAddress = _lendingPoolAddressProvider;
          protocolDataProviderAddress = _protocolDataProviderAddress;

          fundingAddress = _fundingAddress;
          underlyingAddress = _underlyingAddress;
          optionVault = IOptionVault(_optionAddress);

          _mint(msg.sender, ethMultiplier);
      }


      function recordOption(address _purchaser, uint256 _id, bool _isPuchase,
        uint256 _newPremium, uint256 _newCallExposure, uint256 _newPutExposure)
        external  onlyRole(EXCHANGE_ROLE)
      {
        if(_isPuchase)
        {activeOptionsPerOwner[_purchaser].add(_id);
        activeOptions.add(_id);}
        if(!_isPuchase)
        {activeOptionsPerOwner[_purchaser].remove(_id);
        activeOptions.remove(_id);}

        lockedPremium = _isPuchase? (lockedPremium + _newPremium): (lockedPremium - _newPremium);
        callExposure = _isPuchase? (callExposure + _newCallExposure): (callExposure - _newCallExposure);
        putExposure = _isPuchase? (putExposure + _newPutExposure) : (putExposure - _newPutExposure);
      }

    function calcTotalDelta() public view returns(int256)
    {
      int256 _totalDelta= 0;

      for(uint256 i=0;i<activeOptions.length();i++)
      {
        _totalDelta += optionVault.calculateContractDelta(uint256(activeOptions.at(i)));
      }
      return _totalDelta;
    }

    function updateHedges(uint256 _deadline)
    external onlyRole(ADMIN_ROLE)
    {
         int256 _targetDelta = calcTotalDelta();
         (uint256 _price,) = optionVault.queryPrice();

         if(_targetDelta<-int256(shortPosition))
         {
           updateHedgesDownwards( _targetDelta, _price,_deadline);//,  ILendingPoolAddressesProvider(lendingPoolAddressProviderAddress).getLendingPool());
         }
         if(_targetDelta>-int256(shortPosition))
         {
           updateHedgesUpwards( _targetDelta, _price,_deadline);//, ILendingPoolAddressesProvider(lendingPoolAddressProviderAddress).getLendingPool());
         }
    }

    function updateHedgesDownwards(int256 _targetDelta, uint256 _price, uint256 _deadline)
    internal{

      /* uint256 _repayAmount = MarketLibrary.calcRepay(_targetDelta, address(this), protocolDataProviderAddress, underlyingAddress);
      if(_repayAmount>0)
      {
        // repay all borrowing first
        (address _aToken, address _stableDebt, address _variableDebt) = MarketLibrary.getLendingTokenAddresses (protocolDataProviderAddress, underlyingAddress );
        ERC20(lendingPoolRateMode==0? _variableDebt: _stableDebt).approve(_lendingPoolAddress, _repayAmount);
        ERC20(underlyingAddress).approve(_lendingPoolAddress, _repayAmount);
        ILendingPool(_lendingPoolAddress).repay(underlyingAddress, _repayAmount, lendingPoolRateMode, address(this));
        // withdraw collaterals
        ERC20(_aToken).approve(_lendingPoolAddress, MarketLibrary.calcWithdrawCollateral(address(this), protocolDataProviderAddress, underlyingAddress));
        ILendingPool(_lendingPoolAddress).withdraw(underlyingAddress,
          MarketLibrary.calcWithdrawCollateral(address(this), protocolDataProviderAddress, underlyingAddress),
          address(this));
      } */

      // swap to funding
      uint256 _swapToFunding = Math.min(ERC20(underlyingAddress).balanceOf(address(this)),
         uint256(-int256(shortPosition)-_targetDelta));
      if(_swapToFunding>0){
        ERC20(underlyingAddress).increaseAllowance(swapRouterAddress, _swapToFunding);

        address[] memory path = new address[](2);
        path[0] = underlyingAddress;
        path[1] = fundingAddress;
        uint[] memory _swappedAmountsToFunding = IUniswapV2Router02(swapRouterAddress).swapExactTokensForTokens(
          _swapToFunding,
          MulDiv(_swapToFunding, MulDiv(_price , ethMultiplier - swapSlp, ethMultiplier),  optionVault.priceMultiplier() ),
          path,
          address(this),
          _deadline
           );

        // reassign short position
        shortPosition += _swappedAmountsToFunding[0];
      }

      /* return _repayAmount; */
    }

    function updateHedgesUpwards(int256 _targetDelta, uint256 _price, uint256 _deadline)
    internal {
      // swap to underlying
      uint256 _swapFromFunding = Math.min(IERC20(fundingAddress).balanceOf(address(this)),
       MulDiv(Math.min(shortPosition, uint256(_targetDelta + int256(shortPosition))), _price, optionVault.priceMultiplier()));

      if(_swapFromFunding>0){
        ERC20(fundingAddress).increaseAllowance(swapRouterAddress, _swapFromFunding);

        address[] memory path = new address[](2);
        path[0] = fundingAddress;
        path[1]= underlyingAddress;
        uint[] memory _swappedAmountsToUnderlying = IUniswapV2Router02(swapRouterAddress).swapExactTokensForTokens(
          _swapFromFunding,
          MulDiv(_swapFromFunding, optionVault.priceMultiplier() , MulDiv(_price , ethMultiplier + swapSlp, ethMultiplier) ),
          path,
          address(this),
          _deadline
           );

        // reassign short position
        shortPosition -= _swappedAmountsToUnderlying[0];
      }

      /* uint256 _borrowAmount = MarketLibrary.calcBorrow(_targetDelta, address(this), protocolDataProviderAddress, underlyingAddress);
      if(_borrowAmount>0)
      {
        // deposit collaterals
        ERC20(underlyingAddress).approve(_lendingPoolAddress, MarketLibrary.calcDepositCollateral(_borrowAmount, address(this), protocolDataProviderAddress, underlyingAddress));
        ILendingPool(_lendingPoolAddress).deposit(underlyingAddress,
          MarketLibrary.calcDepositCollateral(_borrowAmount, address(this), protocolDataProviderAddress, underlyingAddress),
          address(this), 0);
        // borrow
        ILendingPool(_lendingPoolAddress).borrow(underlyingAddress, _borrowAmount, lendingPoolRateMode,  0, address(this));
      }

      return _borrowAmount; */
    }

    function addCapital(uint256 _depositAmount) external {
        uint256 _averageGrossCapital = calcCapital(false, true);
        require(_averageGrossCapital>0);

        uint256 _mintMPTokenAmount = MulDiv(_depositAmount, ethMultiplier, _averageGrossCapital);

        require(ERC20(underlyingAddress).transferFrom(msg.sender, address(this), _depositAmount));

        _mint(msg.sender, _mintMPTokenAmount);

        emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);
    }


    function withdrawCapital(uint256 _burnMPTokenAmount) external {
        uint256 _withdrawValue = MulDiv(calcCapital(true, true),  _burnMPTokenAmount , ethMultiplier);

        _burn(msg.sender, _burnMPTokenAmount);

        require(ERC20(underlyingAddress).transfer(msg.sender, _withdrawValue));

        emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);
    }

    function calcCapital(bool _net, bool _average) public view returns(uint256){
        (uint256 _price,) = optionVault.queryPrice();
        uint256 _capital = MulDiv(IERC20(fundingAddress).balanceOf(address(this)), optionVault.priceMultiplier() , _price ) + ERC20(underlyingAddress).balanceOf(address(this)) ;

        if(_net)
        {
          _capital -= (_capital <= (callExposure+ putExposure + lockedPremium)? _capital: (callExposure+ putExposure + lockedPremium));
        }

        if(_average)
        {
          _capital = MulDiv(_capital , ethMultiplier , totalSupply());
        }
        return _capital;
    }

    function resetSwapSlippageAllowance(uint256 _multiplier) external onlyRole(ADMIN_ROLE){
        swapSlp = _multiplier;
    }

    function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
    function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionVault.getOption(activeOptionsPerOwner[_address].at(_index));}

    function getLendingTokenAddresses()
    external view returns (address, address, address){return MarketLibrary.getLendingTokenAddresses(protocolDataProviderAddress,underlyingAddress);}

}
