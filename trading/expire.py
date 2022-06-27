#!/Users/apple/.pyenv/shims/python
from web3 import Web3
from eth_account import Account
import library as lib
import os 
from datetime import datetime

tokensList = ['ETH']

web3 = Web3(Web3.HTTPProvider(lib.infuraUrl()))
web3.eth.defaultAccount = Account.from_key(os.environ['MNEMONIC']).address
gas_price = web3.toWei(35, 'gwei')
gas = int(1e6)

moret = lib.contract(web3, lib.moretAddress, 'Moret.json')
exchange = lib.contract(web3, lib.exchangeAddress, 'Exchange.json')
brokerAddress = moret.functions.broker().call()
broker = lib.contract(web3, brokerAddress, 'MoretBroker.json')
vaultAddress = exchange.functions.vault().call()
vault = lib.contract(web3, vaultAddress, 'OptionVault.json')

for token in tokensList:
    tokenAddress = lib.tokenAddress(token)
    pools = broker.functions.getAllPools(tokenAddress).call()
    for pool in pools:
        any_expiring = vault.functions.anyOptionExpiring(pool).call()
        if any_expiring:
            # expireId = vault.function.getExpiringOptionId(pool).call()
            nonce = web3.eth.get_transaction_count(web3.eth.default_account)
            txn = exchange.functions.expireOption(pool, web3.eth.default_account).buildTransaction(
                {'gas': gas, 'from': web3.eth.default_account, 'nonce': nonce, 'chainId': lib.chainId, 'gasPrice': gas_price})
            signed_txn = web3.eth.account.signTransaction(txn, private_key=os.environ['MNEMONIC'])
            web3.eth.sendRawTransaction(signed_txn.rawTransaction)

            print("{} options expiring {} at (exchange) {} | (pool) {}: {}".format(token, datetime.now().strftime("%d/%m/%Y, %H:%M:%S"), exchange.address, pool, web3.toHex(web3.keccak(signed_txn.rawTransaction))))
        # else:
        #     print('no option expiring', datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))
