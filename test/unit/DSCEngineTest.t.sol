// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    uint256 private constant STARTING_BALANCE = 10 ether;
    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant AMOUNT_MINTED = 10 ether;
    uint256 private constant COLLATERAL_TO_COVER = 20 ether;
    address private immutable i_user = makeAddr("user");
    address private immutable i_liquidator = makeAddr("liquidator");

    DeployDSC private deployer;
    DecentralizedStableCoin private dsc;
    DSCEngine private engine;
    HelperConfig private config;
    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;
    address private wbtc;

    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    ); // if redeemFrom != redeemedTo, then it was liquidated

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(i_user, STARTING_BALANCE);

        console.log("--INFO--\n\twethUsdPriceFeed: ", wethUsdPriceFeed);
        console.log("\twbtcUsdPriceFeed: ", wbtcUsdPriceFeed);
        console.log("\tweth: ", weth);
        console.log("\twbtc: ", wbtc);
        console.log("--------\n");
    }

    ///////////////////////
    // CONSTRUCTOR TEST //
    /////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntmatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////
    // PRICE TESTS //
    ////////////////
    function testGetUsdValue() public view {
        //#region SETUP
        (, int256 wethPrice,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        uint256 expectedUsd =
            ((uint256(wethPrice) * engine.getAdditionalFeedPrecision()) * STARTING_BALANCE) / engine.getPrecision();
        //#endregion

        uint256 actualUsd = engine.getUsdValue(weth, STARTING_BALANCE);
        assert(actualUsd == expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        assert(actualWeth == expectedWeth);
    }

    ///////////////////////////////
    // DEPOSIT COLLATERAL TESTS //
    /////////////////////////////
    modifier depositedCollateral() {
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock rantoken = new ERC20Mock("random", "RAN", i_user, AMOUNT_COLLATERAL);
        vm.startPrank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(rantoken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = engine.getAccountInformation(i_user);
        uint256 expectedDepositInUsd = engine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assert(totalDscMinted == 0);
        assert(AMOUNT_COLLATERAL == expectedDepositInUsd);
    }

    /////////////////////
    // MINT DSC TESTS //
    ///////////////////
    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBrokenOnMintDsc() public depositedCollateral {
        uint256 amountToMint = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        console.log("amountToMint: ", amountToMint);

        uint256 collateralValueInUsd = engine.getAccountCollateralValue(i_user);
        console.log("collateralValueInUsd: ", collateralValueInUsd);

        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, collateralValueInUsd);
        console.log("expectedHealthFactor: ", expectedHealthFactor);

        vm.startPrank(i_user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(i_user);
        engine.mintDsc(AMOUNT_MINTED);

        uint256 userBalance = dsc.balanceOf(i_user);
        console.log("DSC user balance: ", userBalance);
        assert(userBalance == AMOUNT_MINTED);
    }

    //////////////////////////////////////////
    // DEPOSIT COLLATERAL & MINT DSC TESTS //
    ////////////////////////////////////////

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINTED);
        vm.stopPrank();
        _;
    }

    function testRevertsIfHealthFactorIsBrokenOnDepositCollateralAndMintDsc() public {
        uint256 amountToMint = engine.getUsdValue(weth, AMOUNT_COLLATERAL); // try to mint same amount as collateral
        console.log("amountToMint: ", amountToMint);

        uint256 collateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        console.log("collateralValueInUsd: ", collateralValueInUsd);

        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, collateralValueInUsd);
        console.log("expectedHealthFactor: ", expectedHealthFactor);

        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(i_user);
        assert(userBalance == AMOUNT_MINTED);
    }

    /////////////////////
    // BURN DSC TESTS //
    ///////////////////
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserhas() public {
        vm.prank(i_user);
        vm.expectRevert();
        engine.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(i_user);
        dsc.approve(address(engine), AMOUNT_MINTED);
        engine.burnDsc(AMOUNT_MINTED);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(i_user);
        assert(userBalance == 0);
    }

    //////////////////////////////
    // REDEEM COLLATERAL TESTS //
    ////////////////////////////
    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINTED);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.prank(i_user);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        uint256 userBalance = ERC20Mock(weth).balanceOf(i_user);
        assert(userBalance == AMOUNT_COLLATERAL);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(i_user, i_user, weth, AMOUNT_COLLATERAL);
        vm.prank(i_user);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
    }

    //////////////////////////////////////
    // REDEEM COLLATERAL FOR DSC TESTS //
    ////////////////////////////////////
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(i_user);
        dsc.approve(address(engine), AMOUNT_MINTED);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, AMOUNT_MINTED);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(i_user);
        dsc.approve(address(engine), AMOUNT_MINTED);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINTED);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(i_user);
        assertEq(userBalance, 0);
    }

    //////////////////////////
    // HEALTH FACTOR TESTS //
    ////////////////////////
    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 1000 ether;
        uint256 healthFactor = engine.getHealthFactor(i_user);
        // $10 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $20 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 10 = 1000 health factor
        assert(healthFactor == expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 wethUsdUpdatedPrice = (18 * 1e8);
        // We need $20 at all times if we have $10 of debt

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(wethUsdUpdatedPrice); // 1 ETH = $18

        uint256 userHealthFactor = engine.getHealthFactor(i_user);
        // (18 (wethUsdUpdatedPrice) * 10 (AMOUNT_COLLATERAL) *50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION)) / 10 (totalDscMinted) = 9
        assert(userHealthFactor == 9 ether);
    }

    ////////////////////////
    // LIQUIDATION TESTS //
    //////////////////////
    modifier liquidated() {
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINTED);
        vm.stopPrank();

        int256 wethUsdUpdatedPrice = (1.8 * 1e8);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(wethUsdUpdatedPrice); // 1 ETH = $1.8
        uint256 userHealthFactor = engine.getHealthFactor(i_user);
        console.log("user health factor: ", userHealthFactor);

        ERC20Mock(weth).mint(i_liquidator, COLLATERAL_TO_COVER);

        vm.startPrank(i_liquidator);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_MINTED);
        dsc.approve(address(engine), AMOUNT_MINTED);
        engine.liquidate(weth, i_user, AMOUNT_MINTED); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(i_liquidator, COLLATERAL_TO_COVER);

        vm.startPrank(i_liquidator);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_TO_COVER);
        dsc.approve(address(engine), AMOUNT_MINTED);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_MINTED);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, i_user, AMOUNT_MINTED);
        vm.stopPrank();
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(i_liquidator);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, AMOUNT_MINTED)
            + (engine.getTokenAmountFromUsd(weth, AMOUNT_MINTED) / engine.getLiquidationBonus());

        assert(liquidatorWethBalance == expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, AMOUNT_MINTED)
            + (engine.getTokenAmountFromUsd(weth, AMOUNT_MINTED) / engine.getLiquidationBonus());

        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = engine.getAccountInformation(i_user);

        assert(userCollateralValueInUsd == expectedUserCollateralValueInUsd);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(i_liquidator);
        console.log("liquidator Dsc Minted: ", liquidatorDscMinted);

        assert(liquidatorDscMinted == AMOUNT_MINTED);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = engine.getAccountInformation(i_user);
        console.log("user Dsc Minted: ", userDscMinted);

        assert(userDscMinted == 0);
    }
}
