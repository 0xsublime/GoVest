// SPDX-License-Identifier: UNLICENSED

/// Run this test with RPC.

pragma solidity 0.8.13;

import "./Cheat.sol";
import "ds-test/test.sol";
import "../GoVest.sol";
import "solmate/tokens/ERC20.sol";

    contract RealisticTest is DSTest {

    // From GoVest contract
    event Claim(address indexed user, address claimer, uint256 amount);

    address public admin;
    address public fundAdmin;
    GoVest public vesting;

    Cheat cheat = (new Cheater()).getCheat();

    ERC20 fireToken = ERC20(0x2033e559cdDFF6DD36ec204e3014FAA75a01052E);
    uint256 totalTime = 10000;
    uint256 offset = 1000;
    uint256 startTime = block.timestamp + offset;

    event Amount(uint256 amount);
    function setUp() public {
        admin = address(0x1337);
        fundAdmin = 0x5Ccb403182598e2bc3767eBc3987E7f4c511a5a8;
        cheat.prank(admin);
        vesting = new GoVest(address(fireToken), startTime, totalTime, address(fundAdmin));

        cheat.label(address(fundAdmin), "fundAdmin");
        cheat.label(address(vesting), "vesting contract");
        cheat.label(address(fireToken), "FIRE token");
        cheat.label(address(cheat), "cheat");
    }

    address[] investors = [address(10), address(11), address(12), address(13), address(14)];
    uint256 investorTokens = 15_000_000e18;
    uint256[] investorAllocations = [5_000_000e18, 4_000_000e18, 3_000_000e18, 2_000_000e18, 1_000_000e18];

    address[] employees = [address(20), address(21), address(22), address(23)];
    uint256[] employeeAllocations = [900_000e18, 1_100_000e18, 1_500_000e18, 1_500_000e18];
    uint256 employeeTokens =  5_000_000e18;
    function testRealistic() public {
        cheat.startPrank(fundAdmin);
        fireToken.approve(address(vesting), investorTokens + employeeTokens);
        vesting.addTokens(investorTokens + employeeTokens);
        vesting.fund(investors, investorAllocations);
        vesting.fundCancellable(employees, employeeAllocations);
        cheat.stopPrank();

        require(vesting.vestedSupply() == 0);
        require(vesting.cancelledSupply() == 0);
        require(vesting.lockedSupply() == vesting.initialLockedSupply());
        require(vesting.initialLockedSupply() == investorTokens + employeeTokens);
        require(fireToken.balanceOf(address(vesting)) == investorTokens + employeeTokens);
        
        cheat.prank(admin);
        vesting.cancelStream(employees[0]);
        require(fireToken.balanceOf(admin) == employeeAllocations[0]);

        cheat.warp(startTime);
        require(vesting.vestedSupply() == 0);
        require(vesting.cancelledSupply() == employeeAllocations[0]);
        require(vesting.lockedSupply() == vesting.initialLockedSupply() - vesting.cancelledSupply());
        require(vesting.initialLockedSupply() == investorTokens + employeeTokens);
        require(fireToken.balanceOf(address(vesting)) == investorTokens + employeeTokens - employeeAllocations[0]);

        cheat.warp(startTime + totalTime / 5);

        cheat.prank(investors[0]);
        vesting.claim();
        require(fireToken.balanceOf(investors[0]) == investorAllocations[0] / 5);
        cheat.prank(employees[0]); // Cancelled.
        require(fireToken.balanceOf(employees[0]) == 0);

        cheat.prank(admin);
        vesting.cancelStream(employees[1]);
        require(fireToken.balanceOf(employees[1]) == employeeAllocations[1]/5);
        require(fireToken.balanceOf(admin) == employeeAllocations[0] + employeeAllocations[1] * 4 / 5);

        require(vesting.vestedSupply() == (investorTokens + employeeTokens  - vesting.cancelledSupply()) / 5);
        require(vesting.cancelledSupply() == employeeAllocations[0] + employeeAllocations[1] * 4 / 5);
        require(vesting.lockedSupply() == (vesting.initialLockedSupply() - vesting.cancelledSupply()) * 4 / 5);
        require(vesting.initialLockedSupply() == investorTokens + employeeTokens);
        require(fireToken.balanceOf(address(vesting)) ==
                      investorTokens
                    + employeeTokens
                    - employeeAllocations[0]
                    - employeeAllocations[1]
                    - investorAllocations[0] / 5); 

        cheat.startPrank(admin);
        for (uint256 i; i < investors.length; i++) {
            cheat.expectRevert("can't cancel this address");
            vesting.cancelStream(investors[i]);
        }
        cheat.stopPrank();
        
        cheat.warp(startTime + totalTime);
        cheat.prank(investors[0]);
        vesting.claim();
        require(fireToken.balanceOf(investors[0]) == investorAllocations[0]);

        cheat.startPrank(admin);
        for (uint256 i; i < investors.length; i++) {
            cheat.expectRevert("can't cancel this address");
            vesting.cancelStream(investors[i]);
        }
        cheat.stopPrank();

        for (uint256 i; i < investors.length; i++) {
            vesting.claim(investors[i]);
        }
        cheat.prank(admin);
        vesting.cancelStream(employees[2]);
        cheat.prank(employees[3]);
        vesting.claim();

        for (uint256 i; i < investors.length; i++) {
            vesting.claim(investors[i]);
        }
        for (uint256 i; i < employees.length; i++) {
            vesting.claim(employees[i]);
        }

        require(fireToken.balanceOf(admin) == employeeAllocations[0] + employeeAllocations[1] * 4 / 5);
        require(fireToken.balanceOf(address(vesting)) == 0);

        for (uint256 i; i < investors.length; i++) {
            require(fireToken.balanceOf(investors[i]) == investorAllocations[i]);
        }

        require(fireToken.balanceOf(employees[0]) == 0);
        require(fireToken.balanceOf(employees[1]) == employeeAllocations[1] / 5);
        require(fireToken.balanceOf(employees[2]) == employeeAllocations[2]);
        require(fireToken.balanceOf(employees[3]) == employeeAllocations[3]);
    }
}