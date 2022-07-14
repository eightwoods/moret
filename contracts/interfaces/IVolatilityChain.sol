// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IVolatilityChain{
    // tenors, timestamp when volchain block is added and the information on the price stamp 
    event NewVolatilityChainBlock(uint256 indexed _tenor, uint256 _timeStamp, uint256 _price, uint256 _volatility, uint256 _baseTime);
    event ResetVolChainParameter(uint256 indexed _tenor, uint256 _timeStamp, address _executor);
    event RemovedTenor(uint256 indexed _tenor, uint256 _timeStamp, address _executor);

    // price stamp includes information like: 
    // start time stamp of price observation, 
    // end time stamp of price observation, 
    // open price,
    // high price during the observation period, subject to the periodicity of updating schedule (on openzeppelin or separate bot)
    // low price
    // close price
    // volatility based on the GARCH model prescribed with the VolParam
    // accentus which is a higher estimate of volatility using the most extreme of high and low prices instead of close price in deducing the volatility using the same GARCH parameters
    struct PriceStamp{ uint256 startTime; uint256 endTime; uint256 open; uint256 close; uint256 volatility; }

    // GARCH parameters include:
    // starting value of volatility which is fixed
    // long term value of volatility which is the target of mean reversion
    // w: weight to the long term volatility
    // p: weight to moving average
    // q: weight to auto regression
    struct VolParam{uint256 initialVol; uint256 ltVol; uint256 ltVolWeighted; uint256 w; uint256 p; uint256 q; }

    function queryPrice() external view returns(uint256);
    function queryVol(uint256 _tenor) external view returns(uint256 _vol);
    }