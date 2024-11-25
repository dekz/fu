// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";
import {Shares} from "./types/Shares.sol";
import {Balance} from "./types/Balance.sol";
import {scale} from "./types/SharesXBasisPoints.sol";
import {scale, castUp} from "./types/BalanceXBasisPoints.sol";
import {BalanceXShares, tmp, alloc, SharesToBalance} from "./types/BalanceXShares.sol";
import {BalanceXShares2, tmp as tmp2, alloc as alloc2} from "./types/BalanceXShares2.sol";
import {BalanceXBasisPointsXShares, tmp as tmp3, alloc as alloc3} from "./types/BalanceXBasisPointsXShares.sol";
import {BalanceXBasisPointsXShares2, tmp as tmp4, alloc as alloc4} from "./types/BalanceXBasisPointsXShares2.sol";
import {SharesXBasisPoints} from "./types/SharesXBasisPoints.sol";
import {Shares2XBasisPoints, tmp as tmp5, alloc as alloc5} from "./types/Shares2XBasisPoints.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    using UnsafeMath for uint256;
    using SharesToBalance for Shares;

    // TODO: reorder arguments for clarity/consistency
    function getTransferShares(
        Balance amount,
        BasisPoints feeRate,
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal view returns (Shares newFromShares, Shares newToShares, Shares newTotalShares) {
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        BalanceXShares t1 = alloc().omul(fromShares, totalSupply);
        BalanceXShares t2 = alloc().omul(amount, totalShares);
        BalanceXShares t3 = alloc().osub(t1, t2);
        BalanceXBasisPointsXShares2 n1 = alloc4().omul(t3, scale(uninvolvedShares, BASIS));
        BalanceXBasisPointsXShares t4 = alloc3().omul(totalSupply, scale(uninvolvedShares, BASIS));
        BalanceXBasisPointsXShares t5 = alloc3().omul(amount, scale(totalShares, feeRate));
        BalanceXBasisPointsXShares d = alloc3().oadd(t4, t5);
        BalanceXBasisPointsXShares t6 = alloc3().omul(amount, scale(totalShares, BASIS - feeRate));
        BalanceXBasisPointsXShares t7 = alloc3().omul(scale(toShares, BASIS), totalSupply);
        BalanceXBasisPointsXShares t8 = alloc3().oadd(t6, t7);
        BalanceXBasisPointsXShares2 n2 = alloc4().omul(t8, uninvolvedShares);

        newFromShares = n1.div(d);
        newToShares = n2.div(d);
        // TODO: implement divMulti for BalanceXBasisPointsXShares2 / BalanceXBasisPointsXShares
        /*
        {
            (uint256 x, uint256 y) = cast(n1).divMulti(cast(n2), cast(d));
            (newFromShares, newToShares) = (Shares.wrap(x), Shares.wrap(y));
        }
        */
        newTotalShares = totalShares + (newToShares - toShares) - (fromShares - newFromShares);

        // TODO use divMulti to compute beforeToBalance and beforeFromBalance (can't use it for after because newTotalShares might change)
        Balance beforeToBalance = toShares.toBalance(totalSupply, totalShares);
        Balance afterToBalance = newToShares.toBalance(totalSupply, newTotalShares);
        Balance expectedAfterToBalanceLo = beforeToBalance + amount - castUp(scale(amount, feeRate));
        Balance expectedAfterToBalanceHi = beforeToBalance + castUp(scale(amount, BASIS - feeRate));

        {
            bool condition = afterToBalance < expectedAfterToBalanceLo;
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
        {
            bool condition = afterToBalance > expectedAfterToBalanceHi;
            newToShares = newToShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }

        Balance beforeFromBalance = fromShares.toBalance(totalSupply, totalShares);
        Balance afterFromBalance = newFromShares.toBalance(totalSupply, newTotalShares);
        Balance expectedAfterFromBalance = beforeFromBalance - amount;
        {
            bool condition = afterFromBalance > expectedAfterFromBalance;
            newFromShares = newFromShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }
        {
            bool condition = afterFromBalance < expectedAfterFromBalance;
            newFromShares = newFromShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
    }

    function getTransferShares(
        BasisPoints feeRate,
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal pure returns (Shares newToShares, Shares newTotalShares) {
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        Shares2XBasisPoints n = alloc5().omul(scale(uninvolvedShares, BASIS), totalShares);
        SharesXBasisPoints d = scale(uninvolvedShares, BASIS) + scale(fromShares, feeRate);

        /*
        Shares2XBasisPoints n =
            alloc5().omul(scale(fromShares, (BASIS - feeRate)) + scale(toShares, BASIS), uninvolvedShares);
        SharesXBasisPoints d = scale(uninvolvedShares, BASIS) + scale(fromShares, feeRate);
        newToShares = n.div(d);
        newTotalShares = totalShares + (newToShares - toShares) - fromShares;
        */
        newTotalShares = n.div(d);
        newToShares = toShares + fromShares - (totalShares - newTotalShares);

        console.log("           feeRate", BasisPoints.unwrap(feeRate));
        console.log("       totalSupply", Balance.unwrap(totalSupply));
        console.log("       totalShares", Shares.unwrap(totalShares));
        console.log("        fromShares", Shares.unwrap(fromShares));
        console.log("          toShares", Shares.unwrap(toShares));
        console.log("       newToShares", Shares.unwrap(newToShares));
        console.log("===");

        // Fixup rounding error
        // TODO: use divMulti
        Balance beforeFromBalance = fromShares.toBalance(totalSupply, totalShares);
        Balance beforeToBalance = toShares.toBalance(totalSupply, totalShares);
        Balance afterToBalance = newToShares.toBalance(totalSupply, newTotalShares);
        Balance expectedAfterToBalance = beforeToBalance + beforeFromBalance - castUp(scale(beforeFromBalance, feeRate));
        //Balance expectedAfterToBalance = beforeToBalance + cast(scale(beforeFromBalance, BASIS - feeRate));

        console.log("before fromBalance", Balance.unwrap(beforeFromBalance));
        console.log("  before toBalance", Balance.unwrap(beforeToBalance));
        console.log("         toBalance", Balance.unwrap(afterToBalance));
        console.log("expected toBalance", Balance.unwrap(expectedAfterToBalance));

        /*
        {
            bool condition = afterToBalance > expectedAfterToBalance;
            newToShares = newToShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }
        {
            bool condition = afterToBalance < expectedAfterToBalance;
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
        */
        for (uint256 i; afterToBalance > expectedAfterToBalance && i < 3; i++) {
            console.log("round down");
            Shares decr = Shares.wrap(
                (Balance.unwrap(afterToBalance - expectedAfterToBalance) * Shares.unwrap(newTotalShares)).unsafeDivUp(
                    Balance.unwrap(totalSupply)
                )
            );
            console.log("decr", Shares.unwrap(decr));
            newToShares = newToShares - decr;
            newTotalShares = newTotalShares - decr;
            if (newToShares <= toShares) {
                console.log("clamp");
                newTotalShares = newTotalShares + (toShares - newToShares);
                newToShares = toShares;
                afterToBalance = newToShares.toBalance(totalSupply, newTotalShares);
                console.log("updated toBalance", Balance.unwrap(afterToBalance));
                break;
            }
            afterToBalance = newToShares.toBalance(totalSupply, newTotalShares);
            console.log("updated toBalance", Balance.unwrap(afterToBalance));
        }
        {
            bool condition = afterToBalance < expectedAfterToBalance;
            if (condition) {
                console.log("round up");
            }
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }

        console.log("    new toBalance", Balance.unwrap(newToShares.toBalance(totalSupply, newTotalShares)));
        console.log("===");
    }

    function getDeliverShares(Balance amount, Balance totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares)
    {
        BalanceXShares t1 = alloc().omul(fromShares, totalSupply);
        BalanceXShares t2 = alloc().omul(amount, totalShares);
        BalanceXShares t3 = alloc().osub(t1, t2);
        BalanceXShares2 n = alloc2().omul(t3, totalShares - fromShares);
        BalanceXShares t4 = alloc().omul(totalSupply, totalShares - fromShares);
        BalanceXShares d = alloc().oadd(t4, t2);

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);

        // Fixup rounding error
        Balance beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        Balance afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        Balance expectedAfterFromBalance = beforeFromBalance - amount;
        bool condition = afterFromBalance < expectedAfterFromBalance;
        newFromShares = newFromShares.inc(condition);
        newTotalShares = newTotalShares.inc(condition);
    }

    function getBurnShares(Balance amount, Balance totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares, Balance newTotalSupply)
    {
        revert("unimplemented");
    }
}
