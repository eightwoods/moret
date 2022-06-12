// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../pools/Pool.sol";
import "../libraries/MathLib.sol";
import "../interfaces/EMoret.sol";
import "../VolatilityChain.sol";
import "../VolatilityToken.sol";
import "../Exchange.sol";
import "./MoretBroker.sol";

/// @custom:security-contact eight@moret.io
contract Moret is ERC20, Ownable, ERC20Permit, ERC20Votes, EMoret {
    using MathLib for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    EnumerableSet.AddressSet internal underlyingList; // list of underlying tokens
    mapping(address=>VolatilityChain) internal volatilityChainMap; // volatility oracle: token address => volatiltiy chain address
    mapping(address=>EnumerableMap.UintToAddressMap) internal volatilityTokenMap; // volatility token list: token address => volatility token map (tenor => volatility tokens)
    EnumerableSet.AddressSet internal eligibleTradingRoutes; // list of exchange routes that are allowed for hedging transactions
    EnumerableSet.AddressSet internal volTradingPools; // pools allowed to trade volatility tokens

    uint256 public protocolFee = 0.005e18; // protocol fees payable to governance token each time option contract is exercised
    address public protocolFeeRecipient;
    
    // funding token address
    ERC20 public funding;
    MoretBroker public broker;

    constructor(MoretBroker _broker) ERC20("Moret", "MOR") ERC20Permit("Moret") {
        broker = _broker;
        funding = _broker.funding();
        _mint(msg.sender, 1e24); // initial mint, 1e6 * 1e18
        protocolFeeRecipient = msg.sender;
        }
    
    // mint function
    function mint(address _to, uint256 _amount) external {
        require(address(broker) == msg.sender, 'broker only');
        _mint(_to, _amount);}
    function divest(uint256 _amount) external {
        uint256 _capitalToDivest = _amount.muldiv(funding.balanceOf(address(this)), totalSupply());
        _burn(msg.sender, _amount);
        funding.transfer(msg.sender, _capitalToDivest);
        // emit DivestFromGov(msg.sender, _capitalToDivest);}
    }

    // withdraw from certain pool so funding tokens can be saved in. This could be only executed by the owner address
    function withdraw(Pool _pool, uint256 _amount) external onlyOwner{
        Exchange(_pool.exchange()).withdrawCapital(_pool, _amount);
        emit WithdrawPoolTokens(address(_pool), _amount);}

    // governable parameters
    function setProtocolFee(uint256 _newFee) public onlyOwner(){ 
        protocolFee = _newFee;
        emit UpdateProtocolFees(_newFee);}
    function setProtocolRecipient(address _newAddress) public onlyOwner(){ 
        require(_newAddress != address(0), "0 address"); 
        protocolFeeRecipient = _newAddress;}

    // list of underlying addresses
    function getAllUnderlyings() external view returns(address[] memory){
        return underlyingList.values();}

    // update/add new volatility oracles
    function updateVolChain(address _underlyingAddress, VolatilityChain _newOracle) external onlyOwner{
        if(!underlyingList.contains(_underlyingAddress)){
            underlyingList.add(_underlyingAddress);}
        volatilityChainMap[_underlyingAddress] = _newOracle;}
        // emit UpdateToken( _underlyingAddress, address(_newOracle));}
    function getVolatilityChain(address _underlyingAddress) public view returns(VolatilityChain){
        require(address(volatilityChainMap[_underlyingAddress]) != address(0), "Oracle not registered");
        return volatilityChainMap[_underlyingAddress];}
    
    // update/get vol tokens.
    function updateVolToken(address _underlyingAddress, uint256 _tenor, VolatilityToken _volToken) external onlyOwner{ 
        require((_volToken.tenor() == _tenor) && (_volToken.underlying() == _underlyingAddress), 'xV');
        volatilityTokenMap[_underlyingAddress].set(_tenor, address(_volToken));}
        // emit UpdateVolToken(_underlyingAddress, _tenor, address(_volToken)); }
    function getVolatilityToken(address _underlyingAddress, uint256 _tenor) external view returns (VolatilityToken){
        (bool _success, address _volToken) = volatilityTokenMap[_underlyingAddress].tryGet(_tenor);
        require(_success, "no vol token");
        return VolatilityToken(_volToken);}
    
    // update eligible routes
    function updateEligibleRoute(address _route, bool _add) public onlyOwner returns(bool){
        require(_route != address(0), "empty address");
        if(_add) { return eligibleTradingRoutes.add(_route);}
        else{ return eligibleTradingRoutes.remove(_route);}}
    function existEligibleRoute(address _route) external view returns(bool){
        return eligibleTradingRoutes.contains(_route);}
    
    // update vol trading pool
    function updateVolTradingPool(address _poolAddress, bool _add) public onlyOwner returns(bool){
        require(_poolAddress != address(0), "empty address");
        if(_add) { return volTradingPools.add(_poolAddress);}
        else{ return volTradingPools.remove(_poolAddress);}}
    function existVolTradingPool(address _poolAddress) external view returns(bool){
        return volTradingPools.contains(_poolAddress);}

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}
