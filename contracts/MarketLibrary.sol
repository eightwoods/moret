// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MoretInterfaces.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./FullMath.sol";
import "./OptionLibrary.sol";

library MarketLibrary {
  
  function getLendingTokenAddresses(address _protocolDataProviderAddress, address _tokenAddress)
  public view returns (address, address, address){
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_protocolDataProviderAddress);
    return  _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);}

  function getTokenBalances(address _contractAddress, address _protocolDataProviderAddress, address _tokenAddress) public view returns(uint256, uint256, uint256) {
    (address _aToken, address _stableLoan, address _variableLoan) = getLendingTokenAddresses(_protocolDataProviderAddress, _tokenAddress);
    return (balanceDef(_tokenAddress, _contractAddress), balanceDef(_aToken, _contractAddress),balanceDef(_stableLoan, _contractAddress) + balanceDef(_variableLoan, _contractAddress)); }

  function getLTV(address _protocolDataProviderAddress, address _tokenAddress) public view returns (uint256) {
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_protocolDataProviderAddress);
    (, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);
    return OptionLibrary.ToDefaultDecimals(_ltv, 4); } 
    
  function getLoanTrade(address _contractAddress, address _protocolDataProviderAddress, int256 _aggregateDelta, address _underlyingAddress, bool _useVariableRate) public view returns(int256 _loanChange, uint256 _targetLoan, address _loanAddress){
    ( , address _stableLoanAddress,  address _variableLoanAddress) = IProtocolDataProvider(_protocolDataProviderAddress).getReserveTokensAddresses(_underlyingAddress);
    _loanAddress = _useVariableRate? _variableLoanAddress: _stableLoanAddress;
    uint256 _debtBalance = balanceDef(_loanAddress, _contractAddress);
    _targetLoan = _aggregateDelta >=0 ? 0: uint256(-_aggregateDelta);
    _loanChange = int256(_targetLoan) - int256(_debtBalance);}
  
  function getCollateralTrade(address _contractAddress, address _protocolDataProviderAddress, uint256 _targetLoan, uint256 _price, address _fundingAddress, address _underlyingAddress) public view returns(int256 _collateralChange, address _collateralAddress) {
    (_collateralAddress, , ) = IProtocolDataProvider(_protocolDataProviderAddress).getReserveTokensAddresses(_fundingAddress);
    uint256 _ltv = getLTV(_protocolDataProviderAddress, _underlyingAddress);
    uint256 _collateralBalance = balanceDef(_collateralAddress, _contractAddress);
    uint256 _requiredCollateral = MulDiv(_targetLoan, _price , _ltv);
    uint256 _fundingBalance = balanceDef(_fundingAddress, _contractAddress);
    require(_requiredCollateral<= (_fundingBalance + _collateralBalance), "Insufficient collateral;");
    _collateralChange =  int256(_requiredCollateral) - int256(_collateralBalance);}

  function getSwapTrade(address _contractAddress, int256 _aggregateDelta, address _underlyingAddress) public view returns (int256 _underlyingChange){
    _underlyingChange = (_aggregateDelta >=0 ? _aggregateDelta: int256(0)) - int256(IERC20(_underlyingAddress).balanceOf(_contractAddress));}

  function balanceDef(address _tokenAddress, address _accountAddress) public view returns(uint256){
    return OptionLibrary.ToDefaultDecimals(ERC20(_tokenAddress).balanceOf(_accountAddress), ERC20(_tokenAddress).decimals());}

  function cvtDef(uint256 _amount, address _tokenAddress) public view returns(uint256){
    return OptionLibrary.ToDefaultDecimals(_amount, ERC20(_tokenAddress).decimals());}

  function cvtDecimals(uint256 _amount, address _tokenAddress) public view returns(uint256){
    return OptionLibrary.ToCustomDecimals(_amount, ERC20(_tokenAddress).decimals());}

  function cvtDecimalsInt(int256 _amount, address _tokenAddress) public view returns(int256 _newAmount){
    _newAmount = _amount;
    if(_amount > 0) _newAmount = int256(cvtDecimals(uint256(_amount), _tokenAddress));
    if(_amount < 0) _newAmount = -int256(cvtDecimals(uint256(-_amount), _tokenAddress));}
  
  function cleanTradeAmounts(int256 _underlyingAmt, int256 _fundingAmt, address _underlyingAddress, address _fundingAddress) public pure returns(uint256 _fromAmount, uint256 _toAmount, address _fromAddress, address _toAddress){
    _fromAmount = 0;
    _toAmount = 0;
    _fromAddress = _fundingAddress;
    _toAddress = _underlyingAddress;
    if(_underlyingAmt > 0 && _fundingAmt < 0){
      _fromAmount = uint256(-_fundingAmt);
      _toAmount = uint256(_underlyingAmt);}
    if(_underlyingAmt < 0 && _fundingAmt> 0){
      _fromAmount = uint256(-_underlyingAmt);
      _fromAddress = _underlyingAddress;
      _toAmount = uint256(_fundingAmt);
      _toAddress = _fundingAddress;}}
}
