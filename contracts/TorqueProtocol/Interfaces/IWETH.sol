// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

interface IWETH {
    function deposit() external payable;

    function withdraw(uint wad) external;
}