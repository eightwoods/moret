from itertools import chain
import json, os

moretAddress = '0xD294BF485222f50c76591751B69d7A188499B145'
exchangeAddress = '0x117E34f9180696EE310fcF70858de3598F706d6b'

def tokenAddress(optionToken):
    addresses = {'ETH': '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', 'BTC': '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6'}
    return addresses[optionToken]

def minTicks(optionToken):
    ticks = {'ETH': 50, 'BTC': 100}
    return ticks[optionToken]

def infuraUrl():
    urls = r'https://polygon-mainnet.infura.io/v3/' + os.environ['INFURA_API_KEY']
    return urls

def contract(web3, address, filename):
    fname = os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts', filename)
    if not os.path.exists(fname):
        fname = os.path.join(r'../build/contracts', filename)
    with open(fname) as f:
        data = json.load(f) 
        return web3.eth.contract(address=address, abi=data['abi'])