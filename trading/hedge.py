from web3 import Web3
from eth_account import Account
from library import read_abi
import os  , json, requests
infura_url = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']
oneinch_url = r'https://api.1inch.exchange/v3.0/137/' 
chain_id = 137
address = '0xf84b72F8B88a2cf155c594B42B27Cbd3bA792f53' # for exchange address

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address

exchange_abi = read_abi(r'../build/contracts/Exchange.json')
exchange = web3.eth.contract(address=address, abi=exchange_abi)

abi = read_abi(r'../build/contracts/MoretMarketMaker.json')
market = web3.eth.contract(address=exchange.functions.marketMakerAddress().call(), abi=abi)
underlying_address = market.functions.underlyingAddress().call()
funding_address = market.functions.fundingAddress().call()

erc20_abi = read_abi(r'../build/contracts/ERC20.json')


# get the amounts to use in loans, adjusting collaterals if needed for Aave
loan_amount, collateral_amount, loan_address, collateral_address = market.functions.calcHedgeTradesForLoans().call()
print([loan_amount, collateral_amount, loan_address, collateral_address])
if collateral_amount != 0 or loan_amount != 0:
    address_abi = read_abi(r'../build/contracts/ILendingPoolAddressesProvider.json')
    address_provider = web3.eth.contract(address=market.functions.aaveAddressProviderAddress().call(),abi=address_abi)
    lending_pool_abi = read_abi(r'../build/contracts/ILendingPool.json')
    lending_pool = web3.eth.contract(address=address_provider.functions.getLendingPool().call(), abi=lending_pool_abi)
    borrow_mode = market.functions.lendingPoolRateMode().call()
    
    if collateral_amount > 0:
        # approve 
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        collat_approval_txn = market.functions.approveSpending(funding_address, lending_pool.address, collateral_amount).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_collat_approval_txn = web3.eth.account.signTransaction(collat_approval_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_collat_approval_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_collat_approval_txn.rawTransaction)))
        # deposit
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        deposit_txn = lending_pool.functions.deposit(funding_address, collateral_amount, market.address, 0).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_deposit_txn = web3.eth.account.signTransaction(deposit_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_deposit_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_deposit_txn.rawTransaction)))
    if loan_amount > 0:
        # borrow
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        borrow_txn = lending_pool.functions.borrow(underlying_address, loan_amount, borrow_mode, 0, market.address).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_borrow_txn = web3.eth.account.signTransaction(borrow_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_borrow_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_borrow_txn.rawTransaction)))
    elif loan_amount < 0:
        # approve
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        loan_approval_txn = market.functions.approveSpending(loan_address, lending_pool.address, abs(loan_amount)).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_loan_approval_txn = web3.eth.account.signTransaction(loan_approval_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_loan_approval_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_loan_approval_txn.rawTransaction)))
        # repay
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        repay_txn = lending_pool.functions.repay(underlying_address, loan_amount, borrow_mode, market.address).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_repay_txn = web3.eth.account.signTransaction(repay_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_repay_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_repay_txn.rawTransaction)))
    if collateral_amount < 0 :
        # approve
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        collat_approval_txn = market.functions.approveSpending(collateral_address, lending_pool.address, abs(collateral_amount)).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_collat_approval_txn = web3.eth.account.signTransaction(collat_approval_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_collat_approval_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_collat_approval_txn.rawTransaction)))
        # repay
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        withdraw_txn = lending_pool.functions.withdraw(funding_address, collateral_amount, market.address).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
        signed_withdraw_txn = web3.eth.account.signTransaction(withdraw_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_withdraw_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_withdraw_txn.rawTransaction)))

# get address of swap and approve the amount to swap in 1inch
spender_url = oneinch_url + r'approve/spender'
spender_resp = requests.get(spender_url)
spender_address = json.loads(spender_resp.content.decode('utf8'))['address']

underlying_amount, funding_amount = market.functions.calcHedgeTradesForSwaps().call()

slippage = web3.fromWei(market.functions.swapSlippage().call(), 'ether') * 100 

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

    # quote
    quote_params = {'fromTokenAddress': from_address, 'toTokenAddress': to_address, 'amount': sell_amount}
    quote_resp = requests.get(oneinch_url + r'quote', params=quote_params)
    quote_toAmount = json.loads(quote_resp.content.decode('utf8'))['toTokenAmount']
    print('Required trading of ' + str(to_amount) + ' vs quoted amount of ' + quote_toAmount)
    quote_protocols = json.loads(quote_resp.content.decode('utf8'))['protocols']

    # transfer sell_amount to wallet
    print("Transfer approval")
    nonce = web3.eth.get_transaction_count(web3.eth.default_account)
    print(['nonce',nonce])
    approve_txn = market.functions.approveSpending(from_address, web3.eth.default_account , sell_amount).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': 137})
    signed_approve_txn = web3.eth.account.signTransaction(approve_txn, private_key=os.environ['MNEMONIC'])
    web3.eth.sendRawTransaction(signed_approve_txn.rawTransaction)
    print(web3.toHex(web3.keccak(signed_approve_txn.rawTransaction)))
    
    print("Transfer")
    from_token = web3.eth.contract(address=from_address, abi=erc20_abi)
    nonce = nonce+ 1 if web3.eth.get_transaction_count(web3.eth.default_account) <= nonce else web3.eth.get_transaction_count(web3.eth.default_account)
    print(['nonce',nonce])
    transfer_tx = from_token.functions.transferFrom(market.address, web3.eth.default_account, sell_amount).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': 137})
    signed_transfer_txn = web3.eth.account.signTransaction(transfer_tx, private_key=os.environ['MNEMONIC'])
    web3.eth.sendRawTransaction(signed_transfer_txn.rawTransaction)
    print(web3.toHex(web3.keccak(signed_transfer_txn.rawTransaction)))

    # approve spending
    print("Swap approval") 
    nonce = nonce+ 1 if web3.eth.get_transaction_count(web3.eth.default_account) <= nonce else web3.eth.get_transaction_count(web3.eth.default_account)
    print(['nonce',nonce])
    approve_txn2 = from_token.functions.approve(Web3.toChecksumAddress(spender_address) , sell_amount).buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': 137})
    signed_approve_txn2 = web3.eth.account.signTransaction(approve_txn2, private_key=os.environ['MNEMONIC'])
    web3.eth.sendRawTransaction(signed_approve_txn2.rawTransaction)
    print(web3.toHex(web3.keccak(signed_approve_txn2.rawTransaction)))

    # swap
    print("Swap")
    swap_params = {'fromTokenAddress': from_address, 'toTokenAddress': to_address, 'amount': sell_amount, 'fromAddress': web3.eth.default_account,  'slippage': slippage, 'destReceiver': market.address}
    swap_resp = requests.get(oneinch_url + r'swap', params=swap_params)
    swap_resp_parsed = json.loads(swap_resp.content.decode('utf8'))
    nonce = nonce+ 1 if web3.eth.get_transaction_count(web3.eth.default_account) <= nonce else web3.eth.get_transaction_count(web3.eth.default_account)
    print(['nonce',nonce])
    swap_resp_parsed['tx']['gas'] = 300000
    swap_resp_parsed['tx']['gasPrice'] = 30000000000
    swap_resp_parsed['tx']['value'] = 0
    swap_resp_parsed['tx']['nonce'] = nonce
    swap_resp_parsed['tx']['chainId'] = 137
    swap_resp_parsed['tx']['to'] = Web3.toChecksumAddress(swap_resp_parsed['tx']['to'])

    signed_swap_txn = web3.eth.account.signTransaction(swap_resp_parsed['tx'],  private_key=os.environ['MNEMONIC'])
    web3.eth.sendRawTransaction(signed_swap_txn.rawTransaction)
    print(web3.toHex(web3.keccak(signed_swap_txn.rawTransaction)))
    print('Sold ' + swap_resp_parsed['fromTokenAmount'] + swap_resp_parsed['fromToken']['symbol'] + ' for ' + swap_resp_parsed['toTokenAmount'] + swap_resp_parsed['toToken']['symbol'])
    #print(swap_resp_parsed['tx'])

