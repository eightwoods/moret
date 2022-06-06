from itertools import chain
import json, os

chainId = 80001
moretAddress = '0x386322f0a82d8F82958e6a78AF1Ee6b0Dcc5bAaB'
exchangeAddress = '0x65d3bF1E994a76Dd512039EF3dF1d111f7B07f4f'

def tokenAddress(optionToken):
    addresses = {137: {'ETH': '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', 'BTC': '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6'}, 80001: {'ETH': '0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa'}}
    return addresses[chainId][optionToken]

def minTicks(optionToken):
    ticks = {'ETH': 50, 'BTC': 100}
    return ticks[optionToken]

def infuraUrl():
    urls = {137: r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY'],  80001: r'https://polygon-mumbai.infura.io/v3/' + os.environ['INFURA_API_KEY']}
    return urls[chainId]

def contract(web3, address, filename):
    fname = os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts', filename)
    if not os.path.exists(fname):
        fname = os.path.join(r'../build/contracts', filename)
    with open(fname) as f:
        data = json.load(f) 
        return web3.eth.contract(address=address, abi=data['abi'])