// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface EOption{
    event NewOption(address indexed _purchaser, address indexed _exchange, uint256 _id, uint256 _premium, uint256 _collateral, bool _inVol);
    event TradeVolatility(address indexed _purchaser, address indexed _exchange, uint256 _cost, uint256 _volAmount, bool _isPurchase);
    event Expire(address indexed _bot, address indexed _exchange, address _holder, uint256 _id, uint256 _payoff);
    event ResetParameter(uint256 indexed _parameterId, uint256 _parameter);
    event ResetBotAddress(address _newBot);
    event HedgeResponse(address indexed _hedger, address indexed _market, bool success, bytes data);
    event HedgeSwapResponse(address indexed _hedger, address indexed _market, uint[] amounts);
    event ResetTradingStatus(address indexed _exchange, bool _tradingAllowed);
    }