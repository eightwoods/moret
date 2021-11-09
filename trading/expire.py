from web3 import Web3
import os  , json
from eth_account import Account
from library import read_abi
infura_url = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.default_account = Account.from_key(os.environ['MNEMONIC']).address

abi = read_abi(r'../build/contracts/MoretMarketMaker.json')

address = '0xE7CAC17029eC86fec53Eb2943B0eDa049bc335c3'
market = web3.eth.contract(address=address,abi= abi)

nonce = web3.eth.get_transaction_count(web3.eth.default_account)  

expire_txn = market.functions.expireOptions().buildTransaction({
    'gas': 70000,
    'from': web3.eth.default_account,
    'nonce': nonce
    })

signed_txn = web3.eth.account.signTransaction(expire_txn, private_key=os.environ['MNEMONIC'])
web3.eth.sendRawTransaction(signed_txn.rawTransaction)
print(web3.toHex(web3.keccak(signed_txn.rawTransaction)))
