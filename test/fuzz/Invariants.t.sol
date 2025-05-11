//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StableCoin} from "src/StableCoin.sol";
import {ADCUEngine} from "src/ADCUEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployADCU} from "script/DeployADCU.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InvariantsTest is StdInvariant{
    DeployADCU deployer;
    ADCUEngine engine;
    StableCoin adcu;
    HelperConfig config;
    address weth;
    address btc;
    Handler handler;

    function setUp() external {
        deployer = new DeployADCU();
        (adcu, engine, config) = deployer.run();
        (,,weth,btc,) = config.activeNetwork();
        handler = new Handler(engine, adcu);
        targetContract(address(handler));
    }

    function invariantProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = adcu.totalSupply();
        uint256 totalWeth = IERC20(weth).balanceOf(address(engine));
        uint256 totalBtc = IERC20(btc).balanceOf(address(engine));

        uint256 wethValue = engine.getUSDValue(weth, totalWeth);
        uint256 btcValue = engine.getUSDValue(btc, totalBtc);

        assert(wethValue + btcValue >= totalSupply);
    }
}