// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for the Pons v2 launch factory on Robinhood
/// Chain. Verified source: 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e
interface IPonsV2LaunchFactory {
    /// @notice Moves the creator fee recipiency of `token` to
    /// `newRecipient`. Only the current recipient may call. Also moves the
    /// buyback vest beneficiary, both on the curve and after graduation.
    function transferCreatorFeeRecipient(address token, address newRecipient) external;
}

/// @notice Minimal interface for the Pons v2 fee escrow on Robinhood
/// Chain. Creator fees accrue here as claimable balances in the launch's
/// pairing asset (native ETH for ETH paired launches). Verified source:
/// 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e
interface IPonsV2FeeEscrow {
    /// @notice Claims the caller's full native ETH balance.
    function claim() external returns (uint256 amount);

    /// @notice Claims the caller's full balance of an ERC20 pairing asset.
    function claimToken(address token) external returns (uint256 amount);

    function balanceOf(address recipient) external view returns (uint256);

    function balanceOfToken(address recipient, address token) external view returns (uint256);
}
