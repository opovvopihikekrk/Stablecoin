//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETHUSDPriceFeed;
        address wBTCUSDPriceFeed;
        address wETH;
        address wBTC;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 1900e8;
    int256 public constant BTC_USD_PRICE = 85000e8;

    NetworkConfig public activeNetwork;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetwork = getSepoliaEthConfig();
        } else if (block.chainid == 31337) {
            activeNetwork = getOrCreateAnvilConfig();
        } else {
            revert("No config for this chain id");
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wETHUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: 0
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetwork.wBTCUSDPriceFeed != address(0)) {
            return activeNetwork;
        }

        vm.startBroadcast();
        MockV3Aggregator ethusdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcusdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 1000e8);
        ERC20Mock wbtcMock = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();
        return NetworkConfig({
            wETHUSDPriceFeed: address(ethusdPriceFeed),
            wBTCUSDPriceFeed: address(btcusdPriceFeed),
            wETH: address(wethMock),
            wBTC: address(wbtcMock),
            deployerKey: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 // Default Anvil key
        });
    }
}
