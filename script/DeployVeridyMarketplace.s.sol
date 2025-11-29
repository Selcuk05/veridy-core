// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {VeridyMarketplace} from "../src/VeridyMarketplace.sol";

/// @notice Deploys VeridyMarketplace
contract DeployVeridyMarketplace is Script {
    address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDT_SEPOLIA = 0xd077A400968890Eacc75cdc901F0356c943e4fDb; // Tether USDT on sepolia
    address constant USDT_ARBITRUM = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // Bridged USDT on Arbitrum One

    VeridyMarketplace public marketplace;

    function run() external returns (VeridyMarketplace) {
        address usdtAddress = getUsdtAddress();

        console.log("Chain ID:", block.chainid);
        console.log("USDT:", usdtAddress);

        vm.startBroadcast();
        marketplace = new VeridyMarketplace();
        marketplace.initialize(usdtAddress);
        vm.stopBroadcast();

        console.log("Deployed to:", address(marketplace));
        return marketplace;
    }

    function getUsdtAddress() internal view returns (address) {
        if (block.chainid == 1) return USDT_MAINNET;
        if (block.chainid == 11155111) return USDT_SEPOLIA;
        if (block.chainid == 42161) return USDT_ARBITRUM;
        if (block.chainid == 31337) revert("Use DeployVeridyMarketplaceLocal");
        revert("Unsupported chain");
    }
}

/// @notice Deploys VeridyMarketplace with mock USDT for local testing
contract DeployVeridyMarketplaceLocal is Script {
    uint256 constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (VeridyMarketplace marketplace, address mockUsdt) {
        address deployer = vm.addr(ANVIL_DEFAULT_KEY);

        vm.startBroadcast(ANVIL_DEFAULT_KEY);

        MockUSDT usdt = new MockUSDT();
        mockUsdt = address(usdt);

        marketplace = new VeridyMarketplace();
        marketplace.initialize(mockUsdt);

        usdt.mint(deployer, 1_000_000 * 10 ** 6);

        vm.stopBroadcast();

        console.log("Marketplace:", address(marketplace));
        console.log("Mock USDT:", mockUsdt);
    }
}

contract MockUSDT {
    string public name = "Mock USDT";
    string public symbol = "USDT";
    uint8 public decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
