// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library MathLib {
/// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
/// @param a The multiplicand
/// @param b The multiplier
/// @param denominator The divisor
/// @return result The 256-bit result
/// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
function muldiv(
    uint256 a,
    uint256 b,
    uint256 denominator
)  public pure returns (uint256 result) {
    // 512-bit multiply [prod1 prod0] = a * b
    // Compute the product mod 2**256 and mod 2**256 - 1
    // then use the Chinese Remainder Theorem to reconstruct
    // the 512 bit result. The result is stored in two 256
    // variables such that product = prod1 * 2**256 + prod0
    uint256 prod0; // Least significant 256 bits of the product
    uint256 prod1; // Most significant 256 bits of the product
    assembly {
        let mm := mulmod(a, b, not(0))
        prod0 := mul(a, b)
        prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    // Handle non-overflow cases, 256 by 256 division
    if (prod1 == 0) {
        require(denominator > 0);
        assembly {
            result := div(prod0, denominator)
        }
        return result;
    }

    // Make sure the result is less than 2**256.
    // Also prevents denominator == 0
    require(denominator > prod1);

    ///////////////////////////////////////////////
    // 512 by 256 division.
    ///////////////////////////////////////////////

    // Make division exact by subtracting the remainder from [prod1 prod0]
    // Compute remainder using mulmod
    uint256 remainder;
    assembly {
        remainder := mulmod(a, b, denominator)
    }
    // Subtract 256 bit number from 512 bit number
    assembly {
        prod1 := sub(prod1, gt(remainder, prod0))
        prod0 := sub(prod0, remainder)
    }

    // Factor powers of two out of denominator
    // Compute largest power of two divisor of denominator.
    // Always >= 1.
    unchecked {
        uint256 twos = (type(uint256).max - denominator + 1) & denominator;
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }
}

// see https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1#4821
function ethmul (uint256 x, uint256 y) external pure returns (uint256 result)
{
    // uint256 z = 1e18;
    // uint256 a = x / z; uint256 b = x % z; // x = a * z + b
    // uint256 c = y / z; uint256 d = y % z; // y = c * z + d
    // return a * b * z + a * d + b * c + b * d / z;
    return muldiv(x, y, 1e18);
}

function accrue(uint256 x, uint256 i) external pure returns (uint256 result){
    // uint256 z = 1e18;
    // uint256 y = 1e18 + i;
    // uint256 a = x / z; uint256 b = x % z; // x = a * z + b
    // uint256 c = y / z; uint256 d = y % z; // y = c * z + d
    // return a * b * z + a * d + b * c + b * d / z;
    return muldiv(x, 1e18 + i, 1e18);
}

function ethdiv(
    uint256 a,
    uint256 b
)  external pure returns (uint256 result){
    return muldiv(a, 1e18, b);
}

function discount(
    uint256 a,
    uint256 b
)  external pure returns (uint256 result){
    return muldiv(a, 1e18, 1e18 + b);
}

// Babylonian method to find sqrt: https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method
function sqrt(uint256 x) external pure returns (uint256 y) {
    uint256 z = (x + 1) / 2;
    y = x;
    while (z < y) {
        y = z;
        z = (x / z + z) / 2;
    }
}

function abs(int256 x) external pure returns (uint256 y){
    y = x>=0?uint256(x):uint256(-x);
}

function logistic(int x) external pure returns (uint y){
    int72[89] memory xArray = [-15000000000000000000,-14000000000000000000,-13000000000000000000,-12000000000000000000,-11000000000000000000,-10000000000000000000,-9000000000000000000,-8000000000000000000,-7000000000000000000,-6000000000000000000,-5000000000000000000,-4500000000000000000,-4000000000000000000,-3500000000000000000,-3000000000000000000,-2900000000000000000,-2800000000000000000,-2700000000000000000,-2600000000000000000,-2500000000000000000,-2400000000000000000,-2300000000000000000,-2200000000000000000,-2100000000000000000,-2000000000000000000,-1900000000000000000,-1800000000000000000,-1700000000000000000,-1600000000000000000,-1500000000000000000,-1400000000000000000,-1300000000000000000,-1200000000000000000,-1100000000000000000,-1000000000000000000,-900000000000000000,-800000000000000000,-700000000000000000,-600000000000000000,-500000000000000000,-400000000000000000,-300000000000000000,-200000000000000000,-100000000000000000,0,100000000000000000,200000000000000000,300000000000000000,400000000000000000,500000000000000000,600000000000000000,700000000000000000,800000000000000000,900000000000000000,1000000000000000000,1100000000000000000,1200000000000000000,1300000000000000000,1400000000000000000,1500000000000000000,1600000000000000000,1700000000000000000,1800000000000000000,1900000000000000000,2000000000000000000,2100000000000000000,2200000000000000000,2300000000000000000,2400000000000000000,2500000000000000000,2600000000000000000,2700000000000000000,2800000000000000000,2900000000000000000,3000000000000000000,3500000000000000000,4000000000000000000,4500000000000000000,5000000000000000000,6000000000000000000,7000000000000000000,8000000000000000000,9000000000000000000,10000000000000000000,11000000000000000000,12000000000000000000,13000000000000000000,14000000000000000000,15000000000000000000];
    uint64[89] memory yArray = [0 ,44836436,245923648,1348868152,7398415306,40579612948,222575331839,1220803608216,6695956668971,36725591631232,201403253470474,471556483514322,1103681034895270,2580984609937180,6023769902595320,7133459036738500,8445836301156980,9997226897023950,11830187857478900,13994466019428000,16548058306388500,19558365881257000,23103423007755600,27273166218293500,32170688427895900,37913394740119600,44633940842921300,52480790660428300,61618178085112800,72225201035282300,84493720901637600,98624697397550700,114822574415160000,133287369369483000,154204234067179000,177730476935663000,203980383415252000,233008640395500000,264793720998468000,299223126787240000,336082774279586000,375052882061361000,415712315555580000,457552419163818000,500000000000000000,542447580836182000,584287684444420000,624947117938639000,663917225720414000,700776873212760000,735206279001532000,766991359604500000,796019616584748000,822269523064337000,845795765932821000,866712630630517000,885177425584840000,901375302602449000,915506279098362000,927774798964718000,938381821914887000,947519209339572000,955366059157079000,962086605259880000,967829311572104000,972726833781707000,976896576992244000,980441634118743000,983451941693611000,986005533980572000,988169812142521000,990002773102976000,991554163698843000,992866540963262000,993976230097405000,997419015390063000,998896318965105000,999528443516486000,999798596746530000,999963274408369000,999993304043331000,999998779196392000,999999777424668000,999999959420387000,999999992601585000,999999998651132000,999999999754076000,999999999955164000,1000000000000000000];

    uint i = 0;
    while(xArray[i]<x){ i++;
    if(i >= 89){break;} }

    y = uint(yArray[0]);
    if(i==89) { y =   uint(yArray[88]);}
    if(i>0 && i<89) { 
        y = (uint(yArray[i-1]) * uint(int(xArray[i]) - x) / uint(int(xArray[i]) - int(xArray[i-1]) )) + (uint(yArray[i]) * uint(x - int(xArray[i-1])) / uint(int(xArray[i]) - int(xArray[i-1]))) ; }    }

function normalDensity(int x) external pure returns (uint y){
    int72[79] memory xArray = [-10000000000000000000,-9000000000000000000,-8000000000000000000,-7000000000000000000,-6000000000000000000,-5000000000000000000,-4500000000000000000,-4000000000000000000,-3500000000000000000,-3000000000000000000,-2900000000000000000,-2800000000000000000,-2700000000000000000,-2600000000000000000,-2500000000000000000,-2400000000000000000,-2300000000000000000,-2200000000000000000,-2100000000000000000,-2000000000000000000,-1900000000000000000,-1800000000000000000,-1700000000000000000,-1600000000000000000,-1500000000000000000,-1400000000000000000,-1300000000000000000,-1200000000000000000,-1100000000000000000,-1000000000000000000,-900000000000000000,-800000000000000000,-700000000000000000,-600000000000000000,-500000000000000000,-400000000000000000,-300000000000000000,-200000000000000000,-100000000000000000,0,100000000000000000,200000000000000000,300000000000000000,400000000000000000,500000000000000000,600000000000000000,700000000000000000,800000000000000000,900000000000000000,1000000000000000000,1100000000000000000,1200000000000000000,1300000000000000000,1400000000000000000,1500000000000000000,1600000000000000000,1700000000000000000,1800000000000000000,1900000000000000000,2000000000000000000,2100000000000000000,2200000000000000000,2300000000000000000,2400000000000000000,2500000000000000000,2600000000000000000,2700000000000000000,2800000000000000000,2900000000000000000,3000000000000000000,3500000000000000000,4000000000000000000,4500000000000000000,5000000000000000000,6000000000000000000,7000000000000000000,8000000000000000000,9000000000000000000,10000000000000000000];
    uint64[79] memory yArray = [0,1,5052,9134720,6075882849,1486719514734,15983741106905,133830225764885,872682695045760,4431848411938010,5952532419775850,7915451582979970,10420934814422600,13582969233685600,17528300493568500,22394530294842900,28327037741601200,35474592846231400,43983595980427200,53990966513188100,65615814774676600,78950158300894200,94049077376887000,110920834679456000,129517595665892000,149727465635745000,171368592047807000,194186054983213000,217852177032551000,241970724519143000,266085249898755000,289691552761483000,312253933366761000,333224602891800000,352065326764300000,368270140303323000,381387815460524000,391042693975456000,396952547477012000,398942280401433000,396952547477012000,391042693975456000,381387815460524000,368270140303323000,352065326764300000,333224602891800000,312253933366761000,289691552761483000,266085249898755000,241970724519143000,217852177032551000,194186054983213000,171368592047807000,149727465635745000,129517595665892000,110920834679456000,94049077376887000,78950158300894200,65615814774676600,53990966513188100,43983595980427200,35474592846231400,28327037741601200,22394530294842900,17528300493568500,13582969233685600,10420934814422600,7915451582979970,5952532419775850,4431848411938010,872682695045760,133830225764885,15983741106905,1486719514734,6075882849,9134720,5052,1,0];

    uint i = 0;
    uint iTotal = 79;
    y=0;
    while(xArray[i]<x) { 
        i++ ;
        if(i >= iTotal) {break;}}

    if(i==iTotal) { y =   uint(yArray[i-1]);}
    if(i>0 && i<iTotal) { 
        y = (uint(yArray[i-1]) * uint(int(xArray[i]) - x) / uint(int(xArray[i]) - int(xArray[i-1]) )) + (uint(yArray[i]) * uint(x - int(xArray[i-1])) / uint(int(xArray[i]) - int(xArray[i-1]))) ; }    }

}