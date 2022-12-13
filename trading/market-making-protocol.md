---
description: Guide on how an institutional investor makes market for options on Moret
cover: >-
  https://images.unsplash.com/photo-1607602274619-4503f0c2444c?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHwxMHx8aGlnaGxhbmR8ZW58MHx8fHwxNjM4ODIxMzQ3&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Market Makers

Since Moret is an AMM on volatility which allows end-investors to transact on-chain from both buy and sell side, the role of making market is dutifully carried out by the liquidity pools.&#x20;

What liquidity providers to Moret do is to take on residual risks to the price movement and hedge out the risk as much as possible, by transacting the underlying tokens on the open market. This is called the hedging mechanism.&#x20;

The hedging mechanism relates to how the exposure of option to the token price is managed. Normally an amount equal to the Delta of the options is set aside as the hedging position. The Delta is the change of option price vis-a-vis underlying price. By dynamically adjusting the hedging positions, the liquidity pool will be able to minimise its capital fluctuation and match the option payout to the investors. However, the actual algorithms might differ from one liquidity pool to another.

![](https://cdn-images-1.medium.com/max/1200/1\*B1ZTQokG6Rr25CPARV0tpw.png)



Bots can run from authorised address to instruct hedge transactions with 1Inch aggregator. In a normal hedging algorithm, when Delta is positive, the liquidity pool converts USDC into the underlying token (WETH or WBTC) using 1Inch Aggregation protocol.&#x20;

#### Volatility Automatic Market Maker

Option premiums are determined by the spot price, strike price, expiry, token amount and volatility. The spot price is retrieved from price oracle Chainlink. Strike price, expiry and token amount are set by the investors. The last input for the option premiums is the volatility, which is determined in a constant product market maker mechanism, which forms the core of Moret AMM.

The total volatility consists of two parts: **backbone volatility** and **volatility premium**

Backbone volatility is a rolling weighted average historical realised volatility of ETH/BTC prices. The data is provided by the Moret volatility oracle detailed in the 'On-chain Oracle' page.

Volatility premium is determined by the capacity of the liquidity pool, via a constant product market making model. Each option bought by investors has positive risk exposure to the liquidity pool, while each option sold by investors as part of the covered short positions, has negative risk exposure to the liquidity pool. The more positive the net risk positions are, the less capacity the whole protocol can support investors to buy additional options. Therefore, a constant product formula works neatly in defining the volatility premium that investors need to pay in order to buy put or call options. Conceptually volatility premium \* capacity = constant. The higher the capacity is the lower volatility premium would be. If there are more selling positions than buying, the capacity could exceed the total liquidity provided, in which case the volatility premium can even be negative.&#x20;

The risk exposure of an option contract is defined as the delta at a stress price level. For a call option, it is set as the delta when the price is 4 times backbone volatility higher than the spot price. For put options, the delta is calculated at a price with the same distance lower.  The stress level can be set differently at each liquidity pool through the LP governance process.

#### Volatility Skew

Because the buying and selling pressures are different for put options vs call options, the volatility premiums are calculated separately based on the aggregate risk exposure of call options on the upside and aggregate risk exposure of put options on the downside. The effect is the volatility skew.&#x20;

![](https://cdn-images-1.medium.com/max/1200/1\*VY5HRpcJkos8V\_uKnw9PCw.png)

**Bespoke Liquidity Pools**

The hedging algorithms and AMM curve parameters can be independently set for different liquidity pools. This allows anyone to create new liquidity pools with their own bots for hedging algorithms. Depending on their risk appetite, market makers can change how sensitive the volatility premiums are to the aggregate risk exposures of options, by fine tuning the AMM parameters. This incentivises market makers to compete in risk management and to provide the best option quotes for investors.&#x20;

