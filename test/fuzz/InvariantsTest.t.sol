// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    uint256 private constant STARTING_BALANCE = 10 ether;

    Handler private handler;
    DeployDSC private deployer;
    DecentralizedStableCoin private dsc;
    DSCEngine private engine;
    HelperConfig private config;
    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;
    address private wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        handler = new Handler(engine, dsc);
        targetContract(address(handler));

        console.log("--INFO--\n\twethUsdPriceFeed: ", wethUsdPriceFeed);
        console.log("\twbtcUsdPriceFeed: ", wbtcUsdPriceFeed);
        console.log("\tweth: ", weth);
        console.log("\twbtc: ", wbtc);
        console.log("--------\n");
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getAdditionalFeedPrecision();
        engine.getCollateralTokens();
        engine.getLiquidationBonus();
        engine.getLiquidationBonus();
        engine.getLiquidationThreshold();
        engine.getMinHealthFactor();
        engine.getPrecision();
        engine.getDsc();
        // engine.getTokenAmountFromUsd();
        // engine.getCollateralTokenPriceFeed();
        // engine.getCollateralBalanceOfUser();
        // engine.getAccountCollateralValue();
    }

    function invariant_protocolMustHaveMoreCollateralValueThanTotalSupply() public {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(engine));
        uint256 totaValueDeposited =
            engine.getUsdValue(weth, totalWethDeposited) + engine.getUsdValue(wbtc, totalWbtcDeposited);
        console.log("<== invariant_protocolMustHaveMoreCollateralValueThanTotalSupply ==>");
        console.log("total dsc Supply: ", totalSupply);
        console.log("tota usd value Deposited in engine: ", totaValueDeposited);
        console.log("<====>\n");
        assert(totalSupply <= totaValueDeposited);
    }
}
