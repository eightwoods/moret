---
description: Guide on how to provide liquidity in Moret
cover: >-
  https://images.unsplash.com/photo-1607602274619-4503f0c2444c?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHwxMHx8aGlnaGxhbmR8ZW58MHx8fHwxNjM4ODIxMzQ3&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Liquidity Providers

In option market, liquidity providers usually take on two roles: making the market and taking on residual risks. Market makers stand at two sides of the market and act as counterparty to end-investors who want to buy or sell options. Risk takers hedge out the exposures by dynamically adjusting their positions in the underlying price movements.&#x20;

Since Moret is an AMM on volatility which allows end-investors to transact on-chain from both buy and sell side, the role of making market is dutifully carried out by the protocol.&#x20;

What liquidity providers to Moret do is to take on residual risks to the price movement and hedge out the risk as much as possible, by transacting the underlying tokens on the open market. This is called the hedging mechanism.&#x20;

The hedging mechanism relates to how the exposure of option to the token price is managed. An amount equal to the Delta of the options is set aside as  the hedging position. The Delta is the change of option price vis-a-vis underlying price. By dynamically adjusting the hedging positions, the liquidity pool will be able to minimise its capital fluctuation and match the option payout to the investors.&#x20;

![](https://cdn-images-1.medium.com/max/1200/1\*B1ZTQokG6Rr25CPARV0tpw.png)



Authorised bots are used to run hedge transactions. When Delta is positive, the liquidity pool converts USDC into the underlying token (WETH or WBTC) using aggregator such as 1Inch. Market order is currently deployed. In future development limit orders could also be utilised.&#x20;

When Delta is negative, the liquidity pool deposit USDC as collateral in Aave, takes out loans in WETH or WBTC and sell short via 1Inch. In this way the liquidity pool hedge out the further decrease of token price.&#x20;

The cost involved in hedging include gas fees, slippage for swaps and interest rate on Aave loans. Gas fees are covered by the maintenance fees, initially set as 1% of payoff of option contracts. As gas price on Polygon chain is considerably lower than Ethereum, the fees will be lower significantly once the transaction volume increases.&#x20;

Swap slippage is the implicit cost between actual price got from 1Inch aggregator and the oracle price. The swap slippage and the Aave loan interest are monitored constantly and gradually built in the option pricing to reflect the swap slippage exposed to the liquidity providers.&#x20;

