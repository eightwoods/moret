pragma solidity ^0.8.4;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
 */

import "./FullMath.sol";
import "./MoretInterfaces.sol";
import "./OptionLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract VolatilityToken is ERC20, AccessControl, IOption
{
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant MARKET_MAKING_ROLE = keccak256("MARKET_MAKING_ROLE");
  uint256 private constant ethMultiplier = 10 ** 18;

  uint256 public tenor;
  bytes32 public descriptionHash;
  address payable public contractAddress;

  OptionLibrary.Percent public margin;
  bool public isUnderlyingNative;

  constructor(
    string memory _underlyingName,
    uint256 _tenor,
    string memory _name,
    string memory _symbol
    )
  ERC20(_name, _symbol)
  {
     _setupRole(ADMIN_ROLE, msg.sender);
     _setupRole(MARKET_MAKING_ROLE, msg.sender);

    tenor = _tenor;
    descriptionHash = keccak256(abi.encodePacked(_underlyingName));
    margin = OptionLibrary.Percent(10 ** 4, 10 ** 6);

    contractAddress = payable(address(this));
  }

  function mint(address _account, uint256 _amount) public payable onlyRole(MARKET_MAKING_ROLE) {
      _mint(_account, _amount);
  }

  function burn(address _account, uint256 _amount) public onlyRole(MARKET_MAKING_ROLE){
      _burn(_account, _amount);
  }

    function calculateMintValue(uint256 _amount, uint256 _price, uint256 _volatility)
    public view returns(uint256){
        return MulDiv(MulDiv(_amount, _volatility, _price), margin.denominator + margin.numerator, margin.denominator);
    }

    function calculateMintableAmount(uint256 _ethValue, uint256 _price, uint256 _volatility)
    public view returns(uint256){
        return MulDiv(MulDiv(_ethValue, margin.denominator, margin.denominator + margin.numerator), _price, _volatility);
    }

    function recycle(address payable _recipient, uint256 _amount) external onlyRole(MARKET_MAKING_ROLE) returns(uint256) {
        uint256 _impliedPrice = MulDiv(contractAddress.balance, ethMultiplier, totalSupply());
        uint256 _swapAmount = MulDiv(_amount, _impliedPrice, ethMultiplier);

        require(_swapAmount<= contractAddress.balance, "Current balance not enough.");

        (bool _sent, ) = _recipient.call{value: _swapAmount }("");
        require(_sent, "Withdrawal failed.");

        _burn(_recipient, _amount);
        return _swapAmount;
    }

    function recycleInToken(address payable _recipient, uint256 _amount, ERC20 _token) external onlyRole(MARKET_MAKING_ROLE) returns(uint256) {
        uint256 _impliedPrice = MulDiv(_token.balanceOf(contractAddress), ethMultiplier, totalSupply());
        uint256 _swapAmount = MulDiv(_amount, _impliedPrice, ethMultiplier);

        require(_swapAmount<= _token.balanceOf(contractAddress), "Current balance not enough.");
        require(_token.transfer(_recipient, _swapAmount), "Withdrawal failed.");

        _burn(_recipient, _amount);
        return _swapAmount;
    }

    function resetMargin(uint256 _margin, uint256 _marginDenominator) public onlyRole(ADMIN_ROLE){
        margin = OptionLibrary.Percent(_margin, _marginDenominator);
        /* emit newMargin(_margin); */
    }


    receive() external payable{}

    /* event newMargin(uint256 _margin); */
}
