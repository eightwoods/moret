// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

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
  using MathLib for int256;
  using MarketLib for uint256;
  using MarketLib for MarketMaker;
  
  using OptionLib for OptionLib.Option;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant EXCHANGE = keccak256("EXCHANGE");
  
  // list of option contracts
  OptionLib.Option[] internal aOption;
  mapping(address=>mapping(address=> EnumerableSet.UintSet)) internal mHolderAtiveOption;
  mapping(address=>EnumerableSet.UintSet) internal mActiveOption;
  mapping(address=>uint256) public mUnderCollateral;
  mapping(address=>uint256) public mFundCollateral;
  mapping(address=>int256) public mExposureUp;
  mapping(address=>int256) public mExposureDown;

  // immutable and constant values
  uint256 internal constant BASE  = 1e18;
  uint256 internal constant SCALING = 1e5;

  // constructor
  constructor(){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); }

  // function to add new option contracts, only executable by Exchange contract as owner
  // arguments: option contracts (in struct), premium (in funding token decimals), collateral (in funding token decimals), price (in price source decimals), volatility (in default decimals 18)
  // return id of option contract
  function addOption(OptionLib.Option memory _option, uint256 _premium, uint256 _collateral, uint256 _price, uint256 _vol, int256 _exposure) external onlyRole(EXCHANGE) returns(uint256 _id){
    require(_option.tenor > 0, "Zero tenor");
    _id = aOption.length;
    
    // Arguments: option type, option side, contract status (default to draft), contract holder address, contract id, creation timestamp, effective timestamp (default to 0), tenor in seconds, maturity timestamp (default to 0), excersie timestamp (default to 0), amount or size of contract, current spot price, option strike, implied volatility, calculated premium and total cost including collaterals.
    aOption.push(OptionLib.Option(_option.poType, _option.side, OptionLib.OptionStatus.Draft, _option.holder, _id, block.timestamp,  0, _option.tenor, 0,  0, _option.amount, _price, _option.strike, _option.spread, _vol, _premium, _collateral, _option.pool, _exposure));}

  // function to stamp option as an active contract, only executable by Exchange contract as owner
  // arguments: contract id and holder address
  function stampActiveOption(uint256 _id, address _holder) external onlyRole(EXCHANGE){
    require(_holder != address(0), "0addr"); 

    // update Option records
    OptionLib.Option storage _option = aOption[_id];
    _option.effectiveTime = block.timestamp;
    _option.maturity = block.timestamp + _option.tenor;
    _option.status = OptionLib.OptionStatus.Active;
    
    // update ownership and exposure records
    address _poolAddress = _option.pool;
    mUnderCollateral[_poolAddress] += _option.getUnderCollateral();
    mFundCollateral[_poolAddress] += _option.sellFundCollateral();
    if(_option.poType == OptionLib.PayoffType.Call || _option.poType == OptionLib.PayoffType.CallSpread){
      mExposureUp[_poolAddress] += _option.exposure;}
    else{
      mExposureDown[_poolAddress] += _option.exposure;}

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

    mUnderCollateral[_poolAddress] -= Math.min(mUnderCollateral[_poolAddress], _option.getUnderCollateral());
    mFundCollateral[_poolAddress] -= Math.min(mFundCollateral[_poolAddress], _option.sellFundCollateral());

    if(_option.poType == OptionLib.PayoffType.Call || _option.poType == OptionLib.PayoffType.CallSpread){
      mExposureUp[_poolAddress] -= _option.exposure;}
    else{
      mExposureDown[_poolAddress] -= _option.exposure;}
   
    _option.status = OptionLib.OptionStatus.Expired;
    _option.exerciseTime = block.timestamp;}

  // functions to get information of the option list -> ONLY USED in VIEW, gas cost unlimited
  function getHolderOptions(address _pool, address _address) external view returns(uint256[] memory){
    return mHolderAtiveOption[_pool][_address].values();}
  function getOption(uint256 _id) external view returns(OptionLib.Option memory) {return aOption[_id];}
  function getActiveOptionCount(address _poolAddress) public view returns(uint256) {return mActiveOption[_poolAddress].length();}
  function getActiveOptions(address _poolAddress) external view returns(uint256[] memory) {return mActiveOption[_poolAddress].values();}

  function getOptionInfo(uint256 _id) external view returns(OptionLib.OptionStatus, OptionLib.OptionSide, address, Pool) {
    require(_id< aOption.length, '-ID');
    return (aOption[_id].status, aOption[_id].side, aOption[_id].holder, Pool(aOption[_id].pool));}

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

  function calcOptionCost(OptionLib.Option memory _option) external view returns(uint256 _premium, uint256 _collateral, uint256 _price, uint256 _annualisedVol, int256 _exposure){
    _price = getPrice(_option);
    (uint256 _volT, uint256 _maxExposure, uint256 _sqrt, uint256 _interest) = getOptionParams(_option);
    
    uint256 _impVol;
    if(_option.poType == OptionLib.PayoffType.Call || _option.poType == OptionLib.PayoffType.CallSpread){
      (_impVol, _exposure) = calcCallOptionCost(_option, _price, _volT, _maxExposure);
    }
    else{
      (_impVol, _exposure) = calcPutOptionCost(_option, _price, _volT, _maxExposure);
    }
    _annualisedVol = _impVol.ethmul(_sqrt);
    _premium = _option.calcPremium(_price, _impVol, _interest);
    _collateral = _option.calcCollateral(_price, _premium);
  }

  function getPrice(OptionLib.Option memory _option) public view returns (uint256 _price){
    Pool _pool = Pool(_option.pool);
    return _pool.marketMaker().getVolatilityChain().queryPrice();
  }

  function getOptionParams(OptionLib.Option memory _option) public view returns(uint256 _vol, uint256 _maxExposure, uint256 _sqrt, uint256 _interest){
    Pool _pool = Pool(_option.pool);
    MarketMaker _market = _pool.marketMaker();
    VolatilityChain _volChain = _market.getVolatilityChain();
    return (_volChain.queryVol(_option.tenor), calcCapital(_pool, false, false), _volChain.getSqrtRatio(_option.tenor), _market.loanInterest());
  }

  function calcCallOptionCost(OptionLib.Option memory _option, uint256 _price, uint256 _volT, uint256 _maxExposure) public view returns(uint256 _impVol, int256 _exposureUp){
    Pool _pool = Pool(_option.pool);
    uint256 _exposureSigma = _pool.exposureSigma();
    uint256 _capacityFactor = _pool.volCapacityFactor();
    uint256 _priceUp = _price.ethmul(BASE + _volT.ethmul(_exposureSigma));
    int256 _currentExposure = mExposureUp[_option.pool];
    (_impVol, _exposureUp) = _option.quoteCallVol(_priceUp, _volT, _capacityFactor, _currentExposure , _maxExposure );  
  }

  function calcPutOptionCost(OptionLib.Option memory _option, uint256 _price, uint256 _volT, uint256 _maxExposure) public view returns(uint256 _impVol, int256 _exposureDown){
    Pool _pool = Pool(_option.pool);
    uint256 _exposureSigma = _pool.exposureSigma();
    uint256 _capacityFactor = _pool.volCapacityFactor();
    uint256 _priceDown = _price.ethdiv(BASE + _volT.ethmul(_exposureSigma));
    int256 _currentExposure = mExposureDown[_option.pool];
    (_impVol, _exposureDown) = _option.quotePutVol(_priceDown, _volT, _capacityFactor, _currentExposure, _maxExposure);  
  }
    
  // functions related to capital calculation, addition and removals
  // calculate capitals. Arguments: pool address, net for net capital (removing all collaterals and max exposures of option contracts) or gross (including all exposures in the underlying and funding tokens), average for average capital (total divided by number of Pool tokens) or gross (not divided by tokens)
  function calcCapital(Pool _pool, bool _net, bool _average) public view returns(uint256){
    MarketMaker _market = _pool.marketMaker();
    VolatilityChain _volChain = _market.getVolatilityChain();
    uint256 _price = _volChain.queryPrice();
    uint256 _capital = _market.getGrossCapital(_price);

    address _poolAddress = address(_pool);
    uint256 _collateral = mUnderCollateral[_poolAddress].ethmul(_price) + mFundCollateral[_poolAddress];
    _capital -= Math.min(_collateral, _capital);
    

    if(_net){ 
      uint256 _exposure = mExposureUp[_poolAddress].absmax(-mExposureDown[_poolAddress]).ethmul(_price);
      _capital -= Math.min(_exposure, _capital);}

    if(_average){ 
      uint256 _poolSupply = _pool.totalSupply();
      if(_poolSupply > 0) {
        _capital = _capital.ethdiv(_poolSupply); }
      else if(_poolSupply == 0 && _capital == 0) {
        _capital = BASE;}}
    
    return _capital;}
}
