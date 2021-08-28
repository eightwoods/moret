
const {expect } = require('chai');

describe('VolatilityChain', function(){
  before(async function() {
    this.Box = await ethers.getContractFactory('VolatilityChain');
  });

  beforeEach(async function(){
    this.box = await this.Box.deploy();
    await this.box.deployed();
  });

  
})
