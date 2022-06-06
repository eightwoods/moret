// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "../pools/Pool.sol";
import "../libraries/MathLib.sol";
import "../interfaces/EMoret.sol";
import "../OptionVault.sol";
import "../VolatilityChain.sol";
import "./Moret.sol";

/// @custom:security-contact eight@moret.io
contract MoretBroker is EMoret, AccessControl {
    using MathLib for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // list of pools
    mapping(address=>address) internal topPoolMap; // only the top pool address is allowed to exchange their pool tokens with Moret. underlying token addres => pool address
    mapping(address=>EnumerableSet.AddressSet) internal allPoolMap; // all created pools
    
    // capital records
    uint256 public minCapital; // 1m minimum capital for the whole Moret pool and for exchanges
    uint256 public poolCapital = 0; // total capitals
    mapping(address=>EnumerableMap.AddressToUintMap) internal poolCapitalMap;
    
    // address
    ERC20 public funding;
    OptionVault public vault;

    constructor(ERC20 _funding, OptionVault _vault){
        funding = _funding;
        vault = _vault;
        minCapital = 1e24; // 1m min notional (in 18 decimals)
        }

    // functions to allow pool to exchange their tokens for Moret
    // arguments: pool contract address, amount of pool tokens to be exchanged
    // a minimum capital of 1m USDC is assumed for any exchange calculations.
    function exchangePoolForMoret(Pool _pool, uint256 _payInAmount) external{
        Moret _gov = _pool.marketMaker().govToken();
        address _underlyingAddress = _pool.marketMaker().underlying();
        _gov.getVolatilityChain(_underlyingAddress); // use this function to check if underlying exists.

        uint256 _poolNetCapital = getAndUpdateTopPool(_pool, _underlyingAddress);
        uint256 _payInCapital = _payInAmount.muldiv(_poolNetCapital, _pool.totalSupply());
        uint256 _existingCapital = Math.max(minCapital, poolCapital);
        uint256 _mintAmount = _payInCapital.muldiv(_gov.totalSupply(), _existingCapital);

        _pool.transferFrom(msg.sender, address(_gov), _payInAmount);
        uint256 _updatedCapital = _pool.balanceOf(address(_gov)).muldiv(_poolNetCapital, _pool.totalSupply());
        if(poolCapitalMap[_underlyingAddress].contains(address(_pool))){
            poolCapital = poolCapital - Math.min(poolCapital, poolCapitalMap[_underlyingAddress].get(address(_pool))) + _updatedCapital;
        }
        else{
            poolCapital = poolCapital + _updatedCapital;
        }
        poolCapitalMap[_underlyingAddress].set(address(_pool), _updatedCapital);
        
        _gov.mint(msg.sender, _mintAmount); // This ensures only the right Moret contract mints.
        emit ExchangePoolTokens(address(_pool), msg.sender, _payInAmount, _mintAmount);}

    function getAndUpdateTopPool(Pool _pool, address _underlyingAddress) internal returns(uint256 _poolNetCapital){
        _poolNetCapital = vault.calcCapital(_pool, true, false);
        require(_poolNetCapital > minCapital, "min capital not met.");

        if (topPoolMap[_underlyingAddress] != address(_pool)){
            uint256 _topCapital = (topPoolMap[_underlyingAddress] != address(0))? vault.calcCapital(Pool(topPoolMap[_underlyingAddress]), true, false): 0;
            if (_poolNetCapital > _topCapital) {
                topPoolMap[_underlyingAddress] = address(_pool);}}}

    // update list of pools
    function addPool(Pool _pool) external{
        allPoolMap[_pool.marketMaker().underlying()].add(address(_pool));}
    function getAllPools(address _underlyingAddress) external view returns(address[] memory){
        return allPoolMap[_underlyingAddress].values();}
    function getTopPool(address _underlyingAddress) external view returns(address){
        return topPoolMap[_underlyingAddress];}
    // function getPoolsCount(address _underlyingAddress) external view returns(uint256){
    //     return allPoolMap[_underlyingAddress].length();}
    
}