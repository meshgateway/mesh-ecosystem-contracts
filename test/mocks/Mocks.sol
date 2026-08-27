// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

/// @notice Mirrors the V2FeeEscrow behavior the splitter depends on:
/// balances credit per recipient and claim pays msg.sender's own balance.
contract MockFeeEscrow {
    error NoBalance();
    error TransferFailed();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) internal tokenBalances;

    function credit(address recipient) external payable {
        balanceOf[recipient] += msg.value;
    }

    function creditToken(address recipient, address token, uint256 amount) external {
        MockERC20(token).mint(address(this), amount);
        tokenBalances[recipient][token] += amount;
    }

    function balanceOfToken(address recipient, address token) external view returns (uint256) {
        return tokenBalances[recipient][token];
    }

    function claim() external returns (uint256 amount) {
        amount = balanceOf[msg.sender];
        if (amount == 0) revert NoBalance();
        balanceOf[msg.sender] = 0;
        (bool sent,) = payable(msg.sender).call{value: amount}("");
        if (!sent) revert TransferFailed();
    }

    function claimToken(address token) external returns (uint256 amount) {
        amount = tokenBalances[msg.sender][token];
        if (amount == 0) revert NoBalance();
        tokenBalances[msg.sender][token] = 0;
        MockERC20(token).transfer(msg.sender, amount);
    }
}

/// @notice Mirrors the PonsV2LaunchFactory recipiency rule: only the
/// current creator fee recipient can pass the role on.
contract MockLaunchFactory {
    error TokenNotFound();
    error NotCreatorFeeRecipient();
    error ZeroAddress();

    mapping(address => address) public creatorFeeRecipient;

    function register(address token, address recipient) external {
        creatorFeeRecipient[token] = recipient;
    }

    function transferCreatorFeeRecipient(address token, address newRecipient) external {
        if (creatorFeeRecipient[token] == address(0)) revert TokenNotFound();
        if (msg.sender != creatorFeeRecipient[token]) revert NotCreatorFeeRecipient();
        if (newRecipient == address(0)) revert ZeroAddress();
        creatorFeeRecipient[token] = newRecipient;
    }
}
