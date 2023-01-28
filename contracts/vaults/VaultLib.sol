// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library VaultLib {
    struct FIAParam{uint256 callMoney; uint256 callTenor; uint256 putMoney; uint256 putTenor; uint256 putSpread; uint256 tradeWindow; }
    struct VintageStats{uint256 optionAmount; uint256 callStrike; uint256 putStrike; uint256 putSpread; uint256 startLevel; uint256 startNAV;}

    event FIPInvest(address investor, uint256 tokenUnit, uint256 investAmount);
    event FIPDivest(address investor, uint256 tokenUnit, uint256 divestAmount);
    event FIPRoll(uint256 time, uint256 amount, uint256 rebTime, uint256 vintageTime );
    event FIPRebalance(uint256 time, uint256 rebTime, bool rebCall);

}