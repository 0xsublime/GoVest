// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../GoVest.sol";

contract FundingTest is DSTest {

    FundAdmin public fundAdmin;
    GoVest public vesting;

    address fireToken = 0x2033e559cdDFF6DD36ec204e3014FAA75a01052E;
    uint256 totalTime = 10000;
    uint256 offset = 1000;
    uint256 startTime = block.timestamp + offset;

    function setUp() public {
        fundAdmin = new FundAdmin();
        vesting = new GoVest(fireToken, startTime, totalTime, address(fundAdmin));
    }

    function testFunding(uint256[] calldata seeds) public {
    }

    function testExample() public {
        assertTrue(true);
    }
}

contract FundAdmin {

}