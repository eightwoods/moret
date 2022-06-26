---
cover: >-
  https://images.unsplash.com/photo-1539206891013-5282a607b334?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHw1fHxoaWdobGFuZHxlbnwwfHx8fDE2Mzg4MjEzNDc&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Volatility Oracle

Volatility is the key input in pricing options. In order to be consistent with how the liquidity pool works, Moret has an on-chain volatility oracle that provides the volatility feed which updates itself constantly.

<img src="https://cdn-images-1.medium.com/max/1200/1*EH8DXi3Jzs2NCWZr1bZVww.png" alt="" data-size="original">

The [GARCH](https://en.wikipedia.org/wiki/Autoregressive\_conditional\_heteroskedasticity) model is used to estimate the volatility based on latest price feed from Chainlink. Without making assumption about the long-term volatility level (few actually can), the daily volatility is a result of both the latest price change and the latests volatility level. The historical 1-day ETH volatility hovered around 5%.&#x20;
