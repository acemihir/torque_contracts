// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OracleLib, AggregatorV3Interface} from "./OracleLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TUSD} from "./TUSD.sol";

contract TUSDEngine is Ownable, ReentrancyGuard {

    error TUSDEngine__NeedsMoreThanZero();
    error TUSDEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error TUSDEngine__MintFailed();
    error TUSDEngine__HealthFactorOk();
    error TUSDEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    TUSD private immutable i_tusd;
    IERC20 private immutable usdcToken;
    AggregatorV3Interface private immutable usdcPriceFeed;

    uint256 private constant LIQUIDATION_THRESHOLD = 90; // will set later
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    mapping(address => uint256) private s_collateralDeposited;
    mapping(address => uint256) private s_TUSDMinted;
    
    address private treasuryAddress;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, uint256 amount);
    event TUSDMinted(address indexed user, uint256 amount);
    event TUSDBurned(address indexed user, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        require(amount > 0, "Amount must be more than zero");
        _;
    }

    constructor(address initialOwner, address usdcTokenAddress, address usdcPriceFeedAddress, address tusdAddress) Ownable(initialOwner) {
        i_tusd = TUSD(tusdAddress);
        usdcToken = IERC20(usdcTokenAddress);
        usdcPriceFeed = AggregatorV3Interface(usdcPriceFeedAddress);
    }

    function depositCollateralAndMintTusd(uint256 amountCollateral, uint256 amountTusdToMint) external moreThanZero(amountCollateral) {
        depositCollateral(amountCollateral);
        mintTusd(amountTusdToMint);
    }

    function redeemCollateralForTusd(uint256 amountCollateral, uint256 amountTusdToBurn) external moreThanZero(amountCollateral) {
        _burnTusd(amountTusdToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender] += amountCollateral;
        require(usdcToken.transferFrom(msg.sender, address(this), amountCollateral), "Transfer failed");
        emit CollateralDeposited(msg.sender, address(usdcToken), amountCollateral);
    }

    function redeemCollateral(uint256 amountCollateral) external moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(amountCollateral, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintTusd(uint256 amountTusdToMint) public moreThanZero(amountTusdToMint) nonReentrant {
        s_TUSDMinted[msg.sender] += amountTusdToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        require(i_tusd.mint(msg.sender, amountTusdToMint), "Mint failed");
        emit TUSDMinted(msg.sender, amountTusdToMint);
    }
    
    function burnTusd(uint256 amount) external moreThanZero(amount) {
        _burnTusd(amount, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TUSDEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnTusd(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TUSDEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        treasuryAddress = _treasuryAddress;
    }

    function deployReserves(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(usdcToken.balanceOf(address(this)) >= amount, "Insufficient balance");
        require(usdcToken.transfer(treasuryAddress, amount), "Transfer failed");
    }

    function _redeemCollateral(uint256 amountCollateral, address to) private {
        require(s_collateralDeposited[to] >= amountCollateral, "Insufficient collateral");
        s_collateralDeposited[from] -= amountCollateral;
        require(usdcToken.transfer(to, amountCollateral), "Transfer failed");
        emit CollateralRedeemed(address(this), to, amountCollateral);
    }

    function _burnTusd(uint256 amountTusdToBurn, address onBehalfOf) private {
        require(s_TUSDMinted[onBehalfOf] >= amountTusdToBurn, "Insufficient TUSD balance");
        s_TUSDMinted[onBehalfOf] -= amountTusdToBurn;
        require(i_tusd.transferFrom(onBehalfOf, address(this), amountTusdToBurn), "Transfer failed");
        i_tusd.burn(amountTusdToBurn);
        emit TUSDBurned(onBehalfOf, amountTusdToBurn);
    }

    function _getAccountInformation(address user) private view returns (uint256 totalTusdMinted, uint256 collateralValueInUsd) {
        totalTusdMinted = s_TUSDMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
        return (totalTusdMinted, collateralValueInUsd);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalTusdMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalTusdMinted, collateralValueInUsd);
    }

    function _getUsdValue(uint256 amount) private view returns (uint256) {
        (, int256 price,,,) = usdcPriceFeed.latestRoundData();
        return (uint256(price) * amount) / FEED_PRECISION;
    }

    function _calculateHealthFactor(uint256 totalTusdMinted, uint256 collateralValueInUsd) internal pure returns (uint256) {
        if (totalTusdMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalTusdMinted;
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        require(_healthFactor(user) >= MIN_HEALTH_FACTOR, "Health factor broken");
    }

    function calculateHealthFactor(uint256 totalTusdMinted, uint256 collateralValueInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(totalTusdMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user) external view returns (uint256 totalTusdMinted, uint256 collateralValueInUsd) {
        return _getAccountInformation(user);
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amountCollateral = s_collateralDeposited[user];
        return _getUsdValue(amountCollateral);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getTusd() external view returns (address) {
        return address(i_tusd);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}