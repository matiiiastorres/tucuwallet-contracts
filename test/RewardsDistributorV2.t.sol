// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TucuToken} from "../src/TucuToken.sol";
import {TucuProxy} from "../src/TucuProxy.sol";
import {RewardsDistributorV2} from "../src/RewardsDistributorV2.sol";

contract RewardsDistributorV2Test is Test {
    TucuToken internal token;
    RewardsDistributorV2 internal distributor;
    uint256 internal signerKey = 0xA11CE;
    address internal signer;
    address internal admin = makeAddr("admin");
    address internal recipient = makeAddr("recipient");
    address internal outsider = makeAddr("outsider");
    bytes32 internal dailyMission = keccak256("web3_daily");
    uint256 internal constant ONE_TUCU = 1 ether;

    function setUp() public {
        signer = vm.addr(signerKey);
        TucuToken implementation = new TucuToken();
        TucuProxy proxy = new TucuProxy(address(implementation), admin);
        token = TucuToken(address(proxy));
        distributor = new RewardsDistributorV2(address(token), admin, signer);

        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), address(distributor));
        distributor.configureMission(dailyMission, ONE_TUCU, 1 days, 0, 30, true);
        vm.stopPrank();
    }

    function _signature(
        address wallet,
        bytes32 missionId,
        bytes32 claimId,
        uint256 amount,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("TucuRewardsDistributor"),
                keccak256("2"),
                block.chainid,
                address(distributor)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                distributor.CLAIM_TYPEHASH(),
                wallet,
                missionId,
                claimId,
                amount,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _claim(
        address wallet,
        bytes32 missionId,
        bytes32 claimId,
        uint256 amount,
        uint256 deadline
    ) internal {
        bytes memory sig = _signature(wallet, missionId, claimId, amount, deadline, signerKey);
        vm.prank(wallet);
        distributor.claim(missionId, claimId, wallet, amount, deadline, sig);
    }

    function _expectClaimRevert(
        bytes memory expected,
        address wallet,
        bytes32 missionId,
        bytes32 claimId,
        uint256 amount,
        uint256 deadline
    ) internal {
        bytes memory sig = _signature(wallet, missionId, claimId, amount, deadline, signerKey);
        if (expected.length == 0) vm.expectRevert();
        else vm.expectRevert(expected);
        vm.prank(wallet);
        distributor.claim(missionId, claimId, wallet, amount, deadline, sig);
    }

    function testValidSignedClaimMintsRewardAndRecordsState() public {
        bytes32 claimId = keccak256("claim-1");
        _claim(recipient, dailyMission, claimId, ONE_TUCU, block.timestamp + 1 hours);
        assertEq(token.balanceOf(recipient), ONE_TUCU);
        assertTrue(distributor.usedClaimIds(claimId));
        (uint64 lastClaimAt,, uint32 lifetimeClaims, uint32 windowClaims) =
            distributor.missionAccounts(recipient, dailyMission);
        assertEq(lastClaimAt, block.timestamp);
        assertEq(lifetimeClaims, 1);
        assertEq(windowClaims, 1);
    }

    function testClaimMustBeSentByRecipient() public {
        bytes32 claimId = keccak256("claim-sender");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signature(recipient, dailyMission, claimId, ONE_TUCU, deadline, signerKey);
        vm.expectRevert(RewardsDistributorV2.NotRecipient.selector);
        vm.prank(outsider);
        distributor.claim(dailyMission, claimId, recipient, ONE_TUCU, deadline, sig);
    }

    function testRejectsExpiredReusedMalformedAndUnauthorizedSignatures() public {
        bytes32 expiredId = keccak256("expired");
        bytes memory expiredSig = _signature(recipient, dailyMission, expiredId, ONE_TUCU, block.timestamp - 1, signerKey);
        vm.expectRevert();
        vm.prank(recipient);
        distributor.claim(dailyMission, expiredId, recipient, ONE_TUCU, block.timestamp - 1, expiredSig);

        bytes32 validId = keccak256("valid");
        uint256 deadline = block.timestamp + 1 hours;
        _claim(recipient, dailyMission, validId, ONE_TUCU, deadline);
        bytes memory reusedSig = _signature(recipient, dailyMission, validId, ONE_TUCU, deadline, signerKey);
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributorV2.ClaimAlreadyUsed.selector, validId));
        vm.prank(recipient);
        distributor.claim(dailyMission, validId, recipient, ONE_TUCU, deadline, reusedSig);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(RewardsDistributorV2.InvalidSignature.selector);
        vm.prank(recipient);
        distributor.claim(dailyMission, keccak256("short"), recipient, ONE_TUCU, block.timestamp + 1 hours, hex"1234");

        uint256 attackerKey = 0xB0B;
        bytes32 badId = keccak256("bad-signer");
        bytes memory badSig = _signature(outsider, dailyMission, badId, ONE_TUCU, block.timestamp + 1 hours, attackerKey);
        vm.expectRevert(RewardsDistributorV2.InvalidSignature.selector);
        vm.prank(outsider);
        distributor.claim(dailyMission, badId, outsider, ONE_TUCU, block.timestamp + 1 hours, badSig);
    }

    function testMissionConfigurationValidationAndAccess() public {
        vm.expectRevert();
        vm.prank(outsider);
        distributor.configureMission(keccak256("x"), 1, 0, 0, 0, true);
        vm.expectRevert(RewardsDistributorV2.InvalidMissionId.selector);
        vm.prank(admin);
        distributor.configureMission(bytes32(0), 1, 0, 0, 0, true);
        vm.expectRevert(RewardsDistributorV2.ZeroAmount.selector);
        vm.prank(admin);
        distributor.configureMission(keccak256("zero"), 0, 0, 0, 0, true);
        vm.expectRevert();
        vm.prank(admin);
        distributor.configureMission(keccak256("large"), 101 ether, 0, 0, 0, true);
    }

    function testDisabledMissionAndChangedAmountAreRejected() public {
        bytes32 disabled = keccak256("disabled");
        vm.prank(admin);
        distributor.configureMission(disabled, ONE_TUCU, 0, 0, 0, false);
        _expectClaimRevert(
            abi.encodeWithSelector(RewardsDistributorV2.MissionDisabled.selector, disabled),
            recipient, disabled, keccak256("disabled-claim"), ONE_TUCU, block.timestamp + 1 hours
        );

        bytes32 amountId = keccak256("amount");
        bytes memory sig = _signature(outsider, dailyMission, amountId, 2 ether, block.timestamp + 1 hours, signerKey);
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributorV2.RewardAmountChanged.selector, 2 ether, ONE_TUCU));
        vm.prank(outsider);
        distributor.claim(dailyMission, amountId, outsider, 2 ether, block.timestamp + 1 hours, sig);
    }

    function testCooldownLifetimeAndMissionWindowLimits() public {
        _claim(recipient, dailyMission, keccak256("daily-1"), ONE_TUCU, block.timestamp + 1 hours);
        _expectClaimRevert("", recipient, dailyMission, keccak256("daily-2"), ONE_TUCU, block.timestamp + 1 hours);

        bytes32 lifetime = keccak256("lifetime");
        vm.prank(admin);
        distributor.configureMission(lifetime, ONE_TUCU, 0, 1, 0, true);
        _claim(outsider, lifetime, keccak256("life-1"), ONE_TUCU, block.timestamp + 1 hours);
        _expectClaimRevert(abi.encodePacked(RewardsDistributorV2.LifetimeLimitReached.selector), outsider, lifetime, keccak256("life-2"), ONE_TUCU, block.timestamp + 1 hours);

        bytes32 windowMission = keccak256("window");
        vm.prank(admin);
        distributor.configureMission(windowMission, ONE_TUCU, 0, 0, 1, true);
        _claim(admin, windowMission, keccak256("window-1"), ONE_TUCU, block.timestamp + 1 hours);
        _expectClaimRevert(abi.encodePacked(RewardsDistributorV2.MissionWindowLimitReached.selector), admin, windowMission, keccak256("window-2"), ONE_TUCU, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 30 days);
        _claim(admin, windowMission, keccak256("window-3"), ONE_TUCU, block.timestamp + 1 hours);
    }

    function testMonthlyAggregateLimitAndReset() public {
        bytes32 sixty = keccak256("sixty");
        bytes32 fifty = keccak256("fifty");
        vm.startPrank(admin);
        distributor.configureMission(sixty, 60 ether, 0, 0, 0, true);
        distributor.configureMission(fifty, 50 ether, 0, 0, 0, true);
        vm.stopPrank();
        _claim(recipient, sixty, keccak256("sixty-1"), 60 ether, block.timestamp + 1 hours);
        _expectClaimRevert(abi.encodePacked(RewardsDistributorV2.MonthlyRewardLimitReached.selector), recipient, fifty, keccak256("fifty-1"), 50 ether, block.timestamp + 1 hours);
        vm.warp(block.timestamp + 30 days);
        _claim(recipient, fifty, keccak256("fifty-2"), 50 ether, block.timestamp + 1 hours);
        assertEq(token.balanceOf(recipient), 110 ether);
    }

    function testPauseAndRevokedSignerBlockClaims() public {
        vm.prank(admin);
        distributor.pause();
        _expectClaimRevert("", recipient, dailyMission, keccak256("paused"), ONE_TUCU, block.timestamp + 1 hours);
        vm.prank(admin);
        distributor.unpause();

        bytes32 rewardSignerRole = distributor.REWARD_SIGNER_ROLE();
        vm.prank(admin);
        distributor.revokeRole(rewardSignerRole, signer);
        _expectClaimRevert(abi.encodePacked(RewardsDistributorV2.InvalidSignature.selector), recipient, dailyMission, keccak256("revoked"), ONE_TUCU, block.timestamp + 1 hours);
    }

    function testConstructorRejectsZeroAddresses() public {
        vm.expectRevert(RewardsDistributorV2.ZeroAddress.selector);
        new RewardsDistributorV2(address(0), admin, signer);
        vm.expectRevert(RewardsDistributorV2.ZeroAddress.selector);
        new RewardsDistributorV2(address(token), address(0), signer);
        vm.expectRevert(RewardsDistributorV2.ZeroAddress.selector);
        new RewardsDistributorV2(address(token), admin, address(0));
    }
}
