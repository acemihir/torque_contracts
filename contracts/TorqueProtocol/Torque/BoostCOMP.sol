// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BoostAbstract.sol";

import "./interfaces/ISwapRouterV3.sol";
import "./interfaces/INonfungiblePositionManager.sol";

import "./strategies/SushiCOMP.sol";
import "./strategies/UniswapCOMP.sol";

import "./tToken.sol";

contract BoostCOMP is Ownable, ReentrancyGuard {

    // Logic to mint and burn receipt token
    // Logic to split deposits between child vaults
    // Logic to manage fees and rewards

}
