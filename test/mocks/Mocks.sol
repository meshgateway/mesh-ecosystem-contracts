// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPonsLaunchLocker} from "../../src/interfaces/IPonsLaunchLocker.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Mirrors the PonsLaunchLocker behavior the splitter depends on:
/// the caller authorization set (owner, deployer, fee recipient, approved
/// collector) and paying the creator share to the redirect target.
contract MockLocker {
    error TokenNotFound();
    error NotAuthorized();
    error NoFeesToCollect();
    error NotDeployer();

    address public owner;
    mapping(address => address) public feeRedirects;
    mapping(address => bool) public feeCollectors;
    mapping(address => IPonsLaunchLocker.LaunchedToken) internal launched;

    // Pending creator-share fees to hand out on the next collectFees call.
    mapping(address => uint256) public pendingToken;
    mapping(address => uint256) public pendingPaired;

    constructor() {
        owner = msg.sender;
    }

    function register(address token, address deployer, address pairedToken) external {
        launched[token] = IPonsLaunchLocker.LaunchedToken({
            token: token,
            deployer: deployer,
            pairedToken: pairedToken,
            positionManager: address(0),
            positionId: 1,
            dexId: 1,
            launchConfigId: 1,
            restrictionsEndBlock: 0,
            supply: 1e27,
            isToken0: false,
            poolFee: 10_000,
            exists: true,
            initialBuyAmount: 0
        });
    }

    function setPending(address token, uint256 tokenAmount, uint256 pairedAmount) external {
        pendingToken[token] = tokenAmount;
        pendingPaired[token] = pairedAmount;
    }

    function setFeeRedirect(address token, address newFeeWallet) external {
        IPonsLaunchLocker.LaunchedToken memory t = launched[token];
        if (!t.exists) revert TokenNotFound();
        if (msg.sender != t.deployer) revert NotDeployer();
        feeRedirects[token] = newFeeWallet;
    }

    function collectFees(address token) external returns (uint256 amount0, uint256 amount1) {
        IPonsLaunchLocker.LaunchedToken memory t = launched[token];
        if (!t.exists) revert TokenNotFound();

        address recipient = feeRedirects[token];
        if (recipient == address(0)) recipient = t.deployer;
        if (
            msg.sender != owner && msg.sender != t.deployer && msg.sender != recipient
                && !feeCollectors[msg.sender]
        ) {
            revert NotAuthorized();
        }

        amount0 = pendingPaired[token];
        amount1 = pendingToken[token];
        if (amount0 == 0 && amount1 == 0) revert NoFeesToCollect();
        pendingToken[token] = 0;
        pendingPaired[token] = 0;

        if (amount1 > 0) MockERC20(token).mint(recipient, amount1);
        if (amount0 > 0) MockERC20(t.pairedToken).mint(recipient, amount0);
    }

    function getLaunchedToken(address token)
        external
        view
        returns (IPonsLaunchLocker.LaunchedToken memory)
    {
        return launched[token];
    }
}
