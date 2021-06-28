pragma solidity ^0.8.4;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Moret
 * Copyright (C) 2021 Moret
 */

import "./VolatilityToken.sol";
import "./VolatilityChain.sol";
import "./FullMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


contract GovernanceToken is ERC20, Ownable, AccessControl
{
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  address payable governanceAddr;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  EnumerableSet.Bytes32Set  tokenHashSet;
  EnumerableSet.UintSet  tenors;
  mapping(bytes32=> VolatilityChain) public volChainList;
  mapping(bytes32=>mapping(uint256=>VolatilityToken)) public volTokensList;

  mapping(bytes32=>uint8) decimalList;

    uint256 public constant pctDenominator = 10 ** 6;
    uint256 public governanceFees = 10000;
    uint256 public loanFees = 200000;
    uint256 public loanDayBase = 31536000;

    constructor(
        string memory _name,
        string memory _symbol) ERC20(_name, _symbol)
    {
        governanceAddr = payable(address(this));

        _mint(governanceAddr, 10 ** (18+10)); // 10 billion total supply.
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    function getVolatilityQuote(string memory _underlying, uint256 _tenor, uint256 _volAmount) public view returns(uint256, uint256)
{
    bytes32 _underlyingHash = keccak256(abi.encodePacked(_underlying));
    require(tokenHashSet.contains(_underlyingHash));
        require(tenors.contains(_tenor));
        (uint256 _price,) = volChainList[_underlyingHash].queryPrice();
        uint256 _volatility = volChainList[_underlyingHash].getVol(_tenor);

        uint256 _quote = volTokensList[_underlyingHash][_tenor].calculateMintValue(_volAmount, _price, _volatility);

        return (_quote, MulDiv(_quote, governanceFees, pctDenominator));
}

    function getVolatilityAmount(string memory _underlying, uint256 _tenor, uint256 _ethAmount) public view returns(uint256, uint256)
    {
        bytes32 _underlyingHash = keccak256(abi.encodePacked(_underlying));
        require(tokenHashSet.contains(_underlyingHash));
        require(tenors.contains(_tenor));

        (uint256 _price,) = volChainList[_underlyingHash].queryPrice();
        uint256 _volatility = volChainList[_underlyingHash].getVol(_tenor);

        uint256 _amount = MulDiv(volTokensList[_underlyingHash][_tenor].calculateMintableAmount(_ethAmount, _price, _volatility), pctDenominator, governanceFees + pctDenominator);
        uint256 _fee = MulDiv(_ethAmount, governanceFees, governanceFees + pctDenominator);

        return (_amount, _fee);
    }

    function purchaseVolatilityToken(string memory _underlying, uint256 _tenor) external payable {
        (uint256 _volTokenAmount, uint256 _fee) = getVolatilityAmount(_underlying, _tenor, msg.value);
        // require(msg.value > _fee);

        (bool _sentFee, ) = governanceAddr.call{value: msg.value}("");
        require(_sentFee, "Fee payment failed.");

        bytes32 _underlyingHash = keccak256(abi.encodePacked(_underlying));
        volTokensList[_underlyingHash][_tenor].mint{value: msg.value - _fee}(msg.sender, _volTokenAmount);

        emit volatilityTokenPurchased(msg.sender, _volTokenAmount,  msg.value,  _fee);
    }

    function addVolChain(string memory _underlying, address _volChainAddress) external onlyRole(ADMIN_ROLE){
        bytes32 _underlyingHash = keccak256(abi.encodePacked(_underlying));

        if(!tokenHashSet.contains(_underlyingHash))
        {
            tokenHashSet.add(_underlyingHash);
        }
        require(_underlyingHash==VolatilityChain(_volChainAddress).tokenHash());
        volChainList[_underlyingHash] = VolatilityChain(_volChainAddress);
    }

    function addVolToken(string memory  _underlying, uint256 _tenor, address payable _tokenAddress) external onlyRole(ADMIN_ROLE)
    {
        bytes32 _underlyingHash = keccak256(abi.encodePacked(_underlying));
        if(!tokenHashSet.contains(_underlyingHash)){
            tokenHashSet.add(_underlyingHash);
        }
        if(!tenors.contains(_tenor)){
            tenors.add(_tenor);
        }
        /* require(_underlyingHash==VolatilityToken(_tokenAddress).descriptionHash()); */
        volTokensList[_underlyingHash][_tenor] = VolatilityToken(_tokenAddress);
        decimalList[_underlyingHash] = volTokensList[_underlyingHash][_tenor].decimals();

        emit newVolatilityToken(_underlying, _tenor, _tokenAddress);
    }

    function removeTenor(uint256 _tenor) external onlyRole(ADMIN_ROLE) {
        require(tenors.contains(_tenor));
        tenors.remove( _tenor);
    }

    function hasVolToken(string memory  _underlying) external view returns(bool)
    {
        return tokenHashSet.contains(keccak256(abi.encodePacked(_underlying)));
    }

    function resetGovernanceFees(uint256 _fee) external onlyRole(ADMIN_ROLE){
        governanceFees = _fee;
        emit newGovernanceFees(_fee);
    }

    function sweepBalance() external onlyOwner{
        uint256 _amount = address(this).balance;
        (bool _sent, ) = payable(msg.sender).call{value: _amount}("");
        require(_sent, "Withdrawal failed.");
        emit cashSweep(_amount);
    }

    receive() external payable{}

    event newGovernanceFees(uint256 _fee);
    event newVolatilityToken(string  _underlying, uint256 _tenor, address _tokenAddress);
    event cashSweep(uint256 _amount);
    event volatilityTokenPurchased(address _buyer, uint256 _amout, uint256 _cost, uint256 _fee);

}
