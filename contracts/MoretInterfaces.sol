/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "./OptionLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface EOption{
    event newOptionBought(address indexed _purchaser, OptionLibrary.Option _option, uint256 _cost, bool _inVol);
    event optionExercised(address indexed _purchaser, OptionLibrary.Option _option, uint256 _payoff);
    event capitalAdded(address _recipient, uint256 _mintMPTokenAmount, uint256 _addedValue);
    event capitalWithdrawn(address _recipient, uint256 _burnMPTokenAmount, uint256 _withdrawValue);
    event newVolatilityTokenBought(address _purchaser, uint256 _time, uint256 _tenor, uint256 _amount);}

interface IVolatilityChain{
    event volatilityChainBlockAdded(uint256 indexed _tenor, uint256 _timeStamp, PriceStamp _book);
    struct PriceStamp{ uint256 startTime; uint256 endTime; uint256 open; uint256 highest; uint256 lowest; uint256 close; uint256 volatility; uint256 accentus; }

    // w: weights to long-term average; p: weights to moving average; q: weights for auto regression
    struct VolParam{ uint256 initialVol; uint256 ltVol; uint256 ltVolWeighted; uint256 w; uint256 p; uint256 q; }

    function getVol(uint256 _tenor) external view returns(uint256);
    function queryPrice() external view returns(uint256, uint256, uint256);
    function getPriceDecimals() external view returns (uint256);
    function getPriceMultiplier() external view returns (uint256);
    function getDecription() external view returns (string memory);}

interface IOptionVault{
    function queryOptionCost(uint256 _tenor, uint256 _strike,uint256 _amount, uint256 _vol, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side) external view returns(uint256 _premium, uint256 _cost);
    function addOption(uint256 _tenor, uint256 _strike, uint256 _amount, OptionLibrary.PayoffType _poType, OptionLibrary.OptionSide _side, uint256 _premium, uint256 _cost, uint256 _price, uint256 _volatility) external  returns(uint256 _id);
    function getOptionHolder(uint256 _id) external view returns(address) ;
    function queryOptionPremium(uint256 _id) external view returns(uint256) ;
    function queryOptionNotional(uint256 _id, bool _ignoreSells) external view returns(uint256 _notional);
    function queryOptionExposure(uint256 _id, OptionLibrary.PayoffType _poType) external view returns(uint256 _exposure);
    function getContractPayoff(uint256 _id) external view returns(uint256 _payoff, uint256 _payback);
    function calculateContractDelta(uint256 _id, uint256 _price, uint256 _priceMultiplier, bool _ignoreSells) external view returns(int256);
    function calculateContractGamma(uint256 _id, uint256 _price, uint256 _priceMultiplier, bool _ignoreSells) external view returns(int256);
    function calculateSpotGamma() external view returns(int256 _gamma);
    function isOptionExpiring(uint256 _id) external view returns (bool);
    function stampActiveOption(uint256 _id) external ;
    function stampExpiredOption(uint256 _id) external;
    function getOption(uint256 _id) external view returns(OptionLibrary.Option memory);
    function queryVol(uint256 _tenor) external view returns(uint256);
    function queryPrice() external view returns(uint256, uint256, uint256);
    function priceMultiplier() external view returns (uint256);
    function priceDecimals() external view returns(uint256); }

interface IUniswapV2Router02 {
  function swapExactTokensForTokens( uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline ) external returns (uint[] memory amounts);
  function swapTokensForExactTokens( uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline ) external returns (uint[] memory amounts);
  function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
  function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
  function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
  function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts); }

interface I1InchProtocol{
    function getExpectedReturn( IERC20 fromToken, IERC20 destToken, uint256 amount, uint256 parts, uint256 flags) external view returns( uint256 returnAmount, uint256[] memory distribution);
    function getExpectedReturnWithGas(IERC20 fromToken,IERC20 destToken,uint256 amount,uint256 parts,uint256 flags,uint256 destTokenEthPriceTimesGasPrice) external view returns(uint256 returnAmount, uint256 estimateGasAmount, uint256[] memory  distribution);
    function getExpectedReturnWithGasMulti( IERC20[] memory tokens, uint256 amount, uint256[] memory parts, uint256[] memory flags, uint256[] memory destTokenEthPriceTimesGasPrices ) external view returns( uint256[] memory returnAmounts, uint256 estimateGasAmount,  uint256[] memory distribution );
    function swap( IERC20 fromToken, IERC20 destToken, uint256 amount, uint256 minReturn, uint256[] memory distribution, uint256 flags ) external payable returns(uint256);
    function swapMulti( IERC20[] memory tokens, uint256 amount, uint256 minReturn, uint256[] memory distribution, uint256[] memory flags ) external payable returns(uint256);
    function makeGasDiscount( uint256 gasSpent, uint256 returnAmount, bytes calldata msgSenderCalldata ) external;}

interface IProtocolDataProvider {
  function getReserveConfigurationData(address asset) external view returns (uint256 decimals, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor, bool usageAsCollateralEnabled, bool borrowingEnabled, bool stableBorrowRateEnabled, bool isActive, bool isFrozen);
  function getReserveTokensAddresses(address asset) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress);}

interface ILendingPoolAddressesProvider {
  function getAddress(bytes32 id) external view returns (address);
  function getLendingPool() external view returns (address);}

interface ILendingPool {
  function deposit( address asset, uint256 amount, address onBehalfOf, uint16 referralCode ) external;
  function withdraw( address asset, uint256 amount, address to ) external returns (uint256);
  function borrow( address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf ) external;
  function repay( address asset, uint256 amount, uint256 rateMode, address onBehalfOf ) external returns (uint256); }
