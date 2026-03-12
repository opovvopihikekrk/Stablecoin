//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {StableCoin} from "src/StableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/Libraries/OracleLib.sol";

/**
 * @title ADCUEngine
 * @author Cemerian
 *
 * The system is designed to be as minimal as possible, and have the tokens mantain a
 * 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically Stable
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
    error ADCUEngine__DifferentLengthForTokensAndPriceFeeds();
    error ADCUEngine__TokenNotAllowed();
    error ADCUEngine__TransferFailed();
    error ADCUEngine__NeedMoreCollateral(uint256 healthFactor);
    error ADCUEngine__MintFailed();
    error ADCUEngine__NotEnoughCollateralAmount();
    error ADCUEngine__HealthFactorOK();
    error ADCUEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    //State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint16 private constant DECIMALS = 18;
    uint256 private constant LIQUIDATION_TRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountADCUMinted) private s_ADCUMinted;
    address[] private s_collateralTokens;

    StableCoin private immutable i_ADCU;

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    //Modifiers
    modifier moreThanZero(uint256 amount) {
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
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address ADCUaddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert ADCUEngine__DifferentLengthForTokensAndPriceFeeds();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_ADCU = StableCoin(ADCUaddress);
        s_collateralTokens = tokenAddresses;
    }

    //External functions
    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountADCUToMint The amount of ADCU to mint.
     * @notice this function will deposit the collateral and mint the ADCU in one transaction.
     */
    function depositCollateralAndMintADCU(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountADCUToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintADCU(amountADCUToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) revert ADCUEngine__TransferFailed();
    }

    /**
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of collateral to redeem
     * @param amountADCUToBurn The amount of ADCU to burn.
     * @notice this function will burn the ADCU and redeem the collateral in one transaction.
     */
    function redeemCollateralForADCU(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountADCUToBurn) external {
        burnADCU(amountADCUToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        uint256 amountDeposited = s_collateralDeposited[msg.sender][tokenCollateralAddress];
        if (amountDeposited < amountCollateral) {
            revert ADCUEngine__NotEnoughCollateralAmount();
        }
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountADCUToMint The amount of ADCU to mint.
     * @notice they must have more collateral value than the minimum treshold.
     */
    function mintADCU(uint256 amountADCUToMint) public moreThanZero(amountADCUToMint) nonReentrant {
        s_ADCUMinted[msg.sender] += amountADCUToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_ADCU.mint(msg.sender, amountADCUToMint);
        if (!minted) {
            revert ADCUEngine__MintFailed();
        }
    }

    function burnADCU(uint256 amount) public moreThanZero(amount){
        _burnADCU(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender); //Might be removed
    }

    /**
     * @notice Liquidate a user if their health factor is below the minimum treshold.
     * @param collateral The address of the collateral token to liquidate
     * @param user The address of the user to liquidate
     * @param debtToCover The amount of ADCU to burn
     * @notice The liquidator can partially liquidate a user
     * @notice The liquidator will get a liquidation bonus
     * @notice This function assumes that the protocol is overcollateralized
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
        uint256 initialHealthFactor = _healthFactor(user);
        if(initialHealthFactor >= MIN_HEALTH_FACTOR) {
            revert ADCUEngine__HealthFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnADCU(user, msg.sender, debtToCover);

        uint256 endingHealthFactor = _healthFactor(user);
        if(endingHealthFactor < MIN_HEALTH_FACTOR) {
            revert ADCUEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //Private and internal view functions
    function _getAccountInformation(address user) private view returns (uint256, uint256) {
        uint256 totalADCUMinted = s_ADCUMinted[user];
        uint256 collateralValueInUSD = getAccountCollateralValue(user);
        return (totalADCUMinted, collateralValueInUSD);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalADCUMinted, uint256 collateralUSDValue) = _getAccountInformation(user);
        if (totalADCUMinted == 0) {
            return type(uint256).max; // User has no ADCU minted, so they are not at risk of liquidation
        }
        uint256 collateralAdjusted = (collateralUSDValue * LIQUIDATION_TRESHOLD) / 100;
        return (collateralAdjusted * 10 ** DECIMALS) / totalADCUMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert ADCUEngine__NeedMoreCollateral(healthFactor);
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert ADCUEngine__TransferFailed();
    }

    /**
     * @dev Do not call unless the function calling it is checking for health factors being broken
     */
    function _burnADCU(address onBehalfOf, address liquidator, uint256 amount) private {
        s_ADCUMinted[onBehalfOf] -= amount;
        bool burned = i_ADCU.transferFrom(liquidator, address(this), amount);
        if (!burned) {
            revert ADCUEngine__TransferFailed();
        }
        i_ADCU.burn(amount);
    }

    //Public and external view functions
    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalUSDValue = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalUSDValue += getUSDValue(token, amount);
        }
        return totalUSDValue;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheck();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / 10 ** DECIMALS;
    }

    function getTokenAmountFromUSD(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheck();
        return (amount * 10 ** DECIMALS) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user) external view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns(uint){
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralDeposited(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
