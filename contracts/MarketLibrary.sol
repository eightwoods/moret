/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
*/

pragma solidity ^0.8.4;

import "./MarketInterfaces.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./FullMath.sol";

library MarketLibrary {
  function getLendingTokenAddresses(address _lendingPoolAddressProviderAddress, address _tokenAddress)
  public view returns (address, address, address){
    ILendingPoolAddressesProvider _lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProviderAddress);
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_lendingPoolAddressProvider.getAddress("0x1"));
    return  _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);
  }

  function calcBalancesIncDebt(address _contractAddress, address _lendingPoolAddressProviderAddress, address _tokenAddress)
  public view returns (uint256){
    (address _aToken, address _stableDebt, address _variableDebt) = getLendingTokenAddresses (_lendingPoolAddressProviderAddress, _tokenAddress );
    return IERC20(_tokenAddress).balanceOf(_contractAddress) + IERC20(_aToken).balanceOf(_contractAddress) + IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress);
  }

  function getLTV(address _lendingPoolAddressProviderAddress, address _tokenAddress)
  public view returns (uint256, uint256)
  {
    ILendingPoolAddressesProvider _lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProviderAddress);
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_lendingPoolAddressProvider.getAddress("0x1"));
    (uint256 _reserveDecimals, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);
    return (_ltv, 10**_reserveDecimals);
  }

  // Negative for repay, positive for borrow
  function calcRepayOrBorrow(int256 _targetBalances, address _contractAddress, address _lendingPoolAddressProviderAddress, address _tokenAddress)
  public view returns (int256)
  {
    (address _aToken, address _stableDebt, address _variableDebt) = getLendingTokenAddresses(_lendingPoolAddressProviderAddress, _tokenAddress);
    uint256 _currentBalances = IERC20(_tokenAddress).balanceOf(_contractAddress) + IERC20(_aToken).balanceOf(_contractAddress) + IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress);
    (uint256 _ltv, uint256 _ltvMultiplier) = getLTV(_lendingPoolAddressProviderAddress, _tokenAddress);

    int256 _repayOrBorrow = 0;
    if(_targetBalances < int256(_currentBalances))
    {
        _repayOrBorrow = -int256(Math.min(uint256(int256(_currentBalances) - _targetBalances),
          IERC20(_stableDebt).balanceOf(address(_contractAddress)) + IERC20(_variableDebt).balanceOf(_contractAddress)));
    }
    if(_targetBalances > int256(_currentBalances))
    {
        _repayOrBorrow = int256(Math.min(MulDiv(IERC20(_tokenAddress).balanceOf(_contractAddress), _ltv, _ltvMultiplier),
          uint256(_targetBalances) - _currentBalances));
    }
    return _repayOrBorrow;
  }

  function calcWithdrawCollateral(address _contractAddress, address _lendingPoolAddressProviderAddress, address _tokenAddress)
  public view returns(uint256)
  {
    ILendingPoolAddressesProvider _lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProviderAddress);
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_lendingPoolAddressProvider.getAddress("0x1"));
    (address _aToken, address _stableDebt, address _variableDebt) = _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);
    (uint256 _reserveDecimals, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);

    uint256 _desiredCollateral = MulDiv(IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress), 10 ** _reserveDecimals, _ltv);
    return (IERC20(_aToken).balanceOf(_contractAddress) > _desiredCollateral)? (IERC20(_aToken).balanceOf(_contractAddress) - _desiredCollateral): 0;
  }

  function calcDepositCollateral(uint256 _newBorrowing, address _contractAddress, address _lendingPoolAddressProviderAddress, address _tokenAddress)
  public view returns (uint256)
  {
    ILendingPoolAddressesProvider _lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProviderAddress);
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_lendingPoolAddressProvider.getAddress("0x1"));
    (address _aToken, address _stableDebt, address _variableDebt) = _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);
    (uint256 _reserveDecimals, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);

    uint256 _desiredCollateral = MulDiv(_newBorrowing + IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress), 10 ** _reserveDecimals, _ltv);
    return (IERC20(_aToken).balanceOf(_contractAddress) < _desiredCollateral)? Math.min(IERC20(_tokenAddress).balanceOf(_contractAddress) , _desiredCollateral - IERC20(_aToken).balanceOf(_contractAddress)): 0;
  }

}
