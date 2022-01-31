#!/Users/apple/.pyenv/shims/python
from web3 import Web3
from eth_account import Account
from library import contract
import os 
from datetime import datetime
infura_url = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']
chain_id = 137
addresses = [
    '0x17277a5A0e547cd2425397ffE9069cc3f03C42A2','0x6eEfc8B4b5A688eec20501495Fc016e197EB2E2a']

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address
gas_price = web3.toWei(50, 'gwei')

for address in addresses:
    exchange = contract(web3, address, 'Exchange.json')
    market = contract(web3, exchange.functions.marketMakerAddress().call(), 'MoretMarketMaker.json')
    vault = contract(web3, exchange.functions.vaultAddress().call(), 'OptionVault.json')

    any_expiring = vault.functions.anyOptionExpiring().call()
    if any_expiring:
        print("options expiring {} at {}".format(datetime.now().strftime("%d/%m/%Y, %H:%M:%S"), market.address))
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        expire_txn = market.functions.expireOptions(web3.eth.default_account).buildTransaction(
            {'gas': 5000000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id, 'gasPrice': gas_price})
        #print(expire_txn)
        signed_txn = web3.eth.account.signTransaction(expire_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_txn.rawTransaction)
        #print(web3.toHex(web3.keccak(signed_txn.rawTransaction)))
    # else:
    #     print('no option expiring', datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))
