//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployADCU} from "script/DeployADCU.s.sol";
import {StableCoin} from "src/StableCoin.sol";
import {ADCUEngine} from "src/ADCUEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";


contract ADCUEngineTest is Test {
    // The test contract for ADCUEngine will be implemented here.
    // This is a placeholder for the actual test code.
    // You can add your test functions and logic here.
    // For example:

    DeployADCU public deployer;
    StableCoin public adcu;
    ADCUEngine public engine;
    HelperConfig public config;

    address public ETHUSDPriceFeed;
    address public WETH;
    address public BTCUSDPriceFeed;
    address public WBTC;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint public constant DEFAULT_COLLATERAL_AMOUNT = 1 ether;
    uint public constant INITIAL_WETH_BALANCE = 10 ether;
    uint public constant MINT_AMOUNT = 500 ether;

    function setUp() public {
        deployer = new DeployADCU();
        (adcu, engine, config) = deployer.run(); 
        (ETHUSDPriceFeed, BTCUSDPriceFeed, WETH, WBTC, ) = config.activeNetwork();

        ERC20Mock(WETH).mint(USER, INITIAL_WETH_BALANCE);
        ERC20Mock(WETH).mint(LIQUIDATOR, INITIAL_WETH_BALANCE); // Mint some WETH for the user
    }

    // Constructor tests

    function testRevertsIfPriceFeedAddressesAndTokenAddressesAreDifferentLength() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        tokenAddresses[0] = WETH;
        priceFeedAddresses[0] = ETHUSDPriceFeed;
        priceFeedAddresses[1] = BTCUSDPriceFeed; // Extra address to make it different length

        vm.expectRevert(ADCUEngine.ADCUEngine__DifferentLengthForTokensAndPriceFeeds.selector);
        new ADCUEngine(tokenAddresses, priceFeedAddresses, address(adcu));
    }

    //Price tests

    function testGetUsdValue() public {
        uint256 amount = 10e18; // 1 token with 8 decimals
        uint256 expectedValue = 19000e18; // 1900 USD for 1 ETH
        uint256 actualValue = engine.getUSDValue(WETH, amount); // Assuming 0 is the index for wETH
        assertEq(actualValue, expectedValue, "getUsdValue failed");
    }

    function testGetTokenAmountFromUSD() public {
        uint256 amount = 1900e8; // 1900 USD
        uint256 expectedValue = 1e8; // 1 token with 8 decimals
        uint256 actualValue = engine.getTokenAmountFromUSD(WETH, amount); // Assuming 0 is the index for wETH
        assertEq(actualValue, expectedValue, "getTokenValue failed");
    }

    //Deposit collateral tests
    function testCollateralIsZero() public{
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), DEFAULT_COLLATERAL_AMOUNT);
        vm.expectRevert(ADCUEngine.ADCUEngine__AmountIsZero.selector);
        engine.depositCollateral(WETH, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock token = new ERC20Mock("Random Token", "RAN", USER, INITIAL_WETH_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(ADCUEngine.ADCUEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(token), DEFAULT_COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    modifier depositedCollateral(){
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(engine), DEFAULT_COLLATERAL_AMOUNT);
        engine.depositCollateral(WETH, DEFAULT_COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalADCUMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        assertEq(totalADCUMinted, 0);
        assertEq(DEFAULT_COLLATERAL_AMOUNT, engine.getTokenAmountFromUSD(WETH, collateralValueInUSD));
       
    }

    /// ---------------------- MINT TESTS ----------------------
    
    function testCannotMintWithoutCollateral() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(ADCUEngine.ADCUEngine__NeedMoreCollateral.selector, 0));
        engine.mintADCU(MINT_AMOUNT);
        vm.stopPrank();
    }

    function testCannotMintZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(ADCUEngine.ADCUEngine__AmountIsZero.selector);
        engine.mintADCU(0);
        vm.stopPrank();
    }

     function testCanMintWithEnoughCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintADCU(MINT_AMOUNT);
        (uint256 totalMinted, ) = engine.getAccountInformation(USER);
        assertEq(totalMinted, MINT_AMOUNT, "Mint amount incorrect");
        vm.stopPrank();
    }

    function testMintFailsIfHealthFactorTooLow() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(ADCUEngine.ADCUEngine__NeedMoreCollateral.selector, 0));
        engine.mintADCU(MINT_AMOUNT * 10 ** 30); // Mint a huge amount to make the health factor too low
        vm.stopPrank();
    }

    /// ---------------------- BURN TESTS ----------------------

    function testCannotBurnMoreThanMinted() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintADCU(MINT_AMOUNT);
        vm.expectRevert();
        engine.burnADCU(MINT_AMOUNT * 2);
        vm.stopPrank();
    }

    function testCannotBurnZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(ADCUEngine.ADCUEngine__AmountIsZero.selector);
        engine.burnADCU(0);
        vm.stopPrank();
    }

    function testCanBurnADCU() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintADCU(MINT_AMOUNT);
        adcu.approve(address(engine), MINT_AMOUNT);
        engine.burnADCU(MINT_AMOUNT / 2);
        (uint256 totalMinted, ) = engine.getAccountInformation(USER);
        assertEq(totalMinted, MINT_AMOUNT / 2, "Burn failed");
        vm.stopPrank();
    }

    function testCannotLiquidateHealthyUser() public depositedCollateral {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(ADCUEngine.ADCUEngine__HealthFactorOK.selector);
        engine.liquidate(WETH, USER, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testCanLiquidateUnderCollateralizedUser() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintADCU(MINT_AMOUNT);
        vm.stopPrank();

        dropPriceFeed();

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(WETH).approve(address(engine), DEFAULT_COLLATERAL_AMOUNT * 3);
        engine.depositCollateral(WETH, DEFAULT_COLLATERAL_AMOUNT * 3);
        engine.mintADCU(MINT_AMOUNT);
        adcu.approve(address(engine), MINT_AMOUNT);
        engine.liquidate(WETH, USER, MINT_AMOUNT/2);
        vm.stopPrank();
    }

    function testCanGetAccountInformation() public depositedCollateral {
        (uint256 totalMinted, uint256 collateralValue) = engine.getAccountInformation(USER);
        assertEq(totalMinted, 0, "Mint amount should be 0");
        assertGt(collateralValue, 0, "Collateral value should be greater than 0");
    }

    function testCanGetHealthFactor() public depositedCollateral {
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertGt(healthFactor, 1e18, "Health factor should be above 1");
    }

    function dropPriceFeed() internal {
        
        MockV3Aggregator(ETHUSDPriceFeed).updateAnswer(900e8); // Drops the price from 1900 to 700 USD
    }


        
}