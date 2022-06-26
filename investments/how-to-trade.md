---
description: Guide on how to place trades on Moret
cover: >-
  https://images.unsplash.com/photo-1465056836041-7f43ac27dcb5?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHw0fHxtb3VudGFpbnxlbnwwfHx8fDE2Mzg4MTkyMjA&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Option Traders

Investors could buy call and put options on ETH and BTC prices. There is potential extension to other tokens. The option premiums are paid in USDC. The investors can trade 1-day, 7-day and 30-day contracts, which settle exactly 24 hours, 168 hours and 720 hours from the second the trades are created. This differs from Deribit where contracts settle at 8:00 UTC. It allows a continuous expiry offerings to investors and reduces the market impact around the option expiry time each day.

Moret also permits trading fractional contract size so investors could trade options on as little as 1 wei.

In addition, Moret allows investors to enter short positions in call and put options. In these cases, the investors are asked to post collaterals that is determined as follows:

* For short positions of call options, the collateral is equal to the current spot price. The protocol would then convert it to the equivalent amount of ETH or BTC in spot. At option expiry, the investors will receive back collateral in USDC that is based on the spot price at expiry. Therefore, the whole transaction constitutes a covered call position, where the investors collect the premium of the call option while forego the price appreciation above the strike price.
* For short positions of put options, the collateral is equal to the strike price. The protocol keeps the same amount in USDC and returns it back to the investor at option expiry. Different to the above case, the collateral is not converted to ETH/BTC. The whole transaction constitutes a covered put position, where the investors collect the put option premium while give up the pay off amount if the price falls below the strike price.

Since the investors pay the collateral and collect the option premium both in USDC, the net payment by covered selling options would be the difference of collateral and premium.

European style expiry is supported only. External bots are employed or enticed to settle the options when they expire, in return for 1% of the option payoff if positive, in order to compensate for the gas fee.

#### Volatility Automatic Market Maker

Option premiums are determined by the spot price, strike price, expiry, token amount and volatility. The spot price is retrieved from price oracle Chainlink. Strike price, expiry and token amount are set by the investors. The last input for the option premiums is the volatility, which is determined in a constant product market maker mechanism, which forms the core of Moret AMM.

The total volatility consists of two parts: **backbone volatility** and **volatility premium**

Backbone volatility is a rolling weighted average historical realised volatility of ETH/BTC prices. The data is provided by the Moret volatility oracle detailed in the 'On-chain Oracle' page.

Volatility premium is determined by the capacity of the liquidity pool, via a constant product market making model. Each option bought by investors has positive risk exposure to the liquidity pool, while each option sold by investors as part of the covered short positions, has negative risk exposure to the liquidity pool. The more positive the net risk positions are, the less capacity the whole protocol can support investors to buy additional options. Therefore, a constant product formula works neatly in defining the volatility premium that investors need to pay in order to buy put or call options. Conceptually volatility premium \* capacity = constant. The higher the capacity is the lower volatility premium would be. If there are more selling positions than buying, the capacity could exceed the total liquidity provided, in which case the volatility premium can even be negative.&#x20;

#### Volatility Skew

The difference in volatility between options with at-the-money strike and other strikes is the volatility skew. Moret formulaically constructs the volatility skew so in-the-money or out-the-money option purchasers take on more volatilities than those buying at-the-money options.

![](https://cdn-images-1.medium.com/max/1200/1\*VY5HRpcJkos8V\_uKnw9PCw.png)

