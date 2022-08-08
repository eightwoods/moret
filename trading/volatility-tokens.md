---
cover: >-
  https://images.unsplash.com/photo-1630048421806-adaffaf3f44a?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHw2fHxldGhlcmV1bXxlbnwwfHx8fDE2Mzg4MjE0OTg&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Volatility Tokens

Volatility tokens are ERC20 tokens linked to implied volatilities. They are specified by 1) the token whose price they track and 2) the time of observing the volatility. For example, ETH1 is the 1-day volatility token based on ETH price; and BTC30 is the 30-day volatility token based on BTC price.&#x20;

While crypto prices are notoriously volatile, volatility itself is, to a large extend, range bound. This feature makes them suited as an alternative to stablecoins. In addition, volatility usually goes up when market crashes. Investing in volatility is a defensive hedge against market downturn.&#x20;

Moret provides two interfaces for volatility tokens: **Issuance/Redemption** and **Option conversion**.

#### Issuance/Redemption

Investors can buy volatility tokens from Moret in the same way as buying options. The quote of volatility tokens is the implied volatility based on the constant product market maker formula. The higher the capacity of the liquidity pool is, the lower volatility premium would be.

Similarly, investors can sell volatility tokens back to Moret, the quote will be also based on the capacity of the liquidity pool.&#x20;

#### Option conversion

Holders of volatility tokens can convert them to the at-the-money call or put options with matching underlying token and expiry, provided that the protocol has enough USDC to pay for the option premium.&#x20;

