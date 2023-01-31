# Perpetuals

Moret provides **Leveraged** **Perpetuals** on the back of its powerful AMM option exchange. There are four sets of leveraged perpetuals:

1. 3x long BTC or ETH, which buys rolling 1 month call options with strike at 75%-80% of spot price and notional of 3.5 times the investment amount. The leverage ranges from 2.5x to 3.5x.
2. 3x short BTC or ETH, which buys rolling 1 month put options with strike at 125%-130% of spot price and notional of 3 times the investment amount. The leverage ranges between 1.7x to 3x.

In order to keep the leverage at designed range, the option is automatically rolled to a new 1-month trade whenever two things happen:

* People invest in or divest from the perpetuals, which is done atomically in the investment/divestment process.
* The leverage falls below the lower bound: 1.75 for 2x perpetuals and 2.5 for 3x perpetuals, which can be triggered by anyone who is incentivised by the 10% APY compensation for rebalancing.

Features of Perpetuals of moret

Graphs show 1) leverage curves for different prices and with different curves at different reset prices. 2) how it works in the background by constantly roll into new option contract with 1 month options, of which the characteristics are predefined to make sure the leverage stays in a range 3) when leverage is below a critical level mainly due to lack of trade and either large market moves or simply moving towards option expiry, anyone can run the rebalance function in order to collect 5% APY incentives
