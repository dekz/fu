// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UnsafeMath} from "../lib/UnsafeMath.sol";
import {uint512, tmp, alloc} from "../lib/512Math.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    using UnsafeMath for uint256;

    uint256 internal constant feeBasis = 10_000;

    function getTransferShares(
        uint256 amount,
        uint256 feeRate,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares
    ) internal view returns (uint256 newFromShares, uint256 newToShares, uint256 newTotalShares) {
        uint256 uninvolvedShares = totalShares - fromShares - toShares;
        uint512 t1 = alloc().omul(fromShares, totalSupply);
        uint512 t2 = alloc().omul(amount, totalShares);
        uint512 t3 = alloc().osub(t1, t2);
        uint512 n1 = alloc().omul(t3, uninvolvedShares * feeBasis);
        uint512 t4 = alloc().omul(totalSupply, uninvolvedShares * feeBasis);
        uint512 t5 = alloc().omul(amount * feeRate, totalShares);
        uint512 d = alloc().oadd(t4, t5);
        uint512 t6 = alloc().omul(amount * (feeBasis - feeRate), totalShares);
        uint512 t7 = alloc().omul(toShares, totalSupply * feeBasis);
        uint512 t8 = alloc().oadd(t6, t7);
        uint512 n2 = alloc().omul(t8, uninvolvedShares);

        // TODO: add optimized multidiv method to 512Math
        newFromShares = n1.div(d);
        newToShares = n2.div(d);
        console.log("    fromShares", fromShares);
        console.log(" newFromShares", newFromShares);
        console.log("      toShares", toShares);
        console.log("   newToShares", newToShares);
        newTotalShares = totalShares + (newToShares - toShares) - (fromShares - newFromShares);
        console.log("   totalShares", totalShares);
        console.log("newTotalShares", newTotalShares);

        // Fixup rounding error
        /*
        {
            console.log("===");
            uint256 beforeToBalance = tmp().omul(toShares, totalSupply).div(totalShares);
            uint256 afterToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
            uint256 expectedAfterToBalance = beforeToBalance + amount * (feeBasis - feeRate) / feeBasis;
            if (afterToBalance < expectedAfterToBalance) {
                console.log("toBalance too low");
                uint256 incr = tmp().omul(expectedAfterToBalance - afterToBalance, newTotalShares).div(totalSupply);
                newToShares += incr;
                newTotalShares += incr;
            }
        }
        */
        {
            console.log("===");
            uint256 beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
            uint256 afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
            uint256 expectedAfterFromBalance = beforeFromBalance - amount;
            console.log("  actual fromBalance", afterFromBalance);
            console.log("expected fromBalance", expectedAfterFromBalance);
            {
                bool condition = afterFromBalance > expectedAfterFromBalance;
                newFromShares = newFromShares.unsafeDec(condition);
                newTotalShares = newTotalShares.unsafeDec(condition);
            }
            {
                bool condition = afterFromBalance < expectedAfterFromBalance;
                newFromShares = newFromShares.unsafeInc(condition);
                newTotalShares = newTotalShares.unsafeInc(condition);
            }
        }
    }

    function getDeliverShares(uint256 amount, uint256 totalSupply, uint256 totalShares, uint256 fromShares)
        internal
        view
        returns (uint256 newFromShares, uint256 newTotalShares)
    {
        uint512 t1 = alloc().omul(fromShares, totalSupply);
        uint512 t2 = alloc().omul(amount, totalShares);
        uint512 t3 = alloc().osub(t1, t2);
        uint512 n = alloc().omul(t3, totalShares - fromShares);
        uint512 t4 = alloc().omul(totalSupply, totalShares - fromShares);
        uint512 d = alloc().oadd(t4, t2);

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);

        // Fixup rounding error
        uint256 beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        uint256 afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        uint256 expectedAfterFromBalance = beforeFromBalance - amount;
        if (afterFromBalance < expectedAfterFromBalance) {
            uint256 incr = tmp().omul(expectedAfterFromBalance - afterFromBalance, newTotalShares).div(totalSupply);
            newFromShares += incr;
            newTotalShares += incr;
        }
    }
}
