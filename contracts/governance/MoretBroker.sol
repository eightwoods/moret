// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../pools/Pool.sol";
import "../libraries/MathLib.sol";
import "../interfaces/EMoret.sol";
import "../OptionVault.sol";
import "../VolatilityChain.sol";
import "../Exchange.sol";
import "./Moret.sol";

/// @custom:security-contact eight@moret.io
contract MoretBroker is EMoret, AccessControl, ReentrancyGuard {
    using MathLib for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeERC20 for ERC20;

    // list of pools
    mapping(address=>address) internal topPoolMap; // only the top pool address is allowed to swap their pool tokens with Moret. underlying token addres => pool address
    mapping(address=>EnumerableSet.AddressSet) internal allPoolMap; // all created pools
    
    // capital records
    uint256 public constant minCapital = 1e24; // 1m min notional (in 18 decimals) // 1m minimum capital for the whole Moret pool and for exchanges
    uint256 public poolCapital = 0; // total capitals
    mapping(address=>EnumerableMap.AddressToUintMap) internal poolCapitalMap;
    
    // address
    ERC20 public funding;
    OptionVault public vault;
    address public immutable exchange;

    constructor(ERC20 _funding, address _exchange){
        funding = _funding;
        exchange = _exchange;
        vault = Exchange(_exchange).vault();
        }

    // functions to allow pool to swap their tokens for Moret
    // arguments: pool contract address, amount of pool tokens to be exchanged
    // a minimum capital of 1m USDC is assumed for any calculations.
    function exchangePoolForMoret(address _poolAddr, uint256 _payInAmount) external nonReentrant{
        Pool _pool = Pool(_poolAddr);
        Moret _gov = _pool.marketMaker().govToken();
        address _undAddr = _pool.marketMaker().underlying();
        require(address(_gov.getVolatilityChain(_undAddr)) != address(0), "0volchain"); // use this function to check if underlying exists.

        ERC20(_poolAddr).safeTransferFrom(msg.sender, address(_gov), _payInAmount);

        uint256 _poolNetCapital = getAndUpdateTopPool(_pool, _undAddr);
        uint256 _payInCapital = _payInAmount.muldiv(_poolNetCapital, _pool.totalSupply());
        uint256 _existingCapital = Math.max(minCapital, poolCapital);
        uint256 _mintAmount = _payInCapital.muldiv(_gov.totalSupply(), _existingCapital);

        uint256 _updatedCapital = _pool.balanceOf(address(_gov)).muldiv(_poolNetCapital, _pool.totalSupply());

        // change stats of MoretBroker contract -> hence suspicious to reentry -> taken care of by nonReentrant and the step that pool tokens are first transferred to gov address
        if(poolCapitalMap[_undAddr].contains(_poolAddr)){
            poolCapital = poolCapital - Math.min(poolCapital, poolCapitalMap[_undAddr].get(_poolAddr)) + _updatedCapital;
        }
        else{
            poolCapital = poolCapital + _updatedCapital;
        }
        poolCapitalMap[_undAddr].set(_poolAddr, _updatedCapital);
        
        _gov.mint(msg.sender, _mintAmount); // This ensures only the right Moret contract mints.
        emit ExchangePoolTokens(_poolAddr, msg.sender, _payInAmount, _mintAmount);}

    function getAndUpdateTopPool(Pool _pool, address _undAddr) internal returns(uint256 _poolNetCapital){
        require(allPoolMap[_undAddr].contains(address(_pool)),'-P'); // check if pool was registered already
        _poolNetCapital = vault.calcCapital(_pool, true, false);
        require(_poolNetCapital > minCapital, "mcP"); // pool capital needs to be above threshold

        if (topPoolMap[_undAddr] != address(_pool)){
            uint256 _topCapital = (topPoolMap[_undAddr] != address(0))? vault.calcCapital(Pool(topPoolMap[_undAddr]), true, false): 0;
            if (_poolNetCapital > _topCapital) {
                topPoolMap[_undAddr] = address(_pool);}}}

    // update list of pools
    function addPool(Pool _pool, bool _remove) external{
        address _poolUnd = _pool.marketMaker().underlying();
        require(_pool.marketMaker().funding() == address(funding), 'xfundings');
        require(_pool.exchange() == exchange, '-pEx');
        if(_remove){
            require(allPoolMap[_poolUnd].remove(address(_pool)), '-rm');    
        }
        else{
            require(allPoolMap[_poolUnd].add(address(_pool)) , '-ad');}}
    function getAllPools(address _undAddr) external view returns(address[] memory){
        return allPoolMap[_undAddr].values();}
    function getTopPool(address _undAddr) external view returns(address){
        return topPoolMap[_undAddr];}
    // function getPoolsCount(address _undAddr) external view returns(uint256){
    //     return allPoolMap[_undAddr].length();}
    
}