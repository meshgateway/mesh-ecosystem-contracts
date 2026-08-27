// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPonsLaunchLocker} from "./interfaces/IPonsLaunchLocker.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title MeshSplitter
/// @notice Receives the creator fee share of a Pons v2 token and splits it
/// between the MeshGateway treasury and the project payout wallet at a
/// fixed, immutable ratio. One splitter is deployed per ecosystem project.
///
/// How it is wired up:
/// 1. MeshSplitterFactory deploys this contract with the project payout
///    wallet; the treasury address and share are fixed at deployment.
/// 2. The token deployer calls setFeeRedirect(token, splitter) on the Pons
///    locker, making this contract the creator fee recipient.
/// 3. Anyone may call claimAndRelease(token). The splitter collects the
///    accrued fees from the locker (it is authorized because it is the fee
///    recipient) and pays out both assets in the same transaction.
///
/// Trust properties:
/// - The treasury address and its share are immutable. Nobody, including
///   the treasury, can raise the cut after deployment.
/// - Releasing is permissionless. If MeshGateway disappears, the project
///   can always trigger its own 90 percent payout.
/// - The payout wallet can only be rotated by the current payout wallet.
/// - There is no owner, no upgrade path, and no pause switch.
contract MeshSplitter {
    /// @notice Treasury share in basis points (1000 = 10 percent).
    uint256 public constant TREASURY_SHARE_BPS = 1_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IPonsLaunchLocker public immutable locker;
    address public immutable treasury;

    /// @notice Wallet receiving the project share of every release.
    address public payout;

    event Claimed(address indexed token, uint256 amount0, uint256 amount1);
    event Released(address indexed asset, uint256 treasuryAmount, uint256 payoutAmount);
    event PayoutUpdated(address indexed previousPayout, address indexed newPayout);

    error ZeroAddress();
    error NotPayout();
    error NativeTransferFailed();
    error TokenTransferFailed();

    constructor(address locker_, address treasury_, address payout_) {
        if (locker_ == address(0) || treasury_ == address(0) || payout_ == address(0)) {
            revert ZeroAddress();
        }
        locker = IPonsLaunchLocker(locker_);
        treasury = treasury_;
        payout = payout_;
    }

    /// @notice Accept native ETH in case fees ever arrive unwrapped.
    receive() external payable {}

    /// @notice Collects accrued Pons creator fees for `token` and releases
    /// both sides of the pair. Permissionless: the locker authorizes this
    /// contract because it is the token's fee redirect target.
    function claimAndRelease(address token) external {
        (uint256 amount0, uint256 amount1) = locker.collectFees(token);
        emit Claimed(token, amount0, amount1);

        IPonsLaunchLocker.LaunchedToken memory launched = locker.getLaunchedToken(token);
        release(token);
        if (launched.pairedToken != token) {
            release(launched.pairedToken);
        }
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
            (bool ok, bytes memory data) =
                asset.call(abi.encodeCall(IERC20.transfer, (to, amount)));
            if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert TokenTransferFailed();
            }
        }
    }
}
