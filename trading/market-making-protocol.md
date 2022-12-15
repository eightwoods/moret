---
cover: >-
  https://images.unsplash.com/photo-1607602274619-4503f0c2444c?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHwxMHx8aGlnaGxhbmR8ZW58MHx8fHwxNjM4ODIxMzQ3&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Liquidity Providers

Moret operates an AMM model on volatility using liquidity pools. The innovation is to allow multiple liquidity pools each of which has its unique hedging algorithms and AMM model parameters. The customisation of both gives freedom for market makers to manage risks and adjust option prices according to their risk appetite and hedging costs (or profits).&#x20;

For yield farmers, they can invest in and redeem from any liquidity pools, according to historical performance of LP in hedging and pricing.&#x20;

There is no locking period for investing in liquidity pools. Instead, LPs operate a swing pricing model where creation and redemption process operates in slightly different prices. The prices are based on two TVLs: gross TVL and net TVL.

Gross TVL is the total reserves of the liquidity pool consisting of USDC and wrapped Ethereum/Bitcoin, minus collaterals of options.

Net TVL is Gross TVL minus the bigger of absolute Delta exposure of all call options (including call spread) and of all put options (including put spread).

The creation process of liquidity pool tokens is based on Gross TVL, so new investors will share the same risks and premium payments starting the very block the investment is made.

The redemption process is based on Net TVL. So that after each redemption, the remaining LP token holders won't be penalised by taking all risks from existing options.&#x20;



