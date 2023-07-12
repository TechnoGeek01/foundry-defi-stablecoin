// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Sudharsan R
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token = $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized".
 * At no point, should the value of all collateral <= the $ backed value of all the DSC
 *
 * @notice This contract is the core of the DSC system.
 * It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 *
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /*********************************/
    //            ERRORS             //
    /*********************************/

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint userHealthFactor);
    error DSCEngine__MintFailed();

    /*********************************/
    //        STATE VARIABLES        //
    /*********************************/
    uint private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint private constant PRECISION = 1e18;
    uint private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint private constant LIQUIDATION_PRECISION = 100;
    uint private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint amount))
        private s_collateralDeposited;
    mapping(address user => uint amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /*********************************/
    //             EVENTS            //
    /*********************************/

    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint indexed amountCollateral
    );

    /*********************************/
    //         MODIFIERS             //
    /*********************************/

    modifier moreThanZero(uint amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*********************************/
    //         FUNCTIONS             //
    /*********************************/

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        //  USD Price Feeds.
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*********************************/
    //        EXTERNAL FUNCTIONS     //
    /*********************************/

    function depositCollateralAndMintDsc() external {}

    /**
     *
     * @notice Followes CEI pattern
     * @param tokenCollateralAddress The address of the tokne to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     *@notice Follows CEI pattern
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(
        uint amountDscToMint
    ) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /*******************************************/
    //   PRIVATE & INTERNAL VIEW FUNCTIONS     //
    /*******************************************/

    function _getAccountInformation(
        address user
    ) private view returns (uint totalDscMinted, uint collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     *
     * Returns how close to liquidation a user is
     * If a user's health factor goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint) {
        (
            uint totalDscMinted,
            uint collateralValueInUsd
        ) = _getAccountInformation(user);
        uint collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return ((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // check health factor (do they have enough collateral)
        // revert if they don't have a good health factor
        uint userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /*******************************************/
    //   PUBLIC & EXTERNAL VIEW FUNCTIONS      //
    /*******************************************/

    function getAccountCollateralValue(
        address user
    ) public view returns (uint totalCollateralValueInUsd) {
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint amount
    ) public view returns (uint) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int price, , , ) = priceFeed.latestRoundData();

        return (uint(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }
}