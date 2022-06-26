# Market Makers

Market makers are the majority liquidity pool token owners. They mainly act as a central counterparty to every option trader and hence need to hedge the residual market risks of the entire option book, of all strikes and expires, supported by the liquidity pool. &#x20;

The mechanism of the liquidity pool allows multiple market makers to divide and conquer the pool into small hot tubs. In order to do that, any liquidity pool token holder can create a hot tub by staking their liquidity pool tokens. This hot tub contains an address that is permitted to run hedging bots which trade option underlying tokens (e.g. WETH or WBTC) on 1Inch or another exchange.&#x20;

The purpose of the hedging bots is to reduce the impermanent loss caused by the option contract payoffs. The premiums, profit and loss, and remaining capitals are ring-fenced in the hot tub contract for the stake liquidity pool token holders. Option premiums and collaterals are allocated according to the total values of each hot tub.

The hot tubbers can un-stake their LP tokens to crystallise their hedging profit and loss. The P\&L is crystallised by adjusting the LP tokens they will receive during un-staking by the ratio of the total value of the hot tub to that of the unstaked part of the liquidity pool.&#x20;

For the sake of efficiency, max number of hot tubs is initially set to 5. When number of hot tubs is greater than 5, those with lowest total capitals are automatically liquidated and those staked tokens unstaked.&#x20;
