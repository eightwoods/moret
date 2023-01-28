// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface EOption{
    event TradeVolatility(address indexed _purchaser, address indexed _pool, uint256 _cost, uint256 _volAmount);
    event Expire(address indexed _holder, address indexed _pool, uint256 _id, uint256 _payoff, address _bot);
    event Unwind(address indexed _holder, address indexed _pool, uint256 _id, uint256 _payoff);
    event ResetParameter(uint256 indexed _parameterId, uint256 _parameter);
    event ResetBotAddress(address _newBot);
    event HedgeResponse(address indexed _hedger, address indexed _market, bool success, bytes data);
    event HedgeSwapResponse(address indexed _hedger, address indexed _market, uint[] amounts);
    // event ResetTradingStatus(address indexed _exchange, bool _tradingAllowed);
    }