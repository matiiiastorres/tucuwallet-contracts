// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TucuTransferRouter} from "../src/TucuTransferRouter.sol";

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public failTransfers;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function setFailTransfers(bool value) external { failTransfers = value; }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TucuTransferRouterTest is Test {
    TucuTransferRouter internal router;
    MockToken internal token;
    address internal admin = makeAddr("admin");
    address internal sender = makeAddr("sender");
    address internal recipient = makeAddr("recipient");
    address internal treasury = makeAddr("treasury");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        router = new TucuTransferRouter(admin, treasury, 50);
        token = new MockToken();
        vm.prank(admin);
        router.setTokenAllowed(address(token), true);
        token.mint(sender, 100 ether);
        vm.prank(sender);
        token.approve(address(router), type(uint256).max);
    }

    function testRoutesRecipientAndFeeWithoutCustody() public {
        vm.prank(sender);
        router.routeToken(address(token), recipient, 10 ether);
        assertEq(token.balanceOf(recipient), 9.95 ether);
        assertEq(token.balanceOf(treasury), 0.05 ether);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function testRoutesFullAmountWhenFeeIsZero() public {
        vm.prank(admin);
        router.setFeeBps(0);
        vm.prank(sender);
        router.routeToken(address(token), recipient, 10 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
        assertEq(token.balanceOf(treasury), 0);
    }

    function testRejectsInvalidRoutingInputs() public {
        vm.expectRevert(abi.encodeWithSelector(TucuTransferRouter.TokenNotAllowed.selector, outsider));
        vm.prank(sender);
        router.routeToken(outsider, recipient, 1 ether);
        vm.expectRevert(TucuTransferRouter.ZeroAddress.selector);
        vm.prank(sender);
        router.routeToken(address(token), address(0), 1 ether);
        vm.expectRevert(TucuTransferRouter.InvalidAmount.selector);
        vm.prank(sender);
        router.routeToken(address(token), recipient, 0);
    }

    function testRejectsFailedTokenTransfer() public {
        token.setFailTransfers(true);
        vm.expectRevert(abi.encodeWithSelector(TucuTransferRouter.TokenTransferFailed.selector, address(token)));
        vm.prank(sender);
        router.routeToken(address(token), recipient, 1 ether);
    }

    function testAdminConfigurationAndHardFeeCap() public {
        address nextTreasury = makeAddr("nextTreasury");
        vm.startPrank(admin);
        router.setFeeBps(100);
        router.setTreasury(nextTreasury);
        router.setTokenAllowed(address(token), false);
        vm.stopPrank();
        assertEq(router.feeBps(), 100);
        assertEq(router.treasury(), nextTreasury);
        assertFalse(router.allowedTokens(address(token)));

        vm.expectRevert(abi.encodeWithSelector(TucuTransferRouter.FeeTooHigh.selector, 101));
        vm.prank(admin);
        router.setFeeBps(101);
        vm.expectRevert(TucuTransferRouter.ZeroAddress.selector);
        vm.prank(admin);
        router.setTreasury(address(0));
        vm.expectRevert(TucuTransferRouter.ZeroAddress.selector);
        vm.prank(admin);
        router.setTokenAllowed(address(0), true);
    }

    function testPauseAndAccessControl() public {
        vm.expectRevert();
        vm.prank(outsider);
        router.setFeeBps(1);
        vm.prank(admin);
        router.pause();
        vm.expectRevert();
        vm.prank(sender);
        router.routeToken(address(token), recipient, 1 ether);
        vm.prank(admin);
        router.unpause();
        vm.prank(sender);
        router.routeToken(address(token), recipient, 1 ether);
    }

    function testConstructorValidation() public {
        vm.expectRevert(TucuTransferRouter.ZeroAddress.selector);
        new TucuTransferRouter(address(0), treasury, 0);
        vm.expectRevert(TucuTransferRouter.ZeroAddress.selector);
        new TucuTransferRouter(admin, address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(TucuTransferRouter.FeeTooHigh.selector, 101));
        new TucuTransferRouter(admin, treasury, 101);
    }
}
