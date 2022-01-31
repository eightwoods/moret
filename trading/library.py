import json, os

def contract(web3, address, filename):
    fname = os.path.join(os.getcwd(), r'Documents/GitHub/moret/build/contracts', filename)
    if not os.path.exists(fname):
        fname = os.path.join(r'../build/contracts', filename)
    with open(fname) as f:
        data = json.load(f) 
        return web3.eth.contract(address=address, abi=data['abi'])