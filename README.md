---
cover: >-
  https://images.unsplash.com/photo-1519681393784-d120267933ba?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHwyfHxtb3VudGFpbnxlbnwwfHx8fDE2Mzg4MTkyMjA&ixlib=rb-1.2.1&q=85
coverY: 0
---

# DeFi Option Exchanges

## Background

* Future and option contracts are used to hedge risk or create synthetic exposures
* In crypto world, volumes in option trading have skyrocketed.
* Deribit is the top centralised exchange for crypto options.
* There have been a couple of attempts to build decentralised option exchanges.

## Option basics

An options contract is a financial derivative that gives the holder the right, but not the obligation, to buy or sell an underlying asset at a specified price on or before a certain date. It is a type of financial instrument that can be used to hedge risk or speculate on the future price movement of an underlying asset. The buyer of the options contract has the right to exercise their option and either buy or sell the underlying asset at the agreed-upon price, while the seller of the contract is obligated to fulfil the terms of the contract if the buyer chooses to exercise their option.

## Option DeFi Space

DeFi options, or decentralised finance options, are options contracts that are built on blockchain technology and are part of the broader DeFi ecosystem. DeFi options allow users to buy and sell options on a wide range of assets, including cryptocurrencies, without the need for a central authority or intermediaries. This allows for greater transparency and accessibility, as well as the potential for lower fees and faster settlement times. DeFi options are also often built on open-source protocols, which allows for greater collaboration and innovation within the DeFi ecosystem.

There have been a few protocols in the DeFi options space. However, the traction of these protocols has been less than ideal. Zee Prime Capital has written an insightful article on the current state of DeFi options space. Among the shortcomings are some of the pain points that are tackled with in Moret.&#x20;

1. **Existing option vaults and structured products focus more on selling volatility**: This is a structural imbalance that has been inherent as protocols act as conduits of hedge funds making markets on-chain and managing risks off-chain. As a result there’s bigger selling pressure of volatility. Moret provides two-way liquidity by acting as a decentralised market maker using an AMM model for implied volatility. Therefore users can buy and sell options with any strike and expiry with more or less the same liquidity.
2. **Liquidity providers are subject to losses without hedging**: It is not surprising that liquidity pools of current DeFi protocols are draining money, mostly by design. The Moret liquidity pools act as market makers in a non-order-book model. The key feature is that liquidity pools can hedge on 1inch exchange on-chain. The collaboration with 1Inch means that any liquidity pool can trade underlying tokens (WETH or WBTC for example) based on the exposure of all option trades it underwrites. Institutional market makers can even create their own liquidity pools with bespoke hedging strategies and AMM curves. Liquidity providers can then choose the best liquidity pool from all market makers.
3. **Current models aren't reflecting values locked in option pricing**: With the exception of Lyra etc., the current models don't take into account the values of liquidity pools vs the options being underwritten. Moret aims to apply an AMM model to determine implied volatility based on backbone historical volatility and the option exposure vs the total value locked in the liquidity pool. While Lyra opts for a 'vega' approach, Moret uses delta to determine the implied volatility. This delta approach naturally creates skews as demands for calls vs puts differ. In addition, Moret has an auto-RFQ process, where by default traders will query quotes from all liquidity pools and pick the best price. Traders can also enter RFQ mode where market makers can quote to compete with liquidity pool quotes based on AMM.&#x20;
4. **There is limited offering of volatility tokens**. On Moret, volatility tokens are traded as ERC20 tokens, characterised in underlying asset and timespan. They can be exchanged with at-the-money call or put options with the same time to expiry. The values of volatility tokens are stabilised around the implied volatility determined by the AMM curves by way of arbitrage through conversions to and from options.
5. **Limited choices of payoff patterns of structured products.** The lack of liquidity for a wide range of option strategies limits the payoff choices of structured products. Moret aims to improve this by offering put and call spreads as single option contracts. The collateral requirement is slashed compared to separate options. On the back of it, we have launched the first Fixed Income Products which provide ETH or BTC linked fixed yield with a downside buffer, similar to Registered Index-Linked Annuity products popular in many parts of the world.&#x20;

On top of the pain points tackled by Moret, there are also many benefits compared to other competitors:

* An in-built volatility oracle that tracks historical volatilities
* Lower gas fees by running on Layer 2 chains such as Polygon
* Gradual overtake of the protocol governance by liquidity providers while initial token holders burn their tokens.



{% embed url="https://zeeprime.capital/a-lot-of-on-chain-options-but-few-to-exercise-a-deep-dive-into-defi-option-protocols" %}

