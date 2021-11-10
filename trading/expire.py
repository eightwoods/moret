from web3 import Web3
from eth_account import Account
from library import read_abi
import os 
infura_url = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']
chain_id = 137
address = '0xf84b72F8B88a2cf155c594B42B27Cbd3bA792f53' # for exchange address

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address

exchange_abi = read_abi(r'../build/contracts/Exchange.json')
exchange = web3.eth.contract(address=address, abi=exchange_abi)

abi = read_abi(r'../build/contracts/MoretMarketMaker.json')
market = web3.eth.contract(address=exchange.functions.marketMakerAddress().call(), abi=abi)

nonce = web3.eth.get_transaction_count(web3.eth.default_account)  
expire_txn = market.functions.expireOptions().buildTransaction({'gas': 100000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id})
signed_txn = web3.eth.account.signTransaction(expire_txn, private_key=os.environ['MNEMONIC'])
web3.eth.sendRawTransaction(signed_txn.rawTransaction)
print(web3.toHex(web3.keccak(signed_txn.rawTransaction)))
