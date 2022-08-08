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



Authorised bots are used to run hedge transactions. When Delta is positive, the liquidity pool converts USDC into the underlying token (WETH or WBTC) using 1Inch Aggregation protocol.&#x20;

#### Volatility Automatic Market Maker

Option premiums are determined by the spot price, strike price, expiry, token amount and volatility. The spot price is retrieved from price oracle Chainlink. Strike price, expiry and token amount are set by the investors. The last input for the option premiums is the volatility, which is determined in a constant product market maker mechanism, which forms the core of Moret AMM.

The total volatility consists of two parts: **backbone volatility** and **volatility premium**

Backbone volatility is a rolling weighted average historical realised volatility of ETH/BTC prices. The data is provided by the Moret volatility oracle detailed in the 'On-chain Oracle' page.

Volatility premium is determined by the capacity of the liquidity pool, via a constant product market making model. Each option bought by investors has positive risk exposure to the liquidity pool, while each option sold by investors as part of the covered short positions, has negative risk exposure to the liquidity pool. The more positive the net risk positions are, the less capacity the whole protocol can support investors to buy additional options. Therefore, a constant product formula works neatly in defining the volatility premium that investors need to pay in order to buy put or call options. Conceptually volatility premium \* capacity = constant. The higher the capacity is the lower volatility premium would be. If there are more selling positions than buying, the capacity could exceed the total liquidity provided, in which case the volatility premium can even be negative.&#x20;

#### Volatility Skew

The difference in volatility between options with at-the-money strike and other strikes is the volatility skew. Moret formulaically constructs the volatility skew so in-the-money or out-the-money option purchasers take on more volatilities than those buying at-the-money options.

![](https://cdn-images-1.medium.com/max/1200/1\*VY5HRpcJkos8V\_uKnw9PCw.png)





