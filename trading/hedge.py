from web3 import Web3
from eth_account import Account
from library import read_abi
import os  , json, requests
infura_url = r'https://polygon-mumbai.infura.io/v3/' + os.environ['INFURA_API_KEY']
oneinch_url = r'https://api.1inch.exchange/v3.0/137/' 

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address

abi = read_abi(r'../build/contracts/MoretMarketMaker.json')
address = '0x61028e8A7C1Fc21712DDf21104A98caf455b06F1'
market = web3.eth.contract(address=address, abi=abi)
underlying_address = market.functions.underlyingAddress().call()
funding_address = market.functions.fundingAddress().call()

# get the amounts to use in loans, adjusting collaterals if needed for Aave
loan_amount, collateral_amount, loan_address, collateral_address = market.functions.calcHedgeTradesForLoans().call()
if collateral_amount != 0 or loan_amount != 0:
    address_abi = read_abi(r'../build/contracts/ILendingPoolAddressesProvider.json')
    address_provider = web3.eth.contract(address=market.functions.aaveAddressProviderAddress().call(),abi=address_abi)
    lending_pool_abi = read_abi(r'../build/contracts/ILendingPool.json')
    lending_pool = web3.eth.contract(address=address_provider.functions.getLendingPool().call(), abi=lending_pool_abi)
    borrow_mode = market.functions.lendingPoolRateMode().call()
    
    if collateral_amount > 0:
        market.functions.approveSpending(funding_address, lending_pool.address, collateral_amount).transact()
        lending_pool.functions.deposit(funding_address, collateral_amount, market.address, 0).transact()
    if loan_amount > 0:
        lending_pool.functions.borrow(underlying_address, loan_amount, borrow_mode, 0, market.address).transact()
    elif loan_amount < 0:
        market.functions.approveSpending(loan_address, lending_pool.address, abs(loan_amount)).transact()
        lending_pool.functions.repay(underlying_address, loan_amount, borrow_mode, market.address).transact()
    if collateral_amount < 0 :
        market.functions.approveSpending(collateral_address, lending_pool.address, abs(collateral_amount)).transact()
        lending_pool.functions.withdraw(funding_address, collateral_amount, market.address).transact()

# get address of swap and approve the amount to swap in 1inch
spender_url = oneinch_url + r'spender'
spender_resp = requests.get(spender_url)
spender_address = json.load(spender_resp)['address']

underlying_amount, funding_amount = market.functions.calcHedgeTradesForSwaps().call()

slippage = web3.fromWei(market.function.swapSlippage().call(), 'ether') * 100 

amounts_ok = True
from_address = ""
to_address = ""
sell_amount = 0
to_amount = 0

if underlying_amount > 0 and funding_amount < 0: # buy underlying
    from_address = funding_address
    to_address = underlying_address
    sell_amount  = abs(funding_amount)
    to_amount = underlying_amount
elif underlying_amount < 0 and funding_amount > 0: # sell underylying
    from_address = underlying_address
    to_address = funding_address
    sell_amount  = abs(underlying_amount)
    to_amount = funding_amount
else:
    amounts_ok = False
    print("Exchange amounts not correctly calculated. Please check the protocol!")

if amounts_ok:
    print("Swap started")
    market.functions.approveSpending(from_address, spender_address, sell_amount).transact()
    quote_params = {'fromTokenAddress': from_address, 'toTokenAddress': to_address, 'amount': sell_amount}
    quote_resp = requests.get(oneinch_url + r'quote', params=quote_params)
    quote_toAmount = json.load(quote_resp)['toTokenAmount']
    print('Required trading of ' + str(to_amount) + ' vs quoted amount of ' + quote_toAmount)
    quote_protocols = json.load(quote_resp)['protocols']

    swap_params = {'fromTokenAddress': from_address, 'toTokenAddress': to_address, 'amount': sell_amount, 'fromAddress': market.address,  'slippage': slippage, 'protocols': quote_protocols}
    swap_resp = requests.get(oneinch_url + r'swap', params=swap_params)
    swap_resp_parsed = json.load(swap_resp)
    print('Sold ' + swap_resp_parsed['fromTokenAmount'] + swap_resp_parsed['fromToken']['symbol'] + ' for ' + swap_resp_parsed['toTokenAmount'] + swap_resp_parsed['toToken']['symbol'])
    print(['tx'])

