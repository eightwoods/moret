// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/EOption.sol";
import "./libraries/MathLib.sol";
import "./libraries/MarketLib.sol";
import "./libraries/OptionLib.sol";
import "./governance/Moret.sol";
import "./pools/Pool.sol";
import "./pools/MarketMaker.sol";
import "./OptionVault.sol";
import "./VolatilityToken.sol";

contract Exchange is Ownable, Pausable, EOption{
  using MarketLib for uint256;
  using MathLib for uint256;
  using SafeMath for uint256;

  event NewOption(address indexed _purchaser, address indexed _underlying, uint256 _optionId);

  // immutable addresses
  OptionVault public immutable vault;

  // contructor. Arguments: option vault and bot address
  constructor(OptionVault _optionVault){
    vault = _optionVault;}
  
  function queryOption(Pool _pool, uint256 _tenor, uint256 _strike, uint256 _spread, uint256 _amount, OptionLib.PayoffType _poType, OptionLib.OptionSide _side) external view returns(uint256 _premium, uint256 _collateral, uint256 _price, uint256 _volatility, int256 _exposure){
    OptionLib.Option memory _option = OptionLib.Option(_poType, _side, OptionLib.OptionStatus.Draft, msg.sender, 0, block.timestamp,  0, _tenor, 0,  0, _amount, 0, _strike, _spread, 0, 0, 0, address(_pool), 0);
    return vault.calcOptionCost(_option);}

  // functions to transact for option contracts
  // arguments: pool token address, tenor in seconds, strike in 18 decimals, amount in 18 decimals, payoff type (call 0 or put 1), option side (buy 0 or sell 1), payment methods 0-usdc/1-token/2-vol
  function tradeOption(Pool _pool, uint256 _tenor, uint256 _strike, uint256 _spread, uint256 _amount, OptionLib.PayoffType _poType, OptionLib.OptionSide _side, OptionLib.PaymentMethod _payment) external whenNotPaused{
    require(_pool.exchange() == address(this), "-Ex");
    OptionLib.Option memory _option = OptionLib.Option(_poType, _side, OptionLib.OptionStatus.Draft, msg.sender, 0, block.timestamp,  0, _tenor, 0,  0, _amount, 0, _strike, _spread, 0, 0, 0, address(_pool), 0);
    (uint256 _premium, uint256 _collateral, uint256 _price, uint256 _vol, int256 _exposure) = vault.calcOptionCost(_option);

    // transfer premiums
    if(_side == OptionLib.OptionSide.Buy){
      buyOption(_pool, msg.sender, _tenor, _premium, _price, _vol, _payment);
    }else {
      sellOption(_pool, msg.sender, _tenor, _premium, _collateral, _price, _vol, _payment);
    }

    uint256 _id = vault.addOption(_option, _premium, _collateral, _price, _vol, _exposure);
    vault.stampActiveOption(_id, msg.sender);

    emit NewOption(msg.sender, _pool.marketMaker().underlying(), _id);}

  function buyOption(Pool _pool, address _buyer, uint256 _tenor, uint256 _premium, uint256 _price, uint256 _vol, OptionLib.PaymentMethod _payment) internal {
    MarketMaker _marketMaker = _pool.marketMaker();
    ERC20 _funding = ERC20(_marketMaker.funding());
    uint256 _fundingDecimals = _funding.decimals();
    address _underlyingAddress = _marketMaker.underlying();
   
    if (_payment == OptionLib.PaymentMethod.Token){
      ERC20 _underlying = ERC20(_underlyingAddress);
      uint256 _decimals = _underlying.decimals();
      require(_underlying.transferFrom(_buyer, address(_marketMaker), _premium.ethdiv(_price).toDecimals(_decimals)), '-PM');}
    else if (_payment == OptionLib.PaymentMethod.Vol){
      VolatilityToken _vToken = _marketMaker.govToken().getVolatilityToken(_underlyingAddress, _tenor);
      (uint256 _volAmount, uint256 _volPrice) = _vToken.getBurnAmount(_premium, _vol);
      require(_volPrice > _pool.minVolPrice(), 'mVP');
      _vToken.burn(msg.sender, _volAmount);
      _vToken.pay(address(_marketMaker), _premium.toDecimals(_fundingDecimals));}
    else{
      require(_funding.transferFrom(_buyer, address(_marketMaker), _premium.toDecimals(_fundingDecimals)), '-PM');}
  }

  function sellOption(Pool _pool, address _buyer, uint256 _tenor, uint256 _premium, uint256 _collateral, uint256 _price, uint256 _vol, OptionLib.PaymentMethod _payment) internal {
    MarketMaker _marketMaker = _pool.marketMaker();
    ERC20 _funding = ERC20(_marketMaker.funding());
    uint256 _fundingDecimals = _funding.decimals();
    
    if (_payment == OptionLib.PaymentMethod.Token){
      ERC20 _underlying = ERC20(_marketMaker.underlying());
      uint256 _decimals = _underlying.decimals();
      require(_underlying.transferFrom(_buyer, address(_marketMaker), (_collateral - _premium).ethdiv(_price).toDecimals(_decimals)), '-PM');}
    else if (_payment == OptionLib.PaymentMethod.Vol){
      if(_collateral > 0){
        require(_funding.transferFrom(msg.sender, address(_marketMaker), _collateral.toDecimals(_fundingDecimals)), '-CM'); }
      VolatilityToken _vToken = _marketMaker.govToken().getVolatilityToken(_marketMaker.underlying(), _tenor);
      (uint256 _volAmount, ) = _vToken.getMintAmount(_premium, _vol);
      _marketMaker.settlePayment(address(_vToken), _premium.toDecimals(_fundingDecimals)); 
      _vToken.mint(msg.sender, _volAmount);}
    else{
      require(_funding.transferFrom(_buyer, address(_marketMaker), (_collateral - _premium).toDecimals(_fundingDecimals)), '-PM');}
    }

  // functions to transact volatility tokens (buy or sell)
  // arguments: pool token address, tenor in seconds, amount in 18 decimals, option side (buy 0 or sell 1)
  function tradeVolToken(Pool _pool, uint256 _tenor, uint256 _amount, OptionLib.OptionSide _side) external whenNotPaused{
    MarketMaker _marketMaker = _pool.marketMaker();
    require(_marketMaker.govToken().existVolTradingPool(address(_pool)), '-VP'); // only certified pools can trade vol
    VolatilityToken _vToken = _marketMaker.govToken().getVolatilityToken(_marketMaker.underlying(), _tenor);
    VolatilityChain _volChain = _marketMaker.getVolatilityChain();
    OptionLib.Option memory _option = OptionLib.Option(OptionLib.PayoffType.Put, _side, OptionLib.OptionStatus.Draft, msg.sender, 0, block.timestamp,  0, _tenor, 0,  0, _amount, 0, _volChain.queryPrice(), 0, 0, 0, 0, address(_pool), 0);

    ERC20 _funding = ERC20(_marketMaker.funding());
    uint256 _fundingDecimals = _funding.decimals();
    (uint256 _premium, , , uint256 _vol, ) = vault.calcOptionCost(_option); 
    
    uint256 _volAmount;
    if (_side == OptionLib.OptionSide.Buy){
      require(_funding.transferFrom(msg.sender, address(_vToken), _premium.toDecimals(_fundingDecimals)), "-VB");
      (_volAmount, ) = _vToken.getMintAmount(_premium, _vol);
      _vToken.mint(msg.sender, _volAmount);}
    else{
      (_volAmount, ) = _vToken.getBurnAmount(_premium, _vol);
      _vToken.burn(msg.sender, _volAmount);
      _vToken.pay(msg.sender, _premium.toDecimals(_fundingDecimals));}
    
    emit TradeVolatility(msg.sender, address(_pool), _amount, _volAmount, _side == OptionLib.OptionSide.Buy);}

  // get volatility token
  function getVolatilityToken(Pool _pool, uint256 _tenor) external view returns(VolatilityToken){
    MarketMaker _marketMaker = _pool.marketMaker();
    return _marketMaker.govToken().getVolatilityToken(_marketMaker.underlying(), _tenor);
  }

  // get volatility chain
  function getVolatilityChain(Pool _pool) external view returns(VolatilityChain){
    MarketMaker _marketMaker = _pool.marketMaker();
    return _marketMaker.getVolatilityChain();
  }

  // expire option contracts (one at a time), with exercise fees paid to the exercising bots.
  function expireOption(uint256 _expiringId, address _exerciseFeeRecipient) external {
    (OptionLib.OptionStatus _optionStatus, OptionLib.OptionSide _optionSide, address _optionHolder, Pool _pool) = vault.getOptionInfo(_expiringId);

    if(_optionStatus == OptionLib.OptionStatus.Active){
      vault.stampExpiredOption(_expiringId);
      (uint256 _payoff, uint256 _payback,) = vault.getContractPayoff(_expiringId);
      
      uint256 _fundingDecimals = ERC20(_pool.marketMaker().funding()).decimals();
      uint256 _protocolAmount = _payoff.ethmul(_pool.marketMaker().govToken().protocolFee()).toDecimals(_fundingDecimals);
      uint256 _exerciseAmount = _payoff.ethmul(_pool.exerciseFee()).toDecimals(_fundingDecimals);
      _payback = _payback.toDecimals(_fundingDecimals);

      if(_optionSide == OptionLib.OptionSide.Buy){
        _payback = _payback - Math.min(_payback, _protocolAmount + _exerciseAmount);}

      MarketMaker _marketMaker = MarketMaker(_pool.marketMaker());
      _marketMaker.settlePayment(_optionHolder, _payback);
      _marketMaker.settlePayment(_pool.marketMaker().govToken().protocolFeeRecipient(), _protocolAmount);
      _marketMaker.settlePayment(_exerciseFeeRecipient, _exerciseAmount);      
      emit Expire(msg.sender, address(this), _optionHolder, _expiringId, _payback);}}
  
  // add capital by depositing amount in funding tokens
  function addCapital(Pool _pool, uint256 _depositAmount) external whenNotPaused{
    uint256 _averageGrossCapital = vault.calcCapital(_pool, false, true);
    ERC20 _funding = ERC20(_pool.marketMaker().funding());
    uint256 _mintPoolAmount = _depositAmount.toWei(_funding.decimals()).ethdiv(_averageGrossCapital);
    require(_funding.transferFrom(msg.sender, address(_pool.marketMaker()), _depositAmount));
    _pool.mint(msg.sender, _mintPoolAmount);}

  // remove capital by withdrawing amount in funding tokens
  function withdrawCapital(Pool _pool, uint256 _burnPoolAmount) external whenNotPaused{
    uint256 _averageNetCapital = vault.calcCapital(_pool, true, true);
    uint256 _withdrawValue = _averageNetCapital.ethmul(_burnPoolAmount).toDecimals(ERC20(_pool.marketMaker().funding()).decimals()); 
    _pool.burn(msg.sender, _burnPoolAmount);
    _pool.marketMaker().settlePayment(msg.sender, _withdrawValue);}

  function pause() external onlyOwner{
    _pause();
  }

  function unpause() external onlyOwner{
    _unpause();
  }
}
