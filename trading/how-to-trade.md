---
description: Guide on how to place trades on Moret
cover: >-
  https://images.unsplash.com/photo-1465056836041-7f43ac27dcb5?crop=entropy&cs=srgb&fm=jpg&ixid=MnwxOTcwMjR8MHwxfHNlYXJjaHw0fHxtb3VudGFpbnxlbnwwfHx8fDE2Mzg4MTkyMjA&ixlib=rb-1.2.1&q=85
coverY: 0
---

# Option Traders

Investors could buy call and put options on ETH and BTC prices. There is potential extension to other tokens. The option premiums are paid in USDC. The investors can trade 1-day, 7-day and 30-day contracts, which settle exactly 24 hours, 168 hours and 720 hours from the block the trades are created. This differs from Deribit where contracts settle at 8:00 UTC. It allows a continuous expiry offerings to investors and reduces the market impact around the option expiry time each day.

Moret also permits trading fractional contract size so investors could theoretically trade options on as little as 1 wei.

In addition, Moret allows investors to enter short positions in call and put options. In these cases, the investors are asked to post collaterals that is determined as follows:

* For short positions of call options, the collateral is equal to the current spot price. The protocol would then convert it to the equivalent amount of ETH or BTC in spot. At option expiry, the investors will receive back collateral in USDC that is based on the spot price at expiry. Therefore, the whole transaction constitutes a covered call position, where the investors collect the premium of the call option while forego the price appreciation above the strike price.
* For short positions of put options, the collateral is equal to the strike price. The protocol keeps the same amount in USDC and returns it back to the investor at option expiry. Different to the above case, the collateral is not converted to ETH/BTC. The whole transaction constitutes a covered put position, where the investors collect the put option premium while give up the pay off amount if the price falls below the strike price.

Since the investors pay the collateral and collect the option premium both in USDC, the net payment by covered selling options would be the difference of collateral and premium.

European style expiry is supported only. External bots are employed or enticed to settle the options when they expire, in return for 1% of the option payoff if positive, in order to compensate for the gas fee.

