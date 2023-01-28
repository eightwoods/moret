// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

contract Exchange is EOption {
    using MarketLib for uint256;
    using MathLib for uint256;
    using SafeMath for uint256;

    event NewOption(
        address indexed _purchaser,
        address indexed _underlying,
        uint256 _optionId
    );

    // immutable addresses
    OptionVault public immutable vault;

    // contructor. Arguments: option vault and bot address
    constructor(OptionVault _optionVault) {
        vault = _optionVault;
    }

    function queryOption(
        Pool _pool,
        uint256 _tenor,
        uint256 _strike,
        uint256 _spread,
        uint256 _amount,
        OptionLib.PayoffType _poType,
        OptionLib.OptionSide _side
    )
        external
        view
        returns (
            uint256 _premium,
            uint256 _collateral,
            uint256 _price,
            uint256 _volatility,
            uint256 _fee
        )
    {
        OptionLib.Option memory _option = OptionLib.Option(
            _poType,
            _side,
            OptionLib.OptionStatus.Draft, // status
            msg.sender, // holder
            0, // id
            block.timestamp, // create time
            0, // effective time
            _tenor, // tenor
            0, // maturity
            0, // exercise
            _amount, // amount or  notional
            0, // spot price
            _strike,
            _spread,
            0, // implied volatility
            0, // premium paid
            0, // collateral
            address(_pool),
            0, // exposure
            0 // fee
        );
        return vault.calcOptionCost(_option);
    }

    // functions to transact for option contracts
    // arguments: pool token address, tenor in seconds, strike in 18 decimals, amount in 18 decimals, payoff type (call 0 or put 1), option side (buy 0 or sell 1), payment methods 0-usdc/1-token/2-vol
    function tradeOption(
        Pool _pool,
        uint256 _tenor,
        uint256 _strike,
        uint256 _spread,
        uint256 _amount,
        OptionLib.PayoffType _poType,
        OptionLib.OptionSide _side,
        OptionLib.PaymentMethod _payment
    ) external {
        require(_pool.exchange() == address(this), "-Ex");
        OptionLib.Option memory _option = OptionLib.Option(
            _poType,
            _side,
            OptionLib.OptionStatus.Draft, // status
            msg.sender, // holder
            0, // id
            block.timestamp, // create time
            0, // effective time
            _tenor,
            0, // maturity
            0, // exercise
            _amount, // amount or notional
            0, // spot price
            _strike,
            _spread,
            0, // implied volatility
            0, // premium paid
            0, // collateral
            address(_pool),
            0, // exposure
            0 // fee
        );
        (
            uint256 _premium,
            uint256 _collateral,
            uint256 _price,
            uint256 _vol,
            uint256 _fee
        ) = vault.calcOptionCost(_option);

        // transfer premiums
        MarketMaker _marketMaker = _pool.marketMaker();
        if(_payment == OptionLib.PaymentMethod.Vol){
            if(_collateral + _fee > 0){
                ERC20 _funding = ERC20(_marketMaker.funding());
                require(_funding.transferFrom(msg.sender, address(_marketMaker), (_collateral + _fee).toDecimals(_funding.decimals())), '-CM'); 
            }
            tradeOptionInVol(_pool, _tenor, _premium, _vol, _side);
        }
        else{
          ERC20 _paymentToken = _payment == OptionLib.PaymentMethod.Token? ERC20(_marketMaker.underlying()): ERC20(_marketMaker.funding());
          uint256 _paymentAmount = _side == OptionLib.OptionSide.Buy ? _fee + _premium:  _collateral + _fee - _premium;
          _paymentAmount = _payment == OptionLib.PaymentMethod.Token? _paymentAmount.ethdiv(_price).toDecimals(_paymentToken.decimals()) : _paymentAmount.toDecimals(_paymentToken.decimals());
          require(
                _paymentToken.transferFrom(
                    msg.sender,
                    address(_marketMaker),
                    _paymentAmount
                ),
                "-Premium"
            );
        }

        uint256 _id = vault.addOption(
            _option,
            _premium, // always in USD
            _collateral, // always in USD
            _price,
            _vol, // annualised vol
            _fee
        );
        vault.stampActiveOption(_id, msg.sender);

        emit NewOption(msg.sender, _pool.marketMaker().underlying(), _id);
    }

    function tradeOptionInVol(Pool _pool, uint256 _tenor, uint256 _premium, uint256 _vol, OptionLib.OptionSide _side) internal{
      MarketMaker _marketMaker = _pool.marketMaker();
      VolatilityToken _vToken = _marketMaker
                .govToken()
                .getVolatilityToken(_marketMaker.underlying(), _tenor);
      uint256 _fundingDecimals = _vToken.funding().decimals();
      (uint256 _volAmount, uint256 _volPrice) = _vToken.calcAmount(_premium, _vol, _side==OptionLib.OptionSide.Sell);
      require(_volPrice > _pool.minVolPrice(), "mVP");

      if (_side == OptionLib.OptionSide.Buy) {
        _vToken.burn(msg.sender, _volAmount);
        _vToken.pay(address(_marketMaker), _premium.toDecimals(_fundingDecimals));
      }
      else{
        _marketMaker.settlePayment( address(_vToken), _premium.toDecimals(_fundingDecimals));
        _vToken.mint(msg.sender, _volAmount);
      }     
    }

    // functions to transact volatility tokens (buy or sell)
    // arguments: pool token address, tenor in seconds, amount in 18 decimals, option side (buy 0 or sell 1)
    function tradeVolToken(
        Pool _pool,
        uint256 _tenor,
        uint256 _amount,
        OptionLib.OptionSide _side
    ) external {
        MarketMaker _marketMaker = _pool.marketMaker();
        require(
            _marketMaker.govToken().existVolTradingPool(address(_pool)),
            "-VP"
        ); // only certified pools can trade vol
        VolatilityToken _vToken = _marketMaker.govToken().getVolatilityToken(
            _marketMaker.underlying(),
            _tenor
        );
        VolatilityChain _volChain = _marketMaker.getVolatilityChain();
        OptionLib.Option memory _option = OptionLib.Option(
            OptionLib.PayoffType.Put,
            _side,
            OptionLib.OptionStatus.Draft,
            msg.sender,
            0,
            block.timestamp,
            0,
            _tenor,
            0,
            0,
            _amount,
            0,
            _volChain.queryPrice(),
            0,
            0,
            0,
            0,
            address(_pool),
            0,
            0
        );

        ERC20 _funding = ERC20(_marketMaker.funding());
        uint256 _fundingDecimals = _funding.decimals();
        (uint256 _premium, , , uint256 _vol, ) = vault
            .calcOptionCost(_option);

        (uint256 _volAmount, uint256 _volPrice) = _vToken.calcAmount(_premium, _vol, _side==OptionLib.OptionSide.Sell);
        require(_volPrice > _pool.minVolPrice(), "mVP");

        if (_side == OptionLib.OptionSide.Buy) {
            require(
                _funding.transferFrom(
                    msg.sender,
                    address(_vToken),
                    _premium.toDecimals(_fundingDecimals)
                ),
                "-VB"
            );
            _vToken.mint(msg.sender, _volAmount);
        } else {
            _vToken.burn(msg.sender, _volAmount);
            _vToken.pay(msg.sender, _premium.toDecimals(_fundingDecimals));
        }

        emit TradeVolatility(
            msg.sender,
            address(_pool),
            _amount,
            _volAmount
        );
    }

    // get volatility token
    function getVolatilityToken(Pool _pool, uint256 _tenor)
        external
        view
        returns (VolatilityToken)
    {
        MarketMaker _marketMaker = _pool.marketMaker();
        return
            _marketMaker.govToken().getVolatilityToken(
                _marketMaker.underlying(),
                _tenor
            );
    }

    // get volatility chain
    function getVolatilityChain(Pool _pool)
        external
        view
        returns (VolatilityChain)
    {
        MarketMaker _marketMaker = _pool.marketMaker();
        return _marketMaker.getVolatilityChain();
    }

    // expire option contracts (one at a time), with exercise fees paid to the exercising bots.
    function expireOption(uint256 _expiringId, address _exerciseFeeRecipient)
        external
    {
        (
            OptionLib.OptionStatus _optionStatus,
            uint256 _maturity,
            address _optionHolder,
            Pool _pool
        ) = vault.getOptionInfo(_expiringId);

        if (
            (_optionStatus == OptionLib.OptionStatus.Active) &&
            (_maturity <= block.timestamp)
        ) {
            vault.stampExpiredOption(_expiringId);
            (
                uint256 _toHolder,
                uint256 _toProtocol,
                uint256 _toExerciser
            ) = vault.getContractPayoff(_expiringId);

            MarketMaker _marketMaker = _pool.marketMaker();
            uint256 _fundingDecimals = ERC20(_marketMaker.funding()).decimals();
            _marketMaker.settlePayment(
                _pool.marketMaker().govToken().protocolFeeRecipient(),
                _toProtocol.toDecimals(_fundingDecimals)
            );
            _marketMaker.settlePayment(_optionHolder, _toHolder.toDecimals(_fundingDecimals));
            _marketMaker.settlePayment(_exerciseFeeRecipient, _toExerciser.toDecimals(_fundingDecimals));
            emit Expire(
                _optionHolder,
                address(_pool),
                _expiringId,
                _toHolder,
                msg.sender
            );
        }
    }

    // unwind existing option contracts
    // arguments: pool token address, tenor in seconds, strike in 18 decimals, amount in 18 decimals, payoff type (call 0 or put 1), option side (buy 0 or sell 1), payment methods 0-usdc/1-token/2-vol
    function unwindOption(uint256 _optionId) external {
        (
            OptionLib.OptionStatus _optionStatus,
            ,
            address _optionHolder,
            Pool _pool
        ) = vault.getOptionInfo(_optionId);

        require((_optionStatus == OptionLib.OptionStatus.Active) &&
            (_optionHolder == msg.sender), "unwind not allowed");
      
          vault.stampExpiredOption(_optionId);
          // get unwind value
          (uint256 _toHolder, uint256 _toProtocol) = vault
              .calcOptionUnwindValue(_optionId);

          MarketMaker _marketMaker = _pool.marketMaker();
          uint256 _fundingDecimals = ERC20(_marketMaker.funding()).decimals();

          _marketMaker.settlePayment(
              _pool.marketMaker().govToken().protocolFeeRecipient(),
              _toProtocol.toDecimals(_fundingDecimals)
          );
          _marketMaker.settlePayment(_optionHolder, _toHolder.toDecimals(_fundingDecimals));
          emit Unwind(_optionHolder, address(_pool), _optionId, _toHolder);
      
    }

    // add capital by depositing amount in funding tokens
    function addCapital(Pool _pool, uint256 _depositAmount) external {
        uint256 _averageGrossCapital = vault.calcCapital(_pool, false, true);
        ERC20 _funding = ERC20(_pool.marketMaker().funding());
        uint256 _mintPoolAmount = _depositAmount
            .toWei(_funding.decimals())
            .ethdiv(_averageGrossCapital);
        require(
            _funding.transferFrom(
                msg.sender,
                address(_pool.marketMaker()),
                _depositAmount
            )
        );
        _pool.mint(msg.sender, _mintPoolAmount);
    }

    // remove capital by withdrawing amount in funding tokens
    function withdrawCapital(Pool _pool, uint256 _burnPoolAmount) external {
        uint256 _averageNetCapital = vault.calcCapital(_pool, true, true);
        uint256 _withdrawValue = _averageNetCapital
            .ethmul(_burnPoolAmount)
            .toDecimals(ERC20(_pool.marketMaker().funding()).decimals());
        _pool.burn(msg.sender, _burnPoolAmount);
        _pool.marketMaker().settlePayment(msg.sender, _withdrawValue);
    }
}
