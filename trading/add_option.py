from web3 import Web3
import os  ,json
infura_url = r'https://polygon-mumbai.infura.io/v3/' + os.environ['INFURA_API_KEY']

web3 = Web3(Web3.HTTPProvider(infura_url))

abi_file = r'./build/contracts/Exchange.json'
with open(abi_file) as f:
    data = json.load(f) 
    abi = data['abi']

address = '0x546B128A36311CB62D69000DB3aeb8545e97836c'
exchange = web3.eth.contracts(address, abi)

exchange.methods.expireOptions().call()
