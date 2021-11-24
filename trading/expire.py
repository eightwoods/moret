#!/Users/apple/.pyenv/shims/python
from web3 import Web3
from eth_account import Account
from library import read_abi
import os 
from datetime import datetime
infura_url = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']
chain_id = 137
addresses = ['0x890F8D3aD8c3a1adb295a4062C2a5D3659d78AD1','0x55310680d4a9Ed08BB6B573451169eFe92Ca7801']# for exchange address

web3 = Web3(Web3.HTTPProvider(infura_url))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address

for address in addresses:
    exchange = web3.eth.contract(address=address, abi=read_abi(os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts/Exchange.json')))
    market = web3.eth.contract(address=exchange.functions.marketMakerAddress().call(), abi=read_abi(os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts/MoretMarketMaker.json')))
    vault = web3.eth.contract(address=exchange.functions.vaultAddress().call(),abi=read_abi(os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts/OptionVault.json')))

    any_expiring = vault.functions.anyOptionExpiring().call()
    if any_expiring:
        print('option expiring', datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))
        nonce = web3.eth.get_transaction_count(web3.eth.default_account)
        expire_txn = market.functions.expireOptions(web3.eth.default_account).buildTransaction({'gas': 5000000, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': chain_id, 'gasPrice': web3.toWei(100, 'gwei')})
        print(expire_txn)
        signed_txn = web3.eth.account.signTransaction(expire_txn, private_key=os.environ['MNEMONIC'])
        web3.eth.sendRawTransaction(signed_txn.rawTransaction)
        print(web3.toHex(web3.keccak(signed_txn.rawTransaction)))
    # else:
    #     print('no option expiring', datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))
