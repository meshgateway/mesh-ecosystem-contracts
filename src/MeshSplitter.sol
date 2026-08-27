// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPonsV2FeeEscrow, IPonsV2LaunchFactory} from "./interfaces/IPonsV2.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title MeshSplitter
/// @notice Receives the Pons v2 creator fees of a MeshEcosystem project
/// and splits them between the MeshGateway treasury and the project payout
/// wallet at a fixed, immutable ratio. One splitter is deployed per project.
///
/// How it is wired up:
/// 1. MeshSplitterFactory deploys this contract with the project payout
///    wallet; the treasury address and share are fixed at deployment.
/// 2. The current creator fee recipient calls
///    transferCreatorFeeRecipient(token, splitter) on the Pons v2 launch
///    factory. From then on creator fees credit to this contract's balance
///    in the Pons fee escrow, in the launch's pairing asset.
/// 3. Anyone may call claimAndRelease. It pulls the escrow balance and
///    pays out both parties in the same transaction.
///
/// Trust properties:
/// - The treasury address and its share are immutable. Nobody, including
///   the treasury, can raise the cut after deployment.
/// - Claiming and releasing are permissionless. If MeshGateway disappears,
///   the project can always trigger its own 90 percent payout.
/// - The project can leave at any time: the payout wallet can transfer the
///   creator fee recipiency onward without MeshGateway's involvement.
/// - The payout wallet can only be rotated by the current payout wallet.
/// - There is no owner, no upgrade path, and no pause switch.
contract MeshSplitter {
    /// @notice Treasury share in basis points (1000 = 10 percent).
    uint256 public constant TREASURY_SHARE_BPS = 1_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IPonsV2LaunchFactory public immutable ponsFactory;
    IPonsV2FeeEscrow public immutable escrow;
    address public immutable treasury;

    /// @notice Wallet receiving the project share of every release.
    address public payout;

    event Claimed(address indexed asset, uint256 amount);
    event Released(address indexed asset, uint256 treasuryAmount, uint256 payoutAmount);
    event PayoutUpdated(address indexed previousPayout, address indexed newPayout);
    event FeeRecipientTransferred(address indexed token, address indexed newRecipient);

    error ZeroAddress();
    error NotPayout();
    error NativeTransferFailed();
    error TokenTransferFailed();

    constructor(address ponsFactory_, address escrow_, address treasury_, address payout_) {
        if (
            ponsFactory_ == address(0) || escrow_ == address(0) || treasury_ == address(0)
                || payout_ == address(0)
        ) {
            revert ZeroAddress();
        }
        ponsFactory = IPonsV2LaunchFactory(ponsFactory_);
        escrow = IPonsV2FeeEscrow(escrow_);
        treasury = treasury_;
        payout = payout_;
    }

    /// @notice Receives the escrow's native ETH payout on claim.
    receive() external payable {}

    /// @notice Claims this splitter's native ETH balance from the Pons fee
    /// escrow and releases it. Permissionless and idempotent: a zero escrow
    /// balance is a no-op, so keeper crons can call it blindly.
    function claimAndRelease() external {
        if (escrow.balanceOf(address(this)) > 0) {
            uint256 amount = escrow.claim();
            emit Claimed(address(0), amount);
        }
        release(address(0));
    }

    /// @notice Same as claimAndRelease for launches paired against an ERC20
    /// asset instead of ETH.
    function claimTokenAndRelease(address asset) external {
        if (escrow.balanceOfToken(address(this), asset) > 0) {
            uint256 amount = escrow.claimToken(asset);
            emit Claimed(asset, amount);
        }
        release(asset);
    }

    /// @notice Splits this contract's full balance of `asset` between the
    /// treasury and the payout wallet. Pass address(0) for native ETH.
    /// Permissionless and idempotent: a zero balance is a no-op.
    function release(address asset) public {
        uint256 balance =
            asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
        if (balance == 0) return;

        uint256 treasuryAmount = (balance * TREASURY_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 payoutAmount = balance - treasuryAmount;

        _send(asset, treasury, treasuryAmount);
        _send(asset, payout, payoutAmount);
        emit Released(asset, treasuryAmount, payoutAmount);
    }

    /// @notice The project's exit hatch. Once this splitter is the creator
    /// fee recipient on Pons, only the splitter itself can pass that role
    /// on; this lets the payout wallet do so at any time, moving future
    /// fees (and the buyback vest beneficiary) wherever the project wants.
    /// Fees already claimable by the splitter remain subject to the split.
    function transferFeeRecipient(address token, address newRecipient) external {
        if (msg.sender != payout) revert NotPayout();
        ponsFactory.transferCreatorFeeRecipient(token, newRecipient);
        emit FeeRecipientTransferred(token, newRecipient);
    }

    /// @notice Rotates the payout wallet. Only the current payout wallet
    /// may call this; the treasury share is untouchable.
    function setPayout(address newPayout) external {
        if (msg.sender != payout) revert NotPayout();
        if (newPayout == address(0)) revert ZeroAddress();
        emit PayoutUpdated(payout, newPayout);
        payout = newPayout;
    }

    function _send(address asset, address to, uint256 amount) private {
        if (amount == 0) return;
        if (asset == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert NativeTransferFailed();
        } else {
            (bool ok, bytes memory data) = asset.call(abi.encodeCall(IERC20.transfer, (to, amount)));
            if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert TokenTransferFailed();
            }
        }
    }
}
