//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StableCoin
 * @author Cemerian
 * Collateral: WETH & WBTC
 * Minting: Algorithmic
 * Stability: Pegged to USD
 *
 * This is the contract meant to be governed by ADCUEngine. This contract is just the ERC20 implementation
 * of the stablecoin system
 */

contract StableCoin is ERC20Burnable, Ownable {
    error StableCoin__AmountIsZero();
    error StableCoin__NotEnoughFunds();
    error StableCoin__ToZeroAddress();

    constructor() ERC20("Algorithmic Decentralized Collaterlalized USD", "ADCU") Ownable() {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert StableCoin__AmountIsZero();
        }
        if (balance < _amount) {
            revert StableCoin__NotEnoughFunds();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin__ToZeroAddress();
        }
        if (_amount <= 0) {
            revert StableCoin__AmountIsZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
