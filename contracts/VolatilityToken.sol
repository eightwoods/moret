pragma solidity ^0.8.4;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
 */

import "./FullMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract VolatilityToken is ERC20, Ownable, AccessControl
{
  bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
  bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
  uint256 public tenor;
  bytes32 public underlyingHash;
  address payable public contractAddress;

  uint256 public margin;
  uint256 public constant marginDenom = 10 ** 6;

  constructor(
    string memory _underlyingName,
    uint256 _tenor,
    string memory _name,
    string memory _symbol
    )
  ERC20(_name, _symbol)
  {
     _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
     _setupRole(MINT_ROLE, msg.sender);
     _setupRole(BURN_ROLE, msg.sender);

    tenor = _tenor;
    underlyingHash = keccak256(abi.encodePacked(_underlyingName));
    margin = 10000;

    contractAddress = payable(address(this));
  }

  function mint(address _account, uint256 _amount) public payable onlyRole(MINT_ROLE) {
        (bool _sent, ) = contractAddress.call{value: msg.value }("");
        require(_sent, "Deposit failed.");

        _mint(_account, _amount);
  }

  function burn(address _account, uint256 _amount) public onlyRole(BURN_ROLE){
      _burn(_account, _amount);
  }

    function calculateMintValue(uint256 _amount, uint256 _price, uint256 _volatility)
    public view returns(uint256){
        return MulDiv(MulDiv(_amount, _volatility, _price), marginDenom + margin, marginDenom);
    }

    function calculateMintableAmount(uint256 _ethValue, uint256 _price, uint256 _volatility)
    public view returns(uint256){
        return MulDiv(MulDiv(_ethValue, marginDenom, marginDenom + margin), _price, _volatility);
    }

    function recycle(address payable _recipient, uint256 _tokenAmount) external payable onlyRole(BURN_ROLE) {
        uint256 _impliedPrice = MulDiv(contractAddress.balance, 10 ** 18, totalSupply());
        uint256 _swapAmount = MulDiv(_tokenAmount, _impliedPrice, 10 ** 18);

        require(_swapAmount<= payable(address(this)).balance, "Current ETH balance not enough.");

        (bool _sent, ) = _recipient.call{value: _swapAmount }("");
        require(_sent, "Withdrawal failed.");

        require(increaseAllowance(contractAddress, _tokenAmount), "Increase Allowance failed.");
        _burn(_recipient, _tokenAmount);
    }

    function resetMargin(uint256 _margin) public onlyOwner{
        margin = _margin;
        emit newMargin(_margin);
    }

    receive() external payable{}

    event newMargin(uint256 _margin);
}
