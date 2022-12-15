# Liquidity Pool, Market Maker and RFQ

DeFi options protocols can be broadly categorised into two camps: order book and liquidity pool models. In Moret, liquidity providers act as market makers in providing liquidity to both sides of the options market. They will take bid-ask spreads as profits and managing residual risks. Risk management usually involves adjusting the balance by trading underlying assets or derivatives via 1Inch aggregator.

The auto-RFQ process is a distinct feature of Moret which works as a nice combination of liquidity pool and book order models.&#x20;

For a market order of options trade, Moret will query all liquidity pools for quotes. It is an automatic RFQ process for existing liquidity pools based on the AMM model. Each liquidity pool has its own hedging approach and could be flexible in setting the AMM model parameters, giving different level of bid-ask spreads.  On the back of it, liquidity pools have designated addresses from which their bots can instruct to trade underlying assets (BTC or ETH) via 1Inch Aggregation protocol.&#x20;

Only available on BNB chain, traders can create explicit RFQ to both the existing liquidity pools and any potential market makers who manage quotes off chain. The off-chain managers can match the RFQ if it is better than the limit price and the on-chain best quote (all based on implied volatility).&#x20;

![Three pillars of liquidity pools in Moret](<../.gitbook/assets/Deck images.004.jpeg>)

