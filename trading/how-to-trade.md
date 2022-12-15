---
cover: >-
  https://images.unsplash.com/photo-1465056836041-7f43ac27dcb5?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHw0fHxtb3VudGFpbnxlbnwwfHx8fDE2Mzg4MTkyMjA&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Option Traders

### Enter an option

Investors could trade options in the following configurations:

* Underlying assets: Ethereum or Bitcoin
* Type of payoff: European style call, put, call spread and put spread
* Amount of assets: this can be fractional, e.g. 0.1 Ethereum or 0.01 Bitcoin
* Strikes: any non-zero price level
* Expiry: as short as 1 second and as long as 100 years
* Premium payments: USDC, wrapped Ethereum/Bitcoin or Moret volatility tokens on the deployed chains

To buy an option, traders pay premium into the liquidity pool with the best quote.&#x20;

To sell an option, traders get paid premium upfront while have to post collaterals. Following alternatives are possible:

* Post collateral in USDC and get paid premium in USDC, the net amount is paid to the liquidity pool.&#x20;
* Post collateral and get paid premium in wrapped Ethereum/Bitcoin, the net amount is paid into the liquidity pool.
* Post collateral in USDC and get paid premium in Moret volatility tokens, the collateral amount is paid to the liquidity pool while volatility tokens are paid immediately.&#x20;

The collateral amount is calculated differently based on the payoff of options:

* Call option: the amount of option contract (1 contract = 1 underlying asset token) times the spot price
* Put option: the amount of option contract (1 contract = 1 underlying asset token) times the option strike price &#x20;
* Call spread and put spread: the amount of option contract (1 contract = 1 underlying asset token) times the difference of two strike prices&#x20;

The fact that call spread and put spread asks for collateral that is usually lower than the full amount, allows traders to post fewer collaterals, especially when they enter an option strategy such as butterfly.

In addition, on BNB chain only, the collateral amount can be further reduced if the traders simultaneously hold liquidity pool tokens and lock the equivalent amount of LP tokens until the option expiry.

### How options are priced

Options are normally priced using Black-Scholes formula such as this one for call options:

$$
\mathrm C(\mathrm S,\mathrm K,\mathrm t)= \mathrm N(\mathrm d_1)\mathrm S - \mathrm N(\mathrm d_2) \mathrm K \mathrm e^{-rt}
$$

The option price can be decomposed to two parts: intrinsic value and time value. Intrinsic value is the payoff value as if the option expires now. The time value is the difference to add up to the option price, which is a result of option expiring in a future time. Moret calculates these two values separately. The time value follows the proxy with the at-the-money option price C' and the relative distance between spot and strike prices:

$$
\mathrm V(\mathrm S,\mathrm t)= \mathrm C'(\mathrm S,\mathrm S,\mathrm t) \frac{\mathrm {min}( \sigma\sqrt{t},1) / 2}{\mathrm {min}( \sigma\sqrt{t},1) / 2 + 1 - \mathrm {min}( \mathrm K/\mathrm S,\mathrm S/\mathrm K)}
$$

The implied volatility is determined by both the volatility oracle and the liquidity pool AMM model.

{% content-ref url="../oracle/on-chain-oracle.md" %}
[on-chain-oracle.md](../oracle/on-chain-oracle.md)
{% endcontent-ref %}

$$
\sigma (\mathrm t) = \sigma_{oracle} (\mathrm t)  \beta_{amm} (\mathrm t)
$$

The AMM model dictates the relationship between volatility premium (or discount) and the relative risk exposure of option contract vs the liquidity pool capital. There are separate calculation for call option (including call spreads) and put options (including put spreads).&#x20;

$$
\beta_{amm} (\mathrm t) = \mathrm {average} (\frac{1}{1-\lambda \frac{\mathrm D_0}{\mathrm E}} , \frac{1}{1-\lambda \frac{\mathrm D_0+\Delta \mathrm D}{\mathrm E}})
$$

$$\lambda$$ is a liquidity pool level parameter setting how sensitive implied volatility should be to the size of option trade. $$\mathrm D_0$$ and $$\Delta \mathrm D$$ are the aggregate delta of all existing call or put options and the delta of option contract concerned, both calculated at a stress level set at $$\zeta$$ times oracle volatility level away from the spot price. $$\zeta$$ is another pool-level parameter configurable via liquidity pool governance. $$\mathrm E$$ is the gross capital of the liquidity pool, explained in the following chapters. Note that there are different values of $$\beta_{amm}$$ for puts and calls.

### At option expiry

On Moret, option contracts are European style, meaning they expire at the fixed expiry time and not earlier. To automate the process of expiring contracts while keeping it decentralised, external bots are incentivised to settle the options when they expire, in return for 0.3% of the option payoff in order to compensate for the gas fee.

At expiry, the payoff amount will be paid back to the option holders in USDC if they are buyers of the options. For option sellers, collateral amount minus the payoff is paid back in USDC.

