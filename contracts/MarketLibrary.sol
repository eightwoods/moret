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
  function getLendingTokenAddresses(address _protocolDataProviderAddress, address _tokenAddress)
  public view returns (address, address, address){
    /* ILendingPoolAddressesProvider _lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProviderAddress); */
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_protocolDataProviderAddress);
    return  _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);
  }

  function getLTV(address _protocolDataProviderAddress, address _tokenAddress)
  public view returns (uint256, uint256)
  {
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_protocolDataProviderAddress);
    (uint256 _reserveDecimals, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);
    return (_ltv, 10**_reserveDecimals);
  }

  function calcRepay(int256 _targetBalances, address _contractAddress, address _protocolDataProviderAddress, address _tokenAddress)
  public view returns(uint256)
  {
    (address _aToken, address _stableDebt, address _variableDebt) = getLendingTokenAddresses(_protocolDataProviderAddress, _tokenAddress);
    uint256 _currentBalances = IERC20(_tokenAddress).balanceOf(_contractAddress) + IERC20(_aToken).balanceOf(_contractAddress);
    return Math.min(uint256(int256(_currentBalances) - _targetBalances),
      IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress));
  }

  function calcBorrow(int256 _targetBalances, address _contractAddress, address _protocolDataProviderAddress, address _tokenAddress)
  public view returns(uint256)
  {
    (address _aToken, ,) = getLendingTokenAddresses(_protocolDataProviderAddress, _tokenAddress);
    (uint256 _ltv, uint256 _ltvMultiplier) = getLTV(_protocolDataProviderAddress, _tokenAddress);

    uint256 _currentBalances = IERC20(_tokenAddress).balanceOf(_contractAddress) + IERC20(_aToken).balanceOf(_contractAddress);
    return Math.min(uint256(_targetBalances) - _currentBalances,
        MulDiv(IERC20(_tokenAddress).balanceOf(_contractAddress) - MulDiv(IERC20(_aToken).balanceOf(_contractAddress) , _ltv, _ltvMultiplier) , _ltv, _ltvMultiplier));
  }

  function calcWithdrawCollateral(address _contractAddress, address _protocolDataProviderAddress, address _tokenAddress)
  public view returns(uint256)
  {
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_protocolDataProviderAddress);
    (address _aToken, address _stableDebt, address _variableDebt) = _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);
    (uint256 _reserveDecimals, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);

    uint256 _desiredCollateral = MulDiv(IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress), 10 ** _reserveDecimals, _ltv);
    return (IERC20(_aToken).balanceOf(_contractAddress) > _desiredCollateral)? (IERC20(_aToken).balanceOf(_contractAddress) - _desiredCollateral): 0;
  }

  function calcDepositCollateral(uint256 _newBorrowing, address _contractAddress, address _protocolDataProviderAddress, address _tokenAddress)
  public view returns (uint256)
  {
    IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(_protocolDataProviderAddress);
    (address _aToken, address _stableDebt, address _variableDebt) = _protocolDataProvider.getReserveTokensAddresses(_tokenAddress);
    (uint256 _reserveDecimals, uint256 _ltv, ,,,,,,, ) = _protocolDataProvider.getReserveConfigurationData(_tokenAddress);

    uint256 _desiredCollateral = MulDiv(_newBorrowing + IERC20(_stableDebt).balanceOf(_contractAddress) + IERC20(_variableDebt).balanceOf(_contractAddress), 10 ** _reserveDecimals, _ltv);
    return (IERC20(_aToken).balanceOf(_contractAddress) < _desiredCollateral)?
      Math.min(IERC20(_tokenAddress).balanceOf(_contractAddress) , _desiredCollateral - IERC20(_aToken).balanceOf(_contractAddress)): 0;
  }

}
