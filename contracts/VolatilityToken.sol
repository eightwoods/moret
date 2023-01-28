// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/MathLib.sol";
import "./libraries/MarketLib.sol";

contract VolatilityToken is ERC20{
    using MathLib for uint256;
    using Math for uint256;

    uint256 public immutable tenor;
    address public immutable underlying;
    address public immutable exchange;
    ERC20 public funding;

    constructor(ERC20 _funding, address _underlying, uint256 _tenor, string memory _name, string memory _symbol, address _exchange ) ERC20(_name, _symbol) {
        require(_underlying != address(0), "0addr");
        require(_exchange != address(0), "0addr");

        funding = _funding;
        tenor = _tenor;
        underlying = _underlying;
        exchange = _exchange;}

    function calcAmount(uint256 _premium, uint256 _vol, bool _mint) external view returns(uint256 _amount, uint256 _volPrice){
        uint256 _supply = totalSupply();
        _volPrice = _vol;
        if(_supply > 0){
            if(_mint){
                _volPrice = _vol.max(MarketLib.balanceDef(funding, address(this)).ethdiv(_supply));
            }
            else{
                _volPrice = _vol.min(MarketLib.balanceDef(funding, address(this)).ethdiv(_supply));
            }
        }
        _amount = _premium.ethdiv(_volPrice);
    }
    
    function mint(address _account, uint256 _amount) external {
        require(msg.sender == exchange, "-vtEx");
        _mint(_account, _amount);}
    function burn(address _account, uint256 _amount) external {
        require(msg.sender == exchange, "-vtEx");
        _burn(_account, _amount);}
    function pay(address _account, uint256 _amount) external {
        require(msg.sender == exchange, "-vtEx");
        require(funding.transfer(_account, _amount), '-VS');}
}
