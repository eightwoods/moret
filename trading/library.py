import json

def read_abi(fname):
    with open(fname) as f:
        data = json.load(f) 
        return data['abi']
