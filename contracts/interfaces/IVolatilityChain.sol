// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVolatilityChain{
    // tenors, timestamp when volchain block is added and the information on the price stamp 
    event NewVolatilityChainBlock(uint256 indexed _tenor, uint256 _timeStamp, PriceStamp _book);

    // price stamp includes information like: 
    // start time stamp of price observation, 
    // end time stamp of price observation, 
    // open price,
    // high price during the observation period, subject to the periodicity of updating schedule (on openzeppelin or separate bot)
    // low price
    // close price
    // volatility based on the GARCH model prescribed with the VolParam
    // accentus which is a higher estimate of volatility using the most extreme of high and low prices instead of close price in deducing the volatility using the same GARCH parameters
    struct PriceStamp{ uint256 startTime; uint256 endTime; uint256 open; uint256 highest; uint256 lowest; uint256 close; uint256 volatility; uint256 accentus; }

    // GARCH parameters include:
    // starting value of volatility which is fixed
    // long term value of volatility which is the target of mean reversion
    // w: weight to the long term volatility
    // p: weight to moving average
    // q: weight to auto regression
    struct VolParam{ uint256 initialVol; uint256 ltVol; uint256 ltVolWeighted; uint256 w; uint256 p; uint256 q; }

    // Return interpolated volatility
    function getVol(uint256 _tenor) external view returns(uint256);
    // Return price and timestamp
    function queryPrice() external view returns(uint256, uint256);
    // Return token hash
    function getTokenHash() external view returns(bytes32);}