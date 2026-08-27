// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MeshSplitter} from "./MeshSplitter.sol";

/// @title MeshSplitterFactory
/// @notice Deploys one MeshSplitter per MeshEcosystem project. The Pons
/// locker address and the MeshGateway treasury are fixed at factory
/// deployment, so every splitter created here carries the same immutable
/// 10 percent treasury share. The factory has no owner and no admin
/// functions; anyone can deploy a splitter.
contract MeshSplitterFactory {
    address public immutable locker;
    address public immutable treasury;

    /// @notice All splitters ever deployed, for off-chain enumeration.
    address[] public splitters;

    event SplitterCreated(
        address indexed splitter, address indexed payout, address indexed creator
    );

    error ZeroAddress();

    constructor(address locker_, address treasury_) {
        if (locker_ == address(0) || treasury_ == address(0)) revert ZeroAddress();
        locker = locker_;
        treasury = treasury_;
    }

    /// @notice Deploys a new splitter paying 90 percent to `payout`.
    function createSplitter(address payout) external returns (address splitter) {
        splitter = address(new MeshSplitter(locker, treasury, payout));
        splitters.push(splitter);
        emit SplitterCreated(splitter, payout, msg.sender);
    }

    function splitterCount() external view returns (uint256) {
        return splitters.length;
    }
}
