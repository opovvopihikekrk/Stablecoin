//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {StableCoin} from "src/StableCoin.sol";
import {ADCUEngine} from "src/ADCUEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployADCU is Script {
    address[] public tokenAdresses;
    address[] public priceFeedAddresses;

    function run() external returns(StableCoin, ADCUEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wETHUSDPriceFeed, address wBTCUSDPriceFeed, address wETH, address wBTC, uint deployerKey)
        = helperConfig.activeNetwork();

        tokenAdresses = [wETH, wBTC];
        priceFeedAddresses = [wETHUSDPriceFeed, wBTCUSDPriceFeed];

        vm.startBroadcast(deployerKey);
        StableCoin adcu = new StableCoin();
        ADCUEngine engine = new ADCUEngine(tokenAdresses, priceFeedAddresses, address(adcu));
        adcu.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (adcu, engine, helperConfig);

    }
}