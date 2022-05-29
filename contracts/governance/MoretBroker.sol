// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
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

    // list of pools
    mapping(address=>address) internal topPoolMap; // only the top pool address is allowed to exchange their pool tokens with Moret. underlying token addres => pool address
    mapping(address=>EnumerableSet.AddressSet) internal allPoolMap; // all created pools
    
    // capital records
    uint256 public minCapital; // 1m minimum capital for the whole Moret pool and for exchanges
    uint256 public poolCapital = 0; // total capitals
    
    // address
    ERC20 public funding;
    OptionVault public vault;

    constructor(ERC20 _funding, OptionVault _vault){
        funding = _funding;
        vault = _vault;
        minCapital = 1e6 * (10 ** (funding.decimals())); // 1m min notional (in funding token decimals)
        }

    // functions to allow pool to exchange their tokens for Moret
    // arguments: pool contract address, amount of pool tokens to be exchanged
    // a minimum capital of 1m USDC is assumed for any exchange calculations.
    function exchangePoolForMoret(Pool _pool, uint256 _payInAmount) external{
        Moret _gov = _pool.marketMaker().govToken();
        _gov.getVolatilityChain(_pool.marketMaker().underlying()); // use this function to check if underlying exists.

        uint256 _poolNetCapital = getAndUpdateTopPool(_pool);
        uint256 _currentCapital = Math.max(minCapital, poolCapital);

        uint256 _payInCapital = _payInAmount.muldiv(_poolNetCapital, _pool.totalSupply());
        uint256 _mintAmount = _payInCapital.muldiv(_gov.totalSupply(), _currentCapital);
        _pool.transferFrom(msg.sender, address(_gov), _payInAmount);
        poolCapital += _payInCapital;
        _gov.mint(msg.sender, _mintAmount); // This ensures only the right Moret contract mints.
        emit ExchangePoolTokens(address(_pool), msg.sender, _payInAmount, _mintAmount);}

    function getAndUpdateTopPool(Pool _pool) internal returns(uint256 _poolNetCapital){
        address _underlyingAddress = _pool.marketMaker().underlying();
        _poolNetCapital = vault.calcCapital(_pool, true, false);
        require(_poolNetCapital > minCapital, "min capital not met.");

        if ((topPoolMap[_underlyingAddress] != address(0)) && (topPoolMap[_underlyingAddress] != address(_pool)))
        {
            uint256 _topCapital = vault.calcCapital(Pool(topPoolMap[_underlyingAddress]), true, false);
            require(_poolNetCapital > _topCapital, 'not the top exchange');
            topPoolMap[_underlyingAddress] = address(_pool);}}

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