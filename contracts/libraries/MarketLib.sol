// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IProtocolDataProvider.sol";
import "../interfaces/ILendingPoolAddressesProvider.sol";
import "../pools/Pool.sol";
import "../pools/MarketMaker.sol";
import "./MathLib.sol";

library MarketLib {
  using MathLib for uint256;
  using SignedMath for int256;
  uint256 public constant LTV_DECIMALS = 4;
  uint256 public constant DECIMALS = 18;
  uint256 internal constant BASE  = 1e18;

  // Returns balances of ERC20 token (as for _tokenAddress), its corresponding aToken (i.e. collaterals posted), and its debt tokens (including both variable and fixed loans)
  function getTokenBalances(address _contractAddress, IProtocolDataProvider _protocolDataProvider, ERC20 _token) external view returns(uint256, uint256, uint256) {
    (address _aToken, address _stableLoan, address _variableLoan) = _protocolDataProvider.getReserveTokensAddresses(address(_token));
    return (balanceDef(_token, _contractAddress), balanceDef(ERC20(_aToken), _contractAddress),balanceDef(ERC20(_stableLoan), _contractAddress) + balanceDef(ERC20(_variableLoan), _contractAddress)); }

  function getLTV(IProtocolDataProvider _protocolDataProvider, address _tokenAddress) public view returns (uint256) {
    (, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);
    return toWei(_ltv, LTV_DECIMALS); } 
    
  function getLoanTrade(address _contractAddress, IProtocolDataProvider _protocolDataProvider, int256 _aggregateDelta, ERC20 _underlying, bool _useVariableRate) external view returns(int256 _loanChange, uint256 _targetLoan, address _loanAddress){
    ( , address _stableLoanAddress,  address _variableLoanAddress) = _protocolDataProvider.getReserveTokensAddresses(address(_underlying));
    _loanAddress = _useVariableRate? _variableLoanAddress: _stableLoanAddress;
    uint256 _debtBalance = balanceDef(ERC20(_loanAddress), _contractAddress);
    _targetLoan = _aggregateDelta >=0 ? 0: uint256(-_aggregateDelta);
    _loanChange = SafeCast.toInt256(_targetLoan) - SafeCast.toInt256(_debtBalance);}
  
  function getCollateralTrade(address _contractAddress, IProtocolDataProvider _protocolDataProvider, uint256 _targetLoan, uint256 _price, ERC20 _funding, ERC20 _underlying, uint256 _overCollateral) external view returns(int256 _collateralChange, address _collateralAddress) {
    (_collateralAddress, , ) = _protocolDataProvider.getReserveTokensAddresses(address(_funding));
    uint256 _ltv = getLTV(_protocolDataProvider, address(_underlying));
    uint256 _collateralBalance = balanceDef(ERC20(_collateralAddress), _contractAddress);
    uint256 _requiredCollateral = _targetLoan.muldiv(_price , _ltv).accrue(_overCollateral);
    uint256 _fundingBalance = balanceDef(_funding, _contractAddress);
    require(_requiredCollateral<= (_fundingBalance + _collateralBalance), "Insufficient collateral;");
    _collateralChange =  SafeCast.toInt256(_requiredCollateral) - SafeCast.toInt256(_collateralBalance);}

  function balanceDef(ERC20 _token, address _accountAddress) public view returns(uint256){
    return toWei(_token.balanceOf(_accountAddress), _token.decimals());}

  function toWei(uint256 _rawData, uint256 _rawDataDecimals) public pure returns(uint256 _data){
    _data = _rawData;
    if(DECIMALS > _rawDataDecimals){
      _data = _rawData * (10** (DECIMALS - _rawDataDecimals));}
    if(DECIMALS < _rawDataDecimals){
      _data = _rawData / (10** (_rawDataDecimals - DECIMALS));}}

  function toDecimals(uint256 _rawData, uint256 _rawDataDecimals) public pure returns(uint256 _data){
    _data = _rawData;
    if(DECIMALS > _rawDataDecimals){
      _data = _rawData / (10 ** (DECIMALS - _rawDataDecimals));}
    else if(DECIMALS < _rawDataDecimals){
      _data = _rawData * (10 ** (_rawDataDecimals - DECIMALS));}}

  function toDecimalsInt(int256 _amount, uint256 _tokenDecimals) external pure returns(int256 _newAmount){
    _newAmount = _amount;
    if(_amount > 0) {
      _newAmount = SafeCast.toInt256(toDecimals(uint256(_amount), _tokenDecimals));}
    else if(_amount < 0) {
      _newAmount = -SafeCast.toInt256(toDecimals(uint256(-_amount), _tokenDecimals));}}
  
  function cleanTradeAmounts(int256 _underlyingAmt, int256 _fundingAmt, address _underlyingAddress, address _fundingAddress) external pure returns(uint256 _fromAmount, uint256 _toAmount, address _fromAddress, address _toAddress){
    _fromAmount = 0;
    _toAmount = 0;
    _fromAddress = _fundingAddress;
    _toAddress = _underlyingAddress;
    if(_underlyingAmt > 0 && _fundingAmt < 0){
      _fromAmount = uint256(-_fundingAmt);
      _toAmount = uint256(_underlyingAmt);}
    else if(_underlyingAmt < 0 && _fundingAmt> 0){
      _fromAmount = uint256(-_underlyingAmt);
      _fromAddress = _underlyingAddress;
      _toAmount = uint256(_fundingAmt);
      _toAddress = _fundingAddress;}}

  // calculate the gross capital of a market address, in DEFAULT decimals.
  function getGrossCapital(MarketMaker _market, uint256 _price) external view returns(uint256){
    // _price = _volChain.queryPrice();
    // if(_pool.aaveAddressesProvider() != address(0)){
    //   IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(ILendingPoolAddressesProvider(_pool.aaveAddressesProvider()).getAddress("0x1"));
    //   (uint256 _underlyingBalance, , uint256 _debtBalance) = getTokenBalances(address(_pool), _protocolDataProvider, _pool.underlying());
    //   (uint256 _fundingBalance, uint256 _collateralBalance,) = getTokenBalances(address(_pool), _protocolDataProvider, _pool.govToken().funding());

    //   _capital = _fundingBalance + _collateralBalance + _underlyingBalance.ethmul(_price);
    //   uint256 _debt_amount = _debtBalance.ethmul(_price);
    //   require(_capital > _debt_amount, "Negative equity.");
    //   _capital -= _debt_amount;}
    // else{
    uint256 _underlyingBalance = balanceDef(ERC20(_market.underlying()), address(_market));
    uint256 _fundingBalance = balanceDef(_market.govToken().funding(), address(_market));
    return  _fundingBalance + _underlyingBalance.ethmul(_price);}
  
  function calcRiskPremium(uint256 _grossCapital, int256 _currentNetNotional, int256 _newNetNotional, uint256 _runningVol,uint256 _volCapacityFactor ) external pure returns(uint256){
    int256 _riskPremium = calcRiskPremiumAMM(_grossCapital, _currentNetNotional,  _runningVol, _volCapacityFactor).average(calcRiskPremiumAMM(_grossCapital, _newNetNotional, _runningVol, _volCapacityFactor));
    require((SafeCast.toInt256(_runningVol) + _riskPremium) > 0,"Incorrect vol premium");
    return SafeCast.toUint256(SafeCast.toInt256(_runningVol) + _riskPremium); 
  }

  function calcRiskPremiumAMM(uint256 _max, int256 _input, uint256 _constant, uint256 _volCapacityFactor) public pure returns(int256) {
    int256 _capacity = SafeCast.toInt256(BASE); // capacity should be in (0,2)
    if(_input < 0){_capacity +=  SafeCast.toInt256(uint256(-_input).muldiv(_volCapacityFactor, _max));}
    if(_input > 0){ _capacity -= SafeCast.toInt256(uint256(_input).muldiv(_volCapacityFactor, _max));}
    require(_capacity>=0 , "Capacity breached.");
    return SafeCast.toInt256(_constant.ethdiv(uint256(_capacity))) - SafeCast.toInt256(_constant);}
}
