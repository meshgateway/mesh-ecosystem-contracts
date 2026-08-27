// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MeshSplitter} from "./MeshSplitter.sol";

/// @title MeshSplitterFactory
/// @notice Deploys one MeshSplitter per MeshEcosystem project. The Pons v2
/// factory, the Pons fee escrow, and the MeshGateway treasury are fixed at
/// factory deployment, so every splitter created here carries the same
/// immutable 10 percent treasury share. The factory has no owner and no
/// admin functions; anyone can deploy a splitter.
contract MeshSplitterFactory {
    address public immutable ponsFactory;
    address public immutable escrow;
    address public immutable treasury;

    /// @notice All splitters ever deployed, for off-chain enumeration.
    address[] public splitters;

    event SplitterCreated(
        address indexed splitter, address indexed payout, address indexed creator
    );

    error ZeroAddress();

    constructor(address ponsFactory_, address escrow_, address treasury_) {
        if (ponsFactory_ == address(0) || escrow_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        ponsFactory = ponsFactory_;
        escrow = escrow_;
        treasury = treasury_;
    }

    /// @notice Deploys a new splitter paying 90 percent to `payout`.
    function createSplitter(address payout) external returns (address splitter) {
        splitter = address(new MeshSplitter(ponsFactory, escrow, treasury, payout));
        splitters.push(splitter);
        emit SplitterCreated(splitter, payout, msg.sender);
    }

    function splitterCount() external view returns (uint256) {
        return splitters.length;
    }
}
