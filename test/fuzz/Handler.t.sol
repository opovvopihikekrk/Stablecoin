//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ADCUEngine} from "src/ADCUEngine.sol";
import {StableCoin} from "src/StableCoin.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract Handler is Test{
    ADCUEngine engine;
    StableCoin adcu;
    address[] public tokenAdresses;
    constructor(ADCUEngine _engine, StableCoin _adcu){
        engine = _engine;
        adcu = _adcu;
        tokenAdresses = engine.getCollateralTokens();
    }

    function depositCollateral(uint collateralSeed, uint amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, type(uint96).max);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);
        engine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint collateralSeed, uint amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 0, engine.getCollateralDeposited(address(collateral), msg.sender));
        if(amount == 0) return;
        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function mintADCU(uint amount) public{
        vm.startPrank(msg.sender);
        (uint ADCUAmount, uint collateralValue) = engine.getAccountInformation(msg.sender);
        int maxADCUToMint = int((collateralValue / 2) - ADCUAmount);
        if(maxADCUToMint <= 0) return;
        amount = bound(amount, 1, uint(maxADCUToMint));
        if(amount == 0) return;
        engine.mintADCU(amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint collateralSeed) internal view returns (ERC20Mock) {
        return ERC20Mock(tokenAdresses[collateralSeed % tokenAdresses.length]);
    }
}