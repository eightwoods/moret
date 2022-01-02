// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IProtocolDataProvider.sol";
import "./FullMath.sol";
import "./OptionLibrary.sol";

library MarketLibrary {
  using FullMath for uint256;
  uint256 public constant LTV_DECIMALS = 4;
  uint256 public constant DECIMALS = 18;

  // Returns balances of ERC20 token (as for _tokenAddress), its corresponding aToken (i.e. collaterals posted), and its debt tokens (including both variable and fixed loans)
  function getTokenBalances(address _contractAddress, IProtocolDataProvider _protocolDataProvider, ERC20 _token) public view returns(uint256, uint256, uint256) {
    (address _aToken, address _stableLoan, address _variableLoan) = _protocolDataProvider.getReserveTokensAddresses(address(_token));
    return (balanceDef(_token, _contractAddress), balanceDef(ERC20(_aToken), _contractAddress),balanceDef(ERC20(_stableLoan), _contractAddress) + balanceDef(ERC20(_variableLoan), _contractAddress)); }

  function getLTV(IProtocolDataProvider _protocolDataProvider, address _tokenAddress) public view returns (uint256) {
    (, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);
    return toWei(_ltv, LTV_DECIMALS); } 
    
  function getLoanTrade(address _contractAddress, IProtocolDataProvider _protocolDataProvider, int256 _aggregateDelta, ERC20 _underlying, bool _useVariableRate) public view returns(int256 _loanChange, uint256 _targetLoan, address _loanAddress){
    ( , address _stableLoanAddress,  address _variableLoanAddress) = _protocolDataProvider.getReserveTokensAddresses(address(_underlying));
    _loanAddress = _useVariableRate? _variableLoanAddress: _stableLoanAddress;
    uint256 _debtBalance = balanceDef(ERC20(_loanAddress), _contractAddress);
    _targetLoan = _aggregateDelta >=0 ? 0: uint256(-_aggregateDelta);
    _loanChange = SafeCast.toInt256(_targetLoan) - SafeCast.toInt256(_debtBalance);}
  
  function getCollateralTrade(address _contractAddress, IProtocolDataProvider _protocolDataProvider, uint256 _targetLoan, uint256 _price, ERC20 _funding, ERC20 _underlying, uint256 _overCollateral) public view returns(int256 _collateralChange, address _collateralAddress) {
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

  function toDecimalsInt(int256 _amount, uint256 _tokenDecimals) public pure returns(int256 _newAmount){
    _newAmount = _amount;
    if(_amount > 0) {
      _newAmount = SafeCast.toInt256(toDecimals(uint256(_amount), _tokenDecimals));}
    else if(_amount < 0) {
      _newAmount = -SafeCast.toInt256(toDecimals(uint256(-_amount), _tokenDecimals));}}
  
  function cleanTradeAmounts(int256 _underlyingAmt, int256 _fundingAmt, address _underlyingAddress, address _fundingAddress) public pure returns(uint256 _fromAmount, uint256 _toAmount, address _fromAddress, address _toAddress){
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
}
