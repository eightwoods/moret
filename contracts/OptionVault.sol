// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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

  bytes32 public constant EXCHANGE = keccak256("EXCHANGE");
  
  // list of option contracts
  OptionLib.Option[] internal aOption;
  mapping(address=>mapping(address=> EnumerableSet.UintSet)) internal mHolderAtiveOption;
  mapping(address=>EnumerableSet.UintSet) internal mActiveOption;
  mapping(address=>uint256) public mUnderCollateral;
  mapping(address=>uint256) public mFundCollateral;
  mapping(address=>uint256) public mShortPremiums;
  mapping(address=>int256) public mExposureUp;
  mapping(address=>int256) public mExposureDown;

  // immutable and constant values
  uint256 internal constant BASE  = 1e18;
  uint256 internal constant SCALING = 1e5;
  uint256 internal constant SECONDS_1Y = 31536000; // 86400 * 365

  // constructor
  constructor(){
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); }
  
  // functions to get information of the option list -> ONLY USED in VIEW, gas cost unlimited
  function getHolderOptions(address _pool, address _address) external view returns(uint256[] memory){
    return mHolderAtiveOption[_pool][_address].values();}
  function getOption(uint256 _id) public view returns(OptionLib.Option memory) {return aOption[_id];}
  function getActiveOptionCount(address _poolAddress) public view returns(uint256) {return mActiveOption[_poolAddress].length();}
  function getActiveOptions(address _poolAddress) external view returns(uint256[] memory) {return mActiveOption[_poolAddress].values();}

  function getOptionInfo(uint256 _id) external view returns(OptionLib.OptionStatus, uint256, address, Pool) {
    require(_id< aOption.length, '-ID');
    return (aOption[_id].status, aOption[_id].maturity, aOption[_id].holder, Pool(aOption[_id].pool));}

  // function to add new option contracts, only executable by Exchange contract as owner
  // arguments: option contracts (in struct), premium (in funding token decimals), collateral (in funding token decimals), price (in price source decimals), volatility (in default decimals 18)
  // return id of option contract
  function addOption(OptionLib.Option memory _option, uint256 _premium, uint256 _collateral, uint256 _price, uint256 _vol, uint256 _fee) external onlyRole(EXCHANGE) returns(uint256 _id){
    require(_option.tenor > 0, "Zero tenor");
    _id = aOption.length;
    Pool _pool = Pool(_option.pool);
    VolatilityChain _volChain = _pool.marketMaker().getVolatilityChain();
    (, int256 _exposure) = calcOptionExposure(_option, _price, _volChain.queryVol(_option.tenor), calcCapital(_pool, false, false).ethdiv(_price));
    
    // Arguments: option type, option side, contract status (default to draft), contract holder address, contract id, creation timestamp, effective timestamp (default to 0), tenor in seconds, maturity timestamp (default to 0), excersie timestamp (default to 0), amount or size of contract, current spot price, option strike, implied volatility, calculated premium and total cost including collaterals.
    aOption.push(OptionLib.Option(_option.poType, _option.side, OptionLib.OptionStatus.Draft, _option.holder, _id, block.timestamp,  0, _option.tenor, 0,  0, _option.amount, _price, _option.strike, _option.spread, _vol, _premium, _collateral, _option.pool, _exposure, _fee));}

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
    mShortPremiums[_poolAddress] += _option.side == OptionLib.OptionSide.Sell? _option.premium: 0;

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
    mShortPremiums[_poolAddress] -= Math.min(mShortPremiums[_poolAddress], _option.side == OptionLib.OptionSide.Sell? _option.premium: 0);

    if(_option.poType == OptionLib.PayoffType.Call || _option.poType == OptionLib.PayoffType.CallSpread){
      mExposureUp[_poolAddress] -= _option.exposure;}
    else{
      mExposureDown[_poolAddress] -= _option.exposure;}
   
    _option.status = (msg.sender == _option.holder)? OptionLib.OptionStatus.Exercised: OptionLib.OptionStatus.Expired;
    _option.exerciseTime = block.timestamp;
  }

  // contract payoff of specified contract ID
  function getContractPayoff(uint256 _id) external view returns(uint256 _toHolder, uint256 _toProtocol, uint256 _toExerciser){
    Pool _pool = Pool(aOption[_id].pool);
    VolatilityChain _volChain = _pool.marketMaker().getVolatilityChain();
    uint256 _price = _volChain.queryPrice();
    
    _toHolder = aOption[_id].calcPayoff(_price);
    _toProtocol = aOption[_id].fee;
    _toExerciser = aOption[_id].amount.ethmul(_price).muldiv(aOption[_id].tenor, SECONDS_1Y).ethmul(_pool.exerciseFee());
    
    if(aOption[_id].side == OptionLib.OptionSide.Buy){
      _toHolder = _toHolder - Math.min(_toHolder, _toExerciser);
    }
  }

  // contract unwind value of specified contract ID. no exerciser as only holder can unwind exiting contract
  function calcOptionUnwindValue(uint256 _id) external view returns(uint256 _toHolder, uint256 _toProtocol){
    OptionLib.Option memory _option = getOption(_id);
    bool isBuyOption = _option.side == OptionLib.OptionSide.Buy;
    _option.side = isBuyOption? OptionLib.OptionSide.Sell: OptionLib.OptionSide.Buy;
    
    (uint256 _premium, , uint256 _price , , ) = calcOptionCost(_option);
    uint256 _feeProrata = _option.fee.muldiv(((_option.effectiveTime > 0) && (_option.maturity > _option.effectiveTime)) ? Math.min(_option.tenor, Math.max(block.timestamp, _option.maturity) - _option.effectiveTime): _option.tenor, _option.tenor);

    _toHolder = isBuyOption? _premium: (_option.calcCollateral(_price, _premium) - _premium ); // collateral for buy backs
    _toHolder = _toHolder + _option.fee - _feeProrata;
    _toProtocol = _feeProrata;
  }

  function calcOptionCost(OptionLib.Option memory _option) public view returns(uint256 _premium, uint256 _collateral, uint256 _price, uint256 _annualisedVol, uint256 _fee){
    Pool _pool = Pool(_option.pool);
    MarketMaker _market = _pool.marketMaker();
    VolatilityChain _volChain = _market.getVolatilityChain();
    _price = _volChain.queryPrice();

    (uint256 _impVol, ) = calcOptionExposure(_option, _price, _volChain.queryVol(_option.tenor), calcCapital(_pool, false, false).ethdiv(_price));
    
    _annualisedVol = _impVol.ethmul(_volChain.getSqrtRatio(_option.tenor));
    _premium = _option.calcPremium(_price, _impVol, _market.loanInterest());
    _collateral = _option.side == OptionLib.OptionSide.Sell? _option.calcCollateral(_price, _premium): 0;
    _fee = _option.amount.ethmul(_price).muldiv(_option.tenor, SECONDS_1Y).ethmul(_market.govToken().protocolFee());
  }

  function calcOptionExposure(OptionLib.Option memory _option, uint256 _price, uint256 _volT, uint256 _maxExposure) public view returns(uint256, int256){
    Pool _pool = Pool(_option.pool);
    uint256 _exposureSigma = _pool.exposureSigma();
    uint256 _capacityFactor = _pool.volCapacityFactor();
    if(_option.poType == OptionLib.PayoffType.Call || _option.poType == OptionLib.PayoffType.CallSpread){
      uint256 _priceAfter = _price.ethmul(BASE + _volT.ethmul(_exposureSigma));
      int256 _currentExposure = mExposureUp[_option.pool];
      return _option.quoteCallVol(_priceAfter, _volT, _capacityFactor, _currentExposure , _maxExposure);  
    }
    else{
      uint256 _priceAfter = _price.ethdiv(BASE + _volT.ethmul(_exposureSigma));
      int256 _currentExposure = mExposureDown[_option.pool];
      return _option.quotePutVol(_priceAfter, _volT, _capacityFactor, _currentExposure, _maxExposure);  
    }
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
    _capital = _capital - Math.min(_collateral, _capital) + mShortPremiums[_poolAddress];
    
    if(_net){ 
      uint256 _exposure = mExposureUp[_poolAddress].absmax(-mExposureDown[_poolAddress]).ethmul(_price);
      _capital -= Math.min(_exposure, _capital);}

    if(_average){ 
      uint256 _poolSupply = _pool.totalSupply();
      if(_poolSupply > 0) {
        _capital = _capital.ethdiv(_poolSupply); }
      else if(_poolSupply == 0 && _capital == 0) {
        _capital = BASE;}}
    
    return _capital;
  }
}
