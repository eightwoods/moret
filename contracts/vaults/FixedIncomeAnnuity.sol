// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Exchange.sol";
import "../OptionVault.sol";
import "../VolatilityChain.sol";
import "../pools/MarketMaker.sol";
import "../pools/Pool.sol";
import "../libraries/MathLib.sol";
import "../libraries/OptionLib.sol";

contract FixedIncomeAnnuity is Ownable, ERC20, ReentrancyGuard{
    using MathLib for uint256;
    using Math for uint256;
    using SafeERC20 for ERC20;

    struct FIAParam{uint256 callMoney; uint256 callTenor; uint256 putMoney; uint256 putTenor; uint256 putSpread; uint256 tradeWindow; uint256 leverage; uint256 multiplier;}
    struct VintageStats{uint256 optionAmount; uint256 callStrike; uint256 putStrike; uint256 putSpread; uint256 startLevel; uint256 startNAV;}

    event FIPInvest(address investor, uint256 tokenUnit, uint256 investAmount);
    event FIPDivest(address investor, uint256 tokenUnit, uint256 divestAmount);
    event FIPRoll(uint256 time, uint256 rebTime, bool isRoll);

    VolatilityChain public immutable oracle;
    Exchange public immutable exchange;
    ERC20 public immutable funding;
    uint256 public immutable fundingMultiplier;
    Pool public pool;

    FIAParam public fiaParams;
    VintageStats public vintage;

    uint256 public nextRebTime; // next time for new option contracts
    uint256 public nextVintageTime; // next time for new vintage

    constructor(address _pool, string memory _name, string memory _symbol, FIAParam memory _params) ERC20(_name, _symbol){
        require(_pool != address(0), "null pool address");
        pool = Pool(_pool);

        exchange = Exchange(pool.exchange()); 

        MarketMaker market = pool.marketMaker();
        oracle = market.getVolatilityChain();
        
        funding = ERC20(market.funding());
        funding.increaseAllowance(address(exchange), 2**256 - 1);
        uint256 fundingDecimals = funding.decimals();
        fundingMultiplier = 10 ** fundingDecimals;

        nextRebTime = block.timestamp;
        nextVintageTime = block.timestamp;

        require(_params.callMoney >= _params.multiplier && _params.putMoney <= _params.multiplier && _params.putSpread < _params.putMoney, "Wrong strikes");
        require(_params.callTenor % _params.putTenor == 0 || _params.putTenor % _params.callTenor == 0, "Wrong tenors");
        fiaParams = _params;
    }

    function setParameters(FIAParam memory _params) external onlyOwner {
        require(_params.callMoney >= _params.multiplier && _params.putMoney <= _params.multiplier && _params.putSpread < _params.putMoney, "Wrong strikes");
        require(_params.callTenor % _params.putTenor == 0 || _params.putTenor % _params.callTenor == 0, "Wrong tenors");
        fiaParams = _params;
    }

    // invest function to deposit USDC
    // _toInvest: amount of USDC to invest during the investment window
    function invest(uint256 _toInvest) external nonReentrant{
        uint256 unitAsset = getRollsUnitAsset();
        uint256 unitToMint = _toInvest.ethdiv(unitAsset);

        funding.safeTransferFrom(msg.sender, address(this), _toInvest);
        _mint(msg.sender, unitToMint);
        emit FIPInvest(msg.sender, unitToMint, _toInvest);
    }
    
    // invest function to withdraw USDC
    // _toDivest: amount of FIP tokens to divest (by withdrawing corresponding amount of USDC) during the investment window
    function divest(uint256 _toDivest) external nonReentrant{
        uint256 unitAsset = getRollsUnitAsset();
        uint256 assetToDivest = _toDivest.ethmul(unitAsset);

        require(balanceOf(msg.sender) >= _toDivest, "Exceed total balance");
        require(funding.balanceOf(address(this)) >= assetToDivest, "Insufficient funding");
        _burn(msg.sender, _toDivest);
        funding.safeTransfer(msg.sender, assetToDivest);
        emit FIPDivest(msg.sender, _toDivest, assetToDivest);
    }

    function getRollsUnitAsset() public view returns(uint256 unitAsset){
        require(block.timestamp >= nextVintageTime, "Invest is unavailable.");
        uint256[] memory options = exchange.vault().getHolderOptions(address(pool), address(this));
        require(options.length == 0, "options yet active");

        uint256 currentAssets = funding.balanceOf(address(this));
        uint256 currentSupply = this.totalSupply();
        if(currentSupply>0){
            unitAsset = currentAssets.ethdiv(currentSupply);
        }
        else{
            unitAsset = fundingMultiplier;
        }
    }

    function rollover() external{
        require(block.timestamp >= (nextVintageTime + fiaParams.tradeWindow), "pdRolls");
        uint256 unitAsset = getRollsUnitAsset();
        require(unitAsset> 0, "0asset");
        vintage.startNAV = unitAsset;

        uint256 currentAssets = funding.balanceOf(address(this)).ethdiv(fundingMultiplier);
        uint256 currentPrice = oracle.queryPrice();
        vintage.startLevel = currentPrice;
        vintage.optionAmount = currentAssets.ethdiv(currentPrice).muldiv(fiaParams.leverage, fiaParams.multiplier);

        // sell call
        vintage.callStrike = currentPrice.muldiv(fiaParams.callMoney, fiaParams.multiplier);
        exchange.tradeOption(pool, fiaParams.callTenor, vintage.callStrike, 0, vintage.optionAmount, OptionLib.PayoffType.Call, OptionLib.OptionSide.Sell, OptionLib.PaymentMethod.USDC);

        // buy put
        vintage.putStrike = currentPrice.muldiv(fiaParams.putMoney, fiaParams.multiplier);
        if(fiaParams.putSpread > 0){
            vintage.putSpread = currentPrice.muldiv(fiaParams.putMoney - fiaParams.putSpread, fiaParams.multiplier);
            exchange.tradeOption(pool, fiaParams.putTenor, vintage.putStrike, vintage.putSpread, vintage.optionAmount, OptionLib.PayoffType.PutSpread, OptionLib.OptionSide.Buy, OptionLib.PaymentMethod.USDC);
        }
        else{
            exchange.tradeOption(pool, fiaParams.putTenor, vintage.putStrike, 0, vintage.optionAmount, OptionLib.PayoffType.Put, OptionLib.OptionSide.Buy, OptionLib.PaymentMethod.USDC);
        }
        
        nextRebTime = block.timestamp + fiaParams.callTenor.min(fiaParams.putTenor);
        nextVintageTime = block.timestamp + fiaParams.callTenor.max(fiaParams.putTenor);

        emit FIPRoll(block.timestamp, nextVintageTime, true);
    }

    function rebalance() external {
        require(block.timestamp >= nextRebTime && block.timestamp < nextVintageTime, "Not for rebalance");
        uint256 currentPrice = oracle.queryPrice();
        if(fiaParams.callTenor > fiaParams.putTenor){
            require(vintage.putStrike > 0, "Put strike unset");
            nextRebTime = (nextRebTime + fiaParams.putTenor).min(nextVintageTime);
            require(nextRebTime > block.timestamp, "put expiry in the past");
            uint256 tenor = nextRebTime - block.timestamp;
            uint256 strike = currentPrice.muldiv(fiaParams.putMoney, fiaParams.multiplier).min(vintage.putStrike);
            
            if(fiaParams.putSpread > 0){
                uint256 spread = strike.muldiv(fiaParams.putMoney - fiaParams.putSpread, fiaParams.putMoney);
                exchange.tradeOption(pool, tenor, strike, spread, vintage.optionAmount, OptionLib.PayoffType.PutSpread, OptionLib.OptionSide.Buy, OptionLib.PaymentMethod.USDC);
            }
            else{
                exchange.tradeOption(pool, tenor, strike, 0, vintage.optionAmount, OptionLib.PayoffType.Put, OptionLib.OptionSide.Buy, OptionLib.PaymentMethod.USDC);
            }
        }
        else if (fiaParams.callTenor < fiaParams.putTenor){
            require(vintage.callStrike > 0, "Call strike unset");
            nextRebTime = (nextRebTime + fiaParams.callTenor).min(nextVintageTime);
            require(nextRebTime > block.timestamp, "call expiry in the past");

            uint256 tenor = nextRebTime - block.timestamp;
            uint256 strike = currentPrice.muldiv(fiaParams.callMoney, fiaParams.multiplier).max(vintage.callStrike);

            uint256 currentAssets = funding.balanceOf(address(this)).ethdiv(fundingMultiplier);
            uint256 callOptionAmount = currentAssets.ethdiv(currentPrice).min(vintage.optionAmount);

            exchange.tradeOption(pool, tenor, strike, 0, callOptionAmount, OptionLib.PayoffType.Call, OptionLib.OptionSide.Sell, OptionLib.PaymentMethod.USDC);
        }

        emit FIPRoll(block.timestamp, nextRebTime, false);
    }


}