// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPricefeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000 * 1e8;
    int256 public constant BTC_USD_PRICE = 1000 * 1e8;
    uint256 public constant INITIAL_BALANCE = 1000 * 1e8;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getLocalConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPricefeed != address(0)) {
            return activeNetworkConfig;
        }

        return NetworkConfig({
            wethUsdPricefeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getLocalConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPricefeed != address(0)) {
            return activeNetworkConfig;
        }

        return _createLocalConfig();
    }

    function _createLocalConfig() private returns (NetworkConfig memory) {
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeedMock =
            new MockV3Aggregator({_decimals: DECIMALS, _initialAnswer: ETH_USD_PRICE});
        ERC20Mock wethMock = new ERC20Mock({
            name: "wraped etherum",
            symbol: "WETH",
            initialAccount: msg.sender,
            initialBalance: INITIAL_BALANCE
        });
        MockV3Aggregator btcUsdPriceFeedMock =
            new MockV3Aggregator({_decimals: DECIMALS, _initialAnswer: BTC_USD_PRICE});
        ERC20Mock wbtcMock = new ERC20Mock({
            name: "wraped bitcoin",
            symbol: "WBTC",
            initialAccount: msg.sender,
            initialBalance: INITIAL_BALANCE
        });
        vm.stopBroadcast();

        NetworkConfig memory localConfig = NetworkConfig({
            wethUsdPricefeed: address(ethUsdPriceFeedMock),
            wbtcUsdPriceFeed: address(btcUsdPriceFeedMock),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: vm.envUint("LOCAL_PRIVATE_KEY")
        });

        return localConfig;
    }
}
