// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@mocks/MockV3Aggregator.sol";

contract Handler is Test {
    uint256 private constant MAX_DEPOSIT_SIZE = type(uint96).max;

    DecentralizedStableCoin private dsc;
    DSCEngine private engine;
    ERC20Mock private weth;
    ERC20Mock private wbtc;
    MockV3Aggregator private wethUsdPriceFeed;
    MockV3Aggregator private wbtcUsdPriceFeed;
    address[] public userWithCollateralDeposited;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;
        weth = ERC20Mock(_engine.getCollateralTokens()[0]);
        wbtc = ERC20Mock(_engine.getCollateralTokens()[1]);

        wethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
        wbtcUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    ///////////////////////
    // ENGINE FUNCTIONS //
    /////////////////////
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("<== depositCollateral ==>");
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); // std-lib function

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        userWithCollateralDeposited.push(msg.sender); // Keep track of which adresses deposited since msg.sender is random in each fuzz tests
        console.log(msg.sender, " deposited: ", amountCollateral);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("<== redeemCollateral ==>");
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem); // std-lib function
        if (amountCollateral == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        console.log(msg.sender, " redeemed: ", amountCollateral);
    }

    function mintDsc(uint256 amount, uint256 _addressSeed) public {
        console.log("<== mintDsc ==>");
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = userWithCollateralDeposited[_addressSeed % userWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxDSCToMint = (int256(totalCollateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDSCToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();

        console.log(sender, " minted: ", amount);
    }

    // This breaks our invariant test suite (if collateral price crumbles too quickly)
    // function updateCollateralPrice(uint96 newPrice) public {
    //     console.log("<== updateCollateralPrice ==>");
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     wethUsdPriceFeed.updateAnswer(newPriceInt);

    //     console.log("new WETH price: ", uint256(newPrice));
    // }

    ///////////////////////
    // HELPER FUNCTIONS //
    /////////////////////
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
