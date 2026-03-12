//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {ADCUEngine} from "src/ADCUEngine.sol";
import {StableCoin} from "src/StableCoin.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    ADCUEngine engine;
    StableCoin adcu;
    address[] public tokenAdresses;
    address[] usersWithCollateral;
    MockV3Aggregator priceFeed;

    constructor(ADCUEngine _engine, StableCoin _adcu) {
        engine = _engine;
        adcu = _adcu;
        tokenAdresses = engine.getCollateralTokens();

        priceFeed = MockV3Aggregator(engine.getPriceFeed(tokenAdresses[0]));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, type(uint96).max);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);
        engine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 0, engine.getCollateralDeposited(address(collateral), msg.sender));
        if (amount == 0) return;
        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function mintADCU(uint256 amount, uint256 seed) public {
        if (usersWithCollateral.length == 0) return;
        address user = usersWithCollateral[seed % usersWithCollateral.length];
        vm.startPrank(user);
        (uint256 ADCUAmount, uint256 collateralValue) = engine.getAccountInformation(user);
        int256 maxADCUToMint = int256((collateralValue / 2) - ADCUAmount);
        if (maxADCUToMint <= 0) return;
        amount = bound(amount, 1, uint256(maxADCUToMint));
        if (amount == 0) return;
        engine.mintADCU(amount);
        vm.stopPrank();
    }

    // This is a known bug, if the price of the collateral collapses within seconds the invariant might break and the protocol become insolvent
    // function updateCollateralPrice(uint96 newPrice) public {
    //     priceFeed.updateAnswer(int256(uint256(newPrice)));
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        return ERC20Mock(tokenAdresses[collateralSeed % tokenAdresses.length]);
    }
}
