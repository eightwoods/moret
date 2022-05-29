// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./libraries/MarketLib.sol";
import "./libraries/OptionLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/EOption.sol";
import "./pools/Pool.sol";
import "./pools/MarketMaker.sol";
import "./VolatilityChain.sol";
import "./VolatilityToken.sol";

contract OptionVault is EOption, AccessControl{
  using MathLib for uint256;
  using MarketLib for uint256;
  
  using OptionLib for OptionLib.Option;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant EXCHANGE = keccak256("EXCHANGE");
  
  // list of option contracts
  OptionLib.Option[] internal aOption;
  mapping(address=>mapping(address=> EnumerableSet.UintSet)) internal mHolderAtiveOption;
  mapping(address=>EnumerableSet.UintSet) internal mActiveOption;
  // mapping(address=>uint256) public mActiveContractCount = 0;
  mapping(address=>int256) public mNetNotional;
  mapping(address=>uint256) public mPutCollateral;
  mapping(address=>uint256) public mDeltaAtZero;
  mapping(address=>uint256) public mDeltaAtMax;

  // immutable and constant values
  uint256 internal constant BASE  = 1e18;
  uint256 internal constant SCALING = 1e5;

  // constructor
  constructor(){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); }

  // function to add new option contracts, only executable by Exchange contract as owner
  // arguments: tenor of option contracts (in seconds), strike (consistent with price source decimals), amount (consistent with underlying token decimals), option type (call or put), option side (buy or sell), premium (in funding token decimals), cost (in funding token decimals), price (in price source decimals), volatility (in default decimals 18), holder address
  // return id of option contract
  function addOption(OptionLib.Option memory _option, uint256 _premium, uint256 _collateral, uint256 _price, uint256 _vol) external onlyRole(EXCHANGE) returns(uint256 _id){
    require(_option.tenor > 0, "Zero tenor");
    _id = aOption.length;
    // Arguments: option type, option side, contract status (default to draft), contract holder address, contract id, creation timestamp, effective timestamp (default to 0), tenor in seconds, maturity timestamp (default to 0), excersie timestamp (default to 0), amount or size of contract, current spot price, option strike, implied volatility, calculated premium and total cost including collaterals.
    aOption.push(OptionLib.Option(_option.poType, _option.side, OptionLib.OptionStatus.Draft, _option.holder, _id, block.timestamp,  0, _option.tenor, 0,  0, _option.amount, _price, _option.strike, _vol, _premium, _collateral, _option.pool));}

  // function to stamp option as an active contract, only executable by Exchange contract as owner
  // arguments: contract id and holder address
  function stampActiveOption(uint256 _id, address _holder) external onlyRole(EXCHANGE){
    // update Option records
    OptionLib.Option storage _option = aOption[_id];
    _option.effectiveTime = block.timestamp;
    _option.maturity = block.timestamp + _option.tenor;
    _option.status = OptionLib.OptionStatus.Active;
    
    // update ownership and exposure records
    address _poolAddress = _option.pool;
    mNetNotional[_poolAddress] += _option.getNetNotional();
    mPutCollateral[_poolAddress] += _option.sellPutCollateral();
    mDeltaAtZero[_poolAddress] += _option.calcDeltaAtZero();
    mDeltaAtMax[_poolAddress] += _option.calcDeltaAtMax();

    mHolderAtiveOption[_poolAddress][_holder].add(_id);
    mActiveOption[_poolAddress].add(_id);}

  // function to stamp option as an expired contract, only executable by Exchange contract as owner
  // arguments: contract id
  function stampExpiredOption(uint256 _id)  external onlyRole(EXCHANGE){
    // update Option records
    OptionLib.Option storage _option = aOption[_id];
    address _poolAddress = _option.pool;
    address _holder = _option.holder;
    mActiveOption[_poolAddress].remove(_id);
    mHolderAtiveOption[_poolAddress][_holder].remove(_id);

    mNetNotional[_poolAddress] -= _option.getNetNotional();
    mDeltaAtZero[_poolAddress] -= Math.min(mDeltaAtZero[_poolAddress], _option.calcDeltaAtZero());
    mDeltaAtMax[_poolAddress] -= Math.min(mDeltaAtMax[_poolAddress], _option.calcDeltaAtMax());
    mPutCollateral[_poolAddress] -= Math.min(mPutCollateral[_poolAddress], _option.sellPutCollateral());
   
    _option.status = OptionLib.OptionStatus.Expired;
    _option.exerciseTime = block.timestamp;}

  // functions to get information of the option list -> ONLY USED in VIEW, gas cost unlimited
  function getHolderOptions(address _pool, address _address) external view returns(uint256[] memory){
    return mHolderAtiveOption[_pool][_address].values();}
  function getOption(uint256 _id) external view returns(OptionLib.Option memory) {return aOption[_id];}
  function getActiveOptionCount(address _poolAddress) external view returns(uint256) {return mActiveOption[_poolAddress].length();}

  // function getHoldersOption(uint256 _index, address _address) external view returns(OptionLib.Option memory) {return aOption[activeOptionsPerOwner[_address].at(_index)];}
  function getOptionInfo(uint256 _id) external view returns(OptionLib.OptionStatus, OptionLib.OptionSide, address, Pool) {
    require(_id< aOption.length);
    return (aOption[_id].status, aOption[_id].side, aOption[_id].holder, Pool(aOption[_id].pool));}

  // functions to get the hedging inputs
  // maximum hedges needed 
  // function getMaxHedge(Pool _pool) external view returns (uint256){
  //   VolatilityChain _volChain = _pool.volChain();
  //   address _poolAddress = address(_pool);
  //   return Math.max(mDeltaAtZero[_poolAddress], mDeltaAtMax[_poolAddress]).ethmul(_volChain.queryPrice());}

  // aggregate delta of all active contracts, optional including expiring contracts yet stamped as Expired. Arguments: spot price and whether to include expiring contracts
  // function calculateAggregateDelta(address _pool, uint256 _price, bool _includeExpiring) public view returns(int256 _delta){
  //   _delta= 0;
  //   for(uint256 i=0;i<activeContractCount;i++){
  //     OptionLib.Option storage _option = aOption[uint256(activeOptions.at(i))];
  //     uint256 _maturityLeft = _option.calcRemainingMaturity();
  //     uint256 _vol = volChain.queryVol(_maturityLeft);
  //     _delta += _option.calcDelta(_price, _vol, _includeExpiring);}}
  
  // aggregate gamma. Arguments: spot price
  // function calculateAggregateGamma(address _pool, uint256 _price) external view returns(int256 _gamma){
  //   _gamma= 0;
  //   for(uint256 i=0;i<activeContractCount;i++){
  //     uint256 _id = uint256(activeOptions.at(i));
  //     if(aOption[_id].status== OptionLib.OptionStatus.Active  && (aOption[_id].maturity > block.timestamp)){
  //       uint256 _vol = volChain.queryVol(aOption[_id].maturity - block.timestamp);
  //       int256 _contractGamma = SafeCast.toInt256(OptionLib.calcGamma(_price, aOption[_id].strike, _vol).ethmul(aOption[_id].amount));
  //       if(aOption[_id].side==OptionLib.OptionSide.Sell){ _gamma -= _contractGamma;}
  //       else{_gamma += _contractGamma;}}}}

  // hypothetical gamma assuming at the money and 1-day expiry
  // function calculateSpotGamma() external view returns(int256 _gamma){
  //   uint256 _vol = volChain.queryVol(86400);
  //   _gamma = SafeCast.toInt256(OptionLib.calcGamma(BASE, BASE, _vol));}

  // functions used in expiring option contracts
  // contract payoff of specified contract ID
  function getContractPayoff(uint256 _id) external view returns(uint256 _payoff, uint256 _payback, uint256 _collateral){
    Pool _pool = Pool(aOption[_id].pool);
    VolatilityChain _volChain = _pool.marketMaker().getVolatilityChain();
    return aOption[_id].calcPayoff(_volChain.queryPrice());}
    
  // check if any option contract is expiring
  function anyOptionExpiring(address _poolAddress) external view returns(bool _isExpiring) {
    _isExpiring = false;
    uint256 _count = mActiveOption[_poolAddress].length();
    for(uint256 i=0;i<_count;i++){
      if(aOption[uint256(mActiveOption[_poolAddress].at(i))].isExpiring()){
        _isExpiring = true;
        break;}}}
  // get the id of any expiring contract -> please only run it on view function as it has unlimited gas usage.
  function getExpiringOptionId(address _poolAddress) external view returns(uint256 _id){
    // uint256[] memory _id;
    uint256 _count = mActiveOption[_poolAddress].length();
    for(uint256 i=0;i<_count;i++){
      uint256 _id_i = uint256(mActiveOption[_poolAddress].at(i));
      if(aOption[_id_i].isExpiring()){
        _id = _id_i;
        break;}}}

  function tryATMOptionCost(Pool _pool, uint256 _tenor, uint256 _amount, OptionLib.PayoffType _poType, OptionLib.OptionSide _side) public view returns(uint256 _premium, uint256 _collateral, uint256 _price, uint256 _volatilty){
    OptionLib.Option memory _option = OptionLib.Option(_poType, _side, OptionLib.OptionStatus.Draft, msg.sender, 0, block.timestamp,  0, _tenor, 0,  0, _amount, 0, 0, 0, 0, 0, address(_pool));
    return calcOptionCost(_option, true);
  }

  function calcOptionCost(OptionLib.Option memory _option, bool _forceATM) public view returns(uint256 _premium, uint256 _collateral, uint256 _price, uint256 _annualisedVol){
    Pool _pool = Pool(_option.pool);
    MarketMaker _market = _pool.marketMaker();

    int256 _newNetNotional = mNetNotional[_option.pool] + SafeCast.toInt256(_option.amount) * (_option.side==OptionLib.OptionSide.Sell? -1: int(1));
    uint256 _impVol; // vol * sqrt(t)
    (_price, _impVol, _annualisedVol) = calcImpliedVol(_market, _option.tenor, _pool.volCapacityFactor(), mNetNotional[_option.pool], _newNetNotional);
    
    if (_forceATM){_option.strike = _price;}

    _premium = _option.calcPremium(_price, _impVol, _market.loanInterest());
    _collateral = _option.calcCollateral();}

  function calcImpliedVol(MarketMaker _market, uint256 _tenor, uint256 _volCapacityFactor, int256 _currentNetNotional, int256 _newNetNotional) public view returns(uint256 _price, uint256 _impVol, uint256 _annualisedVol){
    VolatilityChain _volChain = _market.getVolatilityChain();
    _price = _volChain.queryPrice();
    _impVol = MarketLib.calcRiskPremium(MarketLib.getGrossCapital(_market, _price), _currentNetNotional, _newNetNotional, _volChain.queryVol(_tenor), _volCapacityFactor);
    _annualisedVol = _impVol.ethmul(_volChain.getSqrtRatio(_tenor));}
    
  // functions related to capital calculation, addition and removals
  // calculate capitals. Arguments: net for net capital (removing all collaterals and max exposures of option contracts) or gross (including all exposures in the underlying and funding tokens), average for average capital (total divided by number of Pool tokens) or gross (not divided by tokens)
  function calcCapital(Pool _pool, bool _net, bool _average) external view returns(uint256){
    MarketMaker _market = _pool.marketMaker();
    VolatilityChain _volChain = _market.getVolatilityChain();
    uint256 _price = _volChain.queryPrice();
    uint256 _capital = MarketLib.getGrossCapital(_market, _price);
    address _poolAddress = address(_pool);

    if(_net){ 
      uint256 _maxHedge = Math.max(mDeltaAtZero[_poolAddress], mDeltaAtMax[_poolAddress]).ethmul(_price);
      _capital -= Math.min(_maxHedge + mPutCollateral[_poolAddress], _capital);}

    if(_average){ 
      uint256 _poolSupply = _pool.totalSupply();
      if(_poolSupply > 0) {
        _capital = _capital.ethdiv(_poolSupply); }
      else if(_poolSupply == 0 && _capital == 0) {
        _capital = BASE;}}
    
    return _capital;}
}
