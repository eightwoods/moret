// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    // using SafeERC20 for ERC20;

    EnumerableSet.AddressSet internal underlyingList; // list of underlying tokens
    mapping(address=>VolatilityChain) internal volatilityChainMap; // volatility oracle: token address => volatiltiy chain address
    mapping(address=>EnumerableMap.UintToAddressMap) internal volatilityTokenMap; // volatility token list: token address => volatility token map (tenor => volatility tokens)
    EnumerableSet.AddressSet internal eligibleTradingRoutes; // list of routes that are allowed for hedging transactions
    EnumerableSet.AddressSet internal volTradingPools; // pools allowed to trade volatility tokens

    uint256 public protocolFee =  0.01e18; // protocol fees payable to governance token each time option contract is exercised
    address public protocolFeeRecipient;
    
    MoretBroker public broker;

    constructor(MoretBroker _broker) ERC20("Moret", "MOR") ERC20Permit("Moret") {
        broker = _broker;
        _mint(msg.sender, 1e26); // initial mint, 1e8 * 1e18
        protocolFeeRecipient = msg.sender;
        }
    
    // mint function
    function mint(address _to, uint256 _amount) external {
        require(address(broker) == msg.sender, 'broker only');
        _mint(_to, _amount);}
    function divest(uint256 _amount) external {
        uint256 _capitalToDivest = _amount.muldiv(broker.funding().balanceOf(address(this)), totalSupply());
        _burn(msg.sender, _amount);
        broker.funding().transfer(msg.sender, _capitalToDivest);
        // emit DivestFromGov(msg.sender, _capitalToDivest);}
    }

    // withdraw from certain pool so funding tokens can be saved in. This could be only executed by the owner address
    function withdraw(Pool _pool, uint256 _amount) external onlyOwner{
        require(_pool.exchange() == broker.exchange(), "-wEx");
        Exchange(_pool.exchange()).withdrawCapital(_pool, _amount);
        emit WithdrawPoolTokens(address(_pool), _amount);}

    // governable parameters
    function setProtocolFee(uint256 _newFee) external onlyOwner(){ 
        protocolFee = _newFee;
        emit UpdateProtocolFees(_newFee);}
    function setProtocolRecipient(address _newAddress) external onlyOwner(){ 
        require(_newAddress != address(0), "0 address"); 
        protocolFeeRecipient = _newAddress;
        emit UpdateProtocolRecipient(_newAddress);}

    // update/add new volatility oracles
    function updateVolChain(address _underlyingAddress, VolatilityChain _newOracle) external onlyOwner{
        require(_underlyingAddress != address(0), "0addr");
        if(!underlyingList.contains(_underlyingAddress)){
            underlyingList.add(_underlyingAddress);}
        volatilityChainMap[_underlyingAddress] = _newOracle;}
        // emit UpdateToken( _underlyingAddress, address(_newOracle));}
    function getVolatilityChain(address _underlyingAddress) external view returns(VolatilityChain){
        require(address(volatilityChainMap[_underlyingAddress]) != address(0), "Oracle not registered");
        return volatilityChainMap[_underlyingAddress];}
    
    // update/get vol tokens.
    function updateVolToken(address _underlyingAddress, uint256 _tenor, VolatilityToken _volToken) external onlyOwner{ 
        require((_volToken.tenor() == _tenor) && (_volToken.underlying() == _underlyingAddress) && (_volToken.exchange() == broker.exchange()), '-vE'); // make sure the exchange address is allowed
        volatilityTokenMap[_underlyingAddress].set(_tenor, address(_volToken));}
        // emit UpdateVolToken(_underlyingAddress, _tenor, address(_volToken)); }
    function getVolatilityToken(address _underlyingAddress, uint256 _tenor) external view returns (VolatilityToken){
        (bool _success, address _volToken) = volatilityTokenMap[_underlyingAddress].tryGet(_tenor);
        require(_success, "no vol token");
        return VolatilityToken(_volToken);}
    
    // update eligible routes
    function updateEligibleRoute(address _route, bool _add) external onlyOwner returns(bool _result){
        require(_route != address(0), "empty address");
        if(_add) { _result = eligibleTradingRoutes.add(_route);}
        else{ _result = eligibleTradingRoutes.remove(_route);}}
        // emit UpdateRoute(_route, _add);}
    function existEligibleRoute(address _route) external view returns(bool){
        return eligibleTradingRoutes.contains(_route);}
    
    // update vol trading pool
    function updateVolTradingPool(address _poolAddress, bool _add) external onlyOwner returns(bool _result){
        require(_poolAddress != address(0), "empty address");
        if(_add) { _result = volTradingPools.add(_poolAddress);}
        else{ _result = volTradingPools.remove(_poolAddress);}}
        // emit UpdateVolTradingPool(_poolAddress, _add);}
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
