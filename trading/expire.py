from web3 import Web3
import os  , json
infura_url = r'https://polygon-mumbai.infura.io/v3/' + os.environ['INFURA_API_KEY']

web3 = Web3(Web3.HTTPProvider(infura_url))

abi_file = r'build/contracts/MoretMarketMaker.json'
with open(abi_file) as f:
    data = json.load(f) 
    abi = data['abi']

address = '0x6d1353cB3d387C73c577cEF5294ee72692E66B9d'
market = web3.eth.contracts(address, abi)

market.methods.expireOptions().send()
