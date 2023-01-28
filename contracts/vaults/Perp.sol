// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Exchange.sol";
import "../OptionVault.sol";
import "../VolatilityChain.sol";
import "../pools/MarketMaker.sol";
import "../pools/Pool.sol";
import "../libraries/MathLib.sol";
import "../libraries/OptionLib.sol";
import "../libraries/MarketLib.sol";

contract Perp is ERC20, Ownable, ReentrancyGuard{
    using MathLib for uint256;
    using Math for uint256;
    using SafeCast for int256;
    using MarketLib for ERC20;
    using MarketLib for uint256;
    using OptionLib for OptionLib.Option;

    struct PerpParam{bool long; uint itm; uint itm2; uint leverage; uint criticalLev; uint penalty; uint tenor;}

    event PerpInvest(address investor, uint256 tokenUnit, uint256 investAmount);
    event PerpDivest(address investor, uint256 tokenUnit, uint256 divestAmount);
    event PerpRebalance(uint256 leverage, address bot);
    event PerpLiquidation(bool liquidation, address bot);

    uint256 public notional;
    uint256 public margin;
    uint256 public optionId;
    uint256 public optionEffective;
    uint256 public optionStrike;

    PerpParam public params;
    OptionLib.OptionSide public immutable optionSide = OptionLib.OptionSide.Buy;
    OptionLib.PaymentMethod public immutable optionPayment = OptionLib.PaymentMethod.USDC;

    VolatilityChain public immutable oracle;
    Exchange public immutable exchange;
    OptionVault public immutable vault;
    ERC20 public immutable funding;
    uint256 public immutable fundingDecimals;
    uint256 public immutable fundingMultiplier;
    Pool public immutable pool;
    MarketMaker public immutable market;

    uint256 internal constant SECONDS_1D = 86400;
    bool public liquidating = false;

    constructor(address _pool, string memory _name, string memory _symbol, PerpParam memory _params) ERC20(_name, _symbol){
        require(_pool != address(0), "null pool address");
        pool = Pool(_pool);

        exchange = Exchange(pool.exchange()); 
        vault = exchange.vault();
        market = pool.marketMaker();
        oracle = market.getVolatilityChain();
        funding = ERC20(market.funding());
        funding.increaseAllowance(address(exchange), 2**256 - 1);
        fundingDecimals = funding.decimals();
        fundingMultiplier = 10 ** fundingDecimals;
        optionEffective = block.timestamp;

        require(_params.itm > 0 && _params.itm2 > _params.itm, "error perp params");
        params = _params;
    }

    // invest amount of USDC: _investment in USDC decimals
    function invest(uint256 _investment) external nonReentrant{
        // unwind existing option
        if(optionId > 0){
            exchange.unwindOption(optionId);
        }
        uint256 _previousBalance = funding.balanceOf(address(this));
        uint256 _previousSupply = totalSupply();
        require(!(_previousSupply > 0 && _previousBalance == 0), "contract dead");

        // transfer in investment
        require(funding.transferFrom(msg.sender, address(this), _investment), 'invest error');

        // mint new tokens
        uint256 _newTokenAmount = _previousBalance > 0 ? _previousSupply.muldiv(_investment, _previousBalance): _investment.toWei(fundingDecimals);
        _mint(msg.sender, _newTokenAmount);

        // create options
        createOption();

        emit PerpInvest(msg.sender, _newTokenAmount, _investment);
    }

    // divest amount of USDC: _investment in USDC decimals
    function divest(uint256 _divestment) external nonReentrant{
        // unwind existing option
        if(optionId > 0){
            exchange.unwindOption(optionId);
        }
        uint256 _previousBalance = funding.balanceOf(address(this));
        uint256 _previousSupply = totalSupply();

        // burn tokens
        uint256 _burnTokenAmount = _previousSupply.muldiv(_divestment, _previousBalance).min(balanceOf(msg.sender));
        _burn(msg.sender, _burnTokenAmount);

        // transfer out divestment
        uint256 _redeemAmount = _previousBalance.muldiv(_burnTokenAmount, _previousSupply);
        require(funding.transfer(msg.sender, _redeemAmount), 'divest error');

        // create options
        createOption();

        emit PerpDivest(msg.sender, _burnTokenAmount, _redeemAmount);
    }

    // rebalance when leverage is below threshold
    function rebalance() external{
        // check bounds: can only reblance if leverage is below threshold
        uint256 _currentLev = getCurrentLeverage();
        if(_currentLev < params.criticalLev && !liquidating){
            // unwind existing option
            if(optionId > 0){
                exchange.unwindOption(optionId);
            }
            uint256 _previousBalance = funding.balanceOf(address(this));

            // collect incentives for rebalancer
            uint256 _incentive = _previousBalance.muldiv(block.timestamp - Math.min(block.timestamp, optionEffective), SECONDS_1D).ethmul(params.penalty);
            require(funding.transfer(msg.sender, _incentive), "penalty error");

            // create options
            createOption();

            emit PerpRebalance(_currentLev, msg.sender);
        }
    }

    function createOption() public {
        // calculate new trading notionals
        margin = funding.balanceDef(address(this));
        // it won't create new options if it's in liquidation phase (liquidating = true)
        if(margin > 0 && !liquidating){ 
            uint256 currentPrice = oracle.queryPrice();
            notional = margin.muldiv(params.leverage, currentPrice);
            optionStrike = params.long? currentPrice.ethmul(params.itm): currentPrice.ethdiv(params.itm);
            OptionLib.PayoffType _poType = params.long? OptionLib.PayoffType.Call: OptionLib.PayoffType.Put;
            
            // check notional
            (uint256 _premium,,,, uint256 _fee) = exchange.queryOption(pool, params.tenor, optionStrike, 0, notional, _poType, optionSide);
            if(_premium + _fee > margin){
                optionStrike = params.long? currentPrice.ethmul(params.itm2): currentPrice.ethdiv(params.itm2);
                (_premium,,,, _fee) = exchange.queryOption(pool, params.tenor, optionStrike, 0, notional, _poType, optionSide);
                if(_premium + _fee > margin){
                    notional = notional.muldiv(margin, _premium + _fee);
                }
            }

            // create options
            exchange.tradeOption(pool, params.tenor, optionStrike, 0, notional, _poType, optionSide, optionPayment);

            // register new id
            uint256[] memory _optionIdList = vault.getHolderOptions(address(pool), address(this));
            require(_optionIdList.length == 1, "wrong number of options");
            optionId = _optionIdList[0];
            optionEffective = block.timestamp;
        }
    }

    function getCurrentLeverage() public view returns(uint256 _leverage){
        // calculate delta
        if(optionId > 0){
            OptionLib.Option memory _option = vault.getOption(optionId);
            if(_option.status== OptionLib.OptionStatus.Active && (_option.maturity > block.timestamp)){
                uint256 _remainingTenor = _option.maturity - block.timestamp;
                uint256 _price = oracle.queryPrice();
                int256 _delta = _option.calcDelta(_price, oracle.queryVol(_remainingTenor)); // in 18 decimals
                require((_delta >= 0 && params.long) || (_delta <= 0 && !(params.long)), "wrong delta");

                // multiply delta by the price then divided by current pv
                uint256 _pv = getPV();
                _leverage = params.long? _delta.toUint256().muldiv(_price, _pv): (-_delta).toUint256().muldiv(_price, _pv);
            }
        }
    }

    // returns present value of the whole protocol
    function getPV() public view returns(uint256 _pv){
        // calculate unwind value, in funding token decimals
        if(optionId > 0){
            (uint256 _unwindValue, ) = vault.calcOptionUnwindValue(optionId);

            // add to remaining USDC
            uint256 _remainingBalance = funding.balanceDef(address(this));

            _pv = _unwindValue + _remainingBalance;
        }
    }

    // set the pool to be liquidating, only executable by owner
    // owner can't deal with any funds in the protocol but rather allow token holders to withdraw their funds when the liquidity pool can't support any more trades (so no rebalance would happen)
    function setLiquidation(bool _liquidating) external onlyOwner{
        liquidating = _liquidating;
        emit PerpLiquidation(liquidating, msg.sender);
    }
}