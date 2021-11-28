#!/Users/apple/.pyenv/shims/python
from web3 import Web3
from eth_account import Account
from library import read_abi
import os 
from datetime import datetime
infura_url = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']
chain_id = 137
addresses = ['0x0c53A9cAC37327C00D9c622A6f1439CCFd1A0d1b',
             '0xEc1d5bFb1C170D6d560b1A4C913aA9b5C5308359']  # for exchange address

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address

def contract(ad, filename):
    return web3.eth.contract(address=ad, abi=read_abi(os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts', filename)))

for address in addresses:
    exchange = contract(address, 'Exchange.json')
    market = contract(exchange.functions.marketMakerAddress().call(), 'MoretMarketMaker.json')
    vault = contract(exchange.functions.vaultAddress().call(), 'OptionVault.json')

    any_expiring = vault.functions.anyOptionExpiring().call()
    if any_expiring:
        print("options expiring {} at {}".format(datetime.now().strftime("%m/%d/%Y, %H:%M:%S"), address))
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        expire_txn = market.functions.expireOptions(web3.eth.default_account).buildTransaction({'gas': 5000000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id, 'gasPrice': web3.toWei(100, 'gwei')})
        #print(expire_txn)
        signed_txn = web3.eth.account.signTransaction(expire_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_txn.rawTransaction)
        #print(web3.toHex(web3.keccak(signed_txn.rawTransaction)))
    # else:
    #     print('no option expiring', datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))
