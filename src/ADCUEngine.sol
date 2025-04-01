//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {StableCoin} from "src/StableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title ADCUEngine
 * @author Lucas Conesa
 *
 * The system is designed to be as minimal as possible, and have the tokens mantain a
 * 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our ADCU system should always be "overcollaterized". At no point, should the value of all collateral
 * <= the value of all the ADCU.
 *
 * @notice This contract is the core of the ADCU System. It handles all the logic for mining and redeeming
 * ADCU, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based in the MakeDAO DSS (DAI) system
 */
contract ADCUEngine is ReentrancyGuard {
    //Errors
    error ADCUEngine__AmountIsZero();
    error ADCUEngine_DifferentLengthForTokensAndPriceFeeds();
    error ADCUEngine__TokenNotAllowed();
    error ADCUEngine__TransferFailed();
    error ADCUEngine__NeedMoreCollateral(uint healthFactor);

    //State Variables
    uint private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint16 private constant DECIMALS = 18;
    uint private constant LIQUIDATION_TRESHOLD = 50;
    uint8 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token=> address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint amount)) private s_collateralDeposited;
    mapping(address user => uint amountADCUMinted) private s_ADCUMinted;
    address[] private s_collateralTokens;

    StableCoin private immutable i_ADCU;

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint indexed amount);

    //Modifiers
    modifier moreThanZero(uint amount) {
        if (amount <= 0) {
            revert ADCUEngine__AmountIsZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert ADCUEngine__TokenNotAllowed();
        }
        _;
    }

    //Functions
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address ADCUaddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert ADCUEngine_DifferentLengthForTokensAndPriceFeeds();
        }

        for (uint i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_ADCU = StableCoin(ADCUaddress);
        s_collateralTokens = tokenAddresses;
    }

    //External functions
    function depositCollateralAndMintADCU() external {}

    /**
     *@notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint amount
    )
        external
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success){revert ADCUEngine__TransferFailed();}
    }

    function redeemCollateralForADCU() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI
     * @param amountADCUToMint The amount of ADCU to mint.
     * @notice the must have more collaterall value than the minimum treshold.
     */
    function mintADCU(uint amountADCUToMint) external moreThanZero(amountADCUToMint) nonReentrant{
        s_ADCUMinted[msg.sender] += amountADCUToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnADCU() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //Private and internal view functions
    function _getAccountInformation(address user) private view returns(uint, uint){
        uint totalADCUMinted = s_ADCUMinted[user];
        uint collateralValueInUSD = getAccountCollateralValue(user);
        return (totalADCUMinted, collateralValueInUSD);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns(uint){
        (uint totalADCUMinted, uint collateralUSDValue) = _getAccountInformation(user);
        uint collateralAdjusted = (collateralUSDValue * LIQUIDATION_TRESHOLD) / 100;
        return(collateralAdjusted * 10 ** DECIMALS) / totalADCUMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR){
            revert ADCUEngine__NeedMoreCollateral(healthFactor);
        }
    }

    //Public and external view functions
    function getAccountCollateralValue(address user) public view returns(uint){
        uint totalUSDValue = 0;
        for (uint i = 0; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint amount = s_collateralDeposited[user][token];
            totalUSDValue += getUSDValue(token, amount);
        }
        return totalUSDValue;
    }

    function getUSDValue(address token, uint amount) public view returns(uint){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint(price) * ADDITIONAL_FEED_PRECISION * amount) / 10 ** DECIMALS;
    }
}