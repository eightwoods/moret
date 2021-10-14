// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MoretInterfaces.sol";
import "./MarketInterfaces.sol";
import "./FullMath.sol";
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

  uint256 public updateInterval = 1800;

  uint256 public exchangeSlippageUp = 0;
  uint256 public exchangeSlippageDown = 0;
  uint256 public loanInterest = 0;

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

    function recordOption(address _purchaser, uint256 _id, bool _isNew)
      external  onlyRole(EXCHANGE_ROLE)
    {
      if(_isNew)
      {
        activeOptionsPerOwner[_purchaser].add(_id);
        activeOptions.add(_id);
      }

      if(!_isNew)
      {
        activeOptionsPerOwner[_purchaser].remove(_id);
        activeOptions.remove(_id);
      }
    }

    function getAggregateGamma(bool _ignoreSells) public view returns(int256 _gamma){
      (_price,) = optionVault.queryPrice();
      _gamma= 0;
      for(uint256 i=0;i<activeOptions.length();i++){
        _gamma += optionVault.calculateContractGamma(uint256(activeOptions.at(i)),_price, _ignoreSells);}}

    function getAggregateDelta(bool _ignoreSells, bool _adjustForSkew) public view returns(int256 _delta){
      (_price,) = optionVault.queryPrice();
      _delta= 0;
      for(uint256 i=0;i<activeOptions.length();i++){
        _greek += optionVault.calculateContractDelta(uint256(activeOptions.at(i)),_price, _ignoreSells, _adjustForSkew);}}}

    function getAggregateNotional(bool _ignoreSells) internal view returns(uint256 _notional) {
      _notional= 0;
      for(uint256 i=0;i<activeOptions.length();i++){
        _notional += optionVault.queryOptionNotional(uint256(activeOptions.at(i)), _ignoreSells);} }

    function getBalances() public view returns(uint256 _underlyingBalance, uint256 _fundingBalance, uint256 _collateralBalance, uint256 _debtBalance){
      ( _underlyingBalance, ,  _debtBalance) = MarketLibrary.getTokenBalances(address(this), protocolDataProviderAddress, underlyingAddress);
      ( _fundingBalance,  _collateralBalance,) = MarketLibrary.getTokenBalances(address(this), protocolDataProviderAddress, fundingAddress);    }

    function swapToUnderlying(uint256 _swapAmount, uint256 _maxCost, uint256 _deadline) external onlyRole(ADMIN_ROLE)
    {
      ERC20(fundingAddress).increaseAllowance(swapRouterAddress, _maxCost);

      address[] memory path = new address[](2);
      path[0] = fundingAddress;
      path[1]= underlyingAddress;

      //uint[] memory _swapped = I
      IUniswapV2Router02(swapRouterAddress).swapTokensForExactTokens(_swapAmount, _maxCost, path, address(this), _deadline);
    }

    function swapToFunding(uint256 _swapAmount, uint256 _minReturn, uint256 _deadline) external onlyRole(ADMIN_ROLE)
    {
      ERC20(underlyingAddress).increaseAllowance(swapRouterAddress, _swapAmount);

      address[] memory path = new address[](2);
      path[0] = underlyingAddress;
      path[1] = fundingAddress;

      //uint[] memory _swapped = 
      IUniswapV2Router02(swapRouterAddress).swapExactTokensForTokens(_swapAmount, _minReturn, path, address(this), _deadline);
    }

    function borrowHedge(uint256 _borrowAmount, uint256 _collateralAdjust, 
    address _lendingPoolAddress, 
    uint256 _lendingPoolRateMode) 
    external onlyRole(ADMIN_ROLE)
    {
      // deposit collaterals
      ERC20(underlyingAddress).approve(_lendingPoolAddress, _collateralAdjust);
      ILendingPool(_lendingPoolAddress).deposit(underlyingAddress,_collateralAdjust, address(this), 0);
      // borrow
      ILendingPool(_lendingPoolAddress).borrow(underlyingAddress, _borrowAmount, _lendingPoolRateMode,  0, address(this));
    }

    function repayHedge(uint256 _repayAmount, uint256 _collateralAdjust, 
    address _lendingPoolAddress, address _aToken, address _debtToken, 
    uint256 _lendingPoolRateMode) 
    external onlyRole(ADMIN_ROLE)
    {
      // repay all borrowing first
      ERC20(_debtToken).approve(_lendingPoolAddress, _repayAmount);
      ERC20(underlyingAddress).approve(_lendingPoolAddress, _repayAmount);
      ILendingPool(_lendingPoolAddress).repay(underlyingAddress, _repayAmount, _lendingPoolRateMode, address(this));
      // withdraw collaterals
      ERC20(_aToken).approve(_lendingPoolAddress, _collateralAdjust);
      ILendingPool(_lendingPoolAddress).withdraw(underlyingAddress, _collateralAdjust, address(this));
    }

    function addCapital(uint256 _depositAmount) external {
        uint256 _averageGrossCapital = calcCapital(false, true);
        require(_averageGrossCapital>0);

        uint256 _mintMPTokenAmount = MulDiv(_depositAmount, ethMultiplier, _averageGrossCapital);

        require(ERC20(fundingAddress).transferFrom(msg.sender, address(this), _depositAmount));

        _mint(msg.sender, _mintMPTokenAmount);

        emit capitalAdded(msg.sender, _depositAmount, _mintMPTokenAmount);
    }


    function withdrawCapital(uint256 _burnMPTokenAmount) external {
        uint256 _withdrawValue = MulDiv(calcCapital(true, true),  _burnMPTokenAmount , ethMultiplier);

        _burn(msg.sender, _burnMPTokenAmount);

        require(ERC20(fundingAddress).transfer(msg.sender, _withdrawValue));

        emit capitalWithdrawn(msg.sender, _burnMPTokenAmount, _withdrawValue);
    }

    function calcCapital(bool _net, bool _average) public view returns(uint256 _capital){
        (uint256 _price,) = optionVault.queryPrice();
        (uint256 _underlying_balance, uint256 _funding_balance, uint256 _collateral_balance, uint256 _debt_balance) = getBalances();
        
        _capital = _funding_balance + _collateral_balance + MulDiv(_underlying_balance, _price, optionVault.priceMultiplier()) - MulDiv(_debt_balance, _price, optionVault.priceMultiplier()) ;

        if(_net){ uint256 _totalNotional = getAggregateNotional(false);
          _capital -= Math.min(_totalNotional, _capital);}

        if(_average){ _capital = MulDiv(_capital , ethMultiplier , totalSupply()); }}
    


    function resetVolatilityRiskPremiumConstant(uint256 _newConstant) external onlyRole(ADMIN_ROLE){ volatilityRiskPremiumConstant=_newConstant;}
    function resetVolatilitySkewConstant(uint256 _newConstant) external onlyRole(ADMIN_ROLE){ volatilitySkewConstant=_newConstant;}

    // function resetUpdateInterval(uint256 _newUpdateInterval) external onlyRole(ADMIN_ROLE){ updateInterval=_newUpdateInterval;}

    function payExchange(uint256 _payment, address _exchangeAddress) public onlyRole(EXCHANGE_ROLE){
      require(ERC20(underlyingAddress).transfer(_exchangeAddress, _payment));
    }

    function getPriceMultiplier() external view returns(uint256) {return optionVault.priceMultiplier();}
    function getHoldersOptionCount(address _address) external view returns(uint256){return activeOptionsPerOwner[_address].length();}
    function getHoldersOption(uint256 _index, address _address) external view returns(OptionLibrary.Option memory) {return optionVault.getOption(activeOptionsPerOwner[_address].at(_index));}

}
