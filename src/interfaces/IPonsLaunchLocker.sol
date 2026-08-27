// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for the Pons v2 launch locker on Robinhood Chain.
/// Verified source: 0x736D76699C26D0d966744cAe304C000d471f7F35
interface IPonsLaunchLocker {
    struct LaunchedToken {
        address token;
        address deployer;
        address pairedToken;
        address positionManager;
        uint256 positionId;
        uint256 dexId;
        uint256 launchConfigId;
        uint256 restrictionsEndBlock;
        uint256 supply;
        bool isToken0;
        uint24 poolFee;
        bool exists;
        uint256 initialBuyAmount;
    }

    /// @notice Collects accrued LP fees for a launched token. The creator
    /// share is sent to feeRedirects(token), or the deployer when no
    /// redirect is set. Callable by the locker owner, the token deployer,
    /// the current fee recipient, or an approved fee collector.
    function collectFees(address token) external returns (uint256 amount0, uint256 amount1);

    /// @notice Current fee redirect for a token; zero address means fees
    /// go to the original deployer.
    function feeRedirects(address token) external view returns (address);

    /// @notice Redirects the creator fee share to a new wallet. Only the
    /// token deployer (or the Pons factory) may call this.
    function setFeeRedirect(address token, address newFeeWallet) external;

    function getLaunchedToken(address token) external view returns (LaunchedToken memory);
}
