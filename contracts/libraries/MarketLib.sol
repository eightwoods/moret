// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../pools/Pool.sol";
import "../pools/MarketMaker.sol";
import "./MathLib.sol";

library MarketLib {
  using MathLib for uint256;
  using SignedMath for int256;
  uint256 public constant LTV_DECIMALS = 4;
  uint256 public constant DECIMALS = 18;
  uint256 internal constant BASE  = 1e18;

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
    uint256 _underlyingBalance = balanceDef(ERC20(_market.underlying()), address(_market));
    uint256 _fundingBalance = balanceDef(ERC20(_market.funding()), address(_market));
    return  _fundingBalance + _underlyingBalance.ethmul(_price);}
  
  
}
