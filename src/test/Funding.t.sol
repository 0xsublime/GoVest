// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./Cheat.sol";
import "ds-test/test.sol";
import "../GoVest.sol";
import "solmate/tokens/ERC20.sol";

contract FundingTest is DSTest {

    // From GoVest contract
    event Claim(address indexed user, address claimer, uint256 amount);

    address public admin;
    address public fundAdmin;
    GoVest public vesting;

    Cheat cheat = (new Cheater()).getCheat();

    address fireTokenWhale = 0x5Ccb403182598e2bc3767eBc3987E7f4c511a5a8;
    FireToken fireToken = new FireToken("Ceramic Token", "FIRE", 18);
    uint256 totalTime = 10000;
    uint256 offset = 1000;
    uint256 startTime = block.timestamp + offset;

    event Amount(uint256 amount);
    function setUp() public {
        admin = address(1337);
        fundAdmin = address(new FundAdmin());
        cheat.prank(admin);
        vesting = new GoVest(address(fireToken), startTime, totalTime, address(fundAdmin));

        cheat.label(address(fundAdmin), "fundAdmin");
        cheat.label(address(vesting), "vesting contract");
        cheat.label(address(fireToken), "FIRE token");
        cheat.label(address(fireTokenWhale), "FIRE Whale");
        cheat.label(address(cheat), "cheat");
    }

    function testAccessControl(address addr) public {
        cheat.assume(addr != admin && addr != fundAdmin);
        cheat.expectRevert("only admin or fund admin");
        vesting.fund(new address[](0),new uint256[](0));
        cheat.expectRevert("only admin or fund admin");
        vesting.fundCancellable(new address[](0),new uint256[](0));
        cheat.expectRevert("only admin or fund admin");
        vesting.setAdmin(addr);
        cheat.expectRevert("only admin or fund admin");
        vesting.setFundAdmin(addr);
        cheat.expectRevert("only admin or fund admin");
        vesting.setStartTime(type(uint256).max);
    }
    // Cancelling

    function testSetCancel(address[] memory recipients, uint256[] calldata _amounts) public {
        cheat.assume(_amounts.length > 0);
        uint256 len = recipients.length;
        uint256[] memory amounts = new uint256[](len);
        uint256 totalAmount;
        for (uint256 i; i < len; i++) {
            if (recipients[i] == address(0)) {
                recipients[i] = address(bytes20(keccak256(abi.encode(i, "salty"))));
            }
            // Treat amounts as a circular buffer.
            amounts[i] = _amounts[i % _amounts.length];
            cheat.assume(!overflow(totalAmount, amounts[i]));
            totalAmount += amounts[i];
        }
        cheat.assume(type(uint256).max / totalTime > totalAmount);

        for (uint256 i; i < recipients.length; i++) {
            require(!vesting.cancellable(recipients[i]));
        }
        fireToken.mint(fundAdmin, totalAmount);
        cheat.startPrank(fundAdmin);
        fireToken.approve(address(vesting), totalAmount);
        vesting.addTokens(totalAmount);
        vesting.fundCancellable(recipients, amounts);
        cheat.stopPrank();
        for (uint256 i; i < recipients.length; i++) {
            require(vesting.cancellable(recipients[i]));
        }
    }

    // NOTE: `claim` can fail if either the claimed amount or the current timestamp is huge

    function testCancelStream(address[] memory recipients, uint176[] calldata _amounts, uint80 warp) public {
        cheat.assume(_amounts.length > 0);
        uint256 len = recipients.length;
        uint256[] memory amounts = new uint256[](len);
        uint256 totalAmount;
        for (uint256 i; i < len; i++) {
            if (recipients[i] == address(0)) {
                recipients[i] = address(bytes20(keccak256(abi.encode(i, "salty"))));
            }
            // Treat amounts as a circular buffer.
            amounts[i] = _amounts[i % _amounts.length];
            cheat.assume(!overflow(totalAmount, amounts[i]));
            totalAmount += amounts[i];
        }
        cheat.assume(type(uint256).max / totalTime > totalAmount);

        fireToken.mint(fundAdmin, totalAmount);

        cheat.startPrank(fundAdmin);
        fireToken.approve(address(vesting), totalAmount);
        vesting.addTokens(totalAmount);
        vesting.fundCancellable(recipients, amounts);

        cheat.warp(warp);
        cheat.stopPrank();

        checkCancel(recipients);

        cheat.warp(type(uint80).max);
        for (uint256 i; i < len; i++) {
            uint256 initialBal = fireToken.balanceOf(recipients[i]);
            cheat.expectEmit(true, false, false, true);
            emit Claim(recipients[i], address(this), 0);
            vesting.claim(recipients[i]);
            cheat.prank(fundAdmin);
            vesting.cancelStream(recipients[i]);
            require(fireToken.balanceOf(recipients[i]) == initialBal);
        }
        require(fireToken.balanceOf(address(vesting)) == 0);
    }

    function checkCancel(address[] memory recipients) internal {
        for (uint256 i; i < recipients.length; i++) {
            uint256 initialBalAdmin = fireToken.balanceOf(admin);
            uint256 initialBalUser = fireToken.balanceOf(recipients[i]);
            uint256 claimable = vesting.balanceOf(recipients[i]);
            uint256 locked = vesting.lockedOf(recipients[i]);
            uint256 claimed = vesting.totalClaimed(recipients[i]);
            require(claimed + claimable + locked == vesting.initialLocked(recipients[i]));

            cheat.prank(fundAdmin);
            vesting.cancelStream(recipients[i]);

            require(fireToken.balanceOf(admin) == initialBalAdmin + locked);
            require(fireToken.balanceOf(recipients[i]) == initialBalUser + claimable);
        }
    }
    // Helpers

    function overflow(uint256 x, uint256 y) internal pure returns (bool) {
        unchecked {
            return x + y < x;
        }
    }

    function seed2Address(uint256 seed, uint256 salt) internal pure returns (address) {
        return address(bytes20(keccak256(abi.encode(seed, salt))));
    }

    function testFunding(uint256[] memory seeds, bool choice) public returns (bool) {
        address[] memory recipients = new address[](seeds.length);
        uint256[] memory amounts    = new uint256[](seeds.length);
        uint256 totalAmount = 0;
        for (uint256 i; i < seeds.length; i++) {
            uint256 seed = seeds[i];
            recipients[i] = seed2Address(seed, i);
            // Skip if the seed gives "bad" values, such as too big token amounts
            // or address collissions.
            amounts[i] = seed;
            if (overflow(totalAmount, amounts[i])) {
                return false;
            }
            totalAmount = totalAmount + amounts[i];
        }
        
        address funder;
        if (choice) {
            funder = admin;
        } else {
            funder = fundAdmin;
        }

        fireToken.mint(fireTokenWhale, totalAmount);

        cheat.prank(fireTokenWhale);
        fireToken.transfer(funder, totalAmount);

        emit Amount(fireToken.balanceOf(funder));

        cheat.startPrank(funder);
        fireToken.approve(address(vesting), totalAmount);

        bool failure = type(uint256).max / totalTime < totalAmount;
        if (failure) {
            cheat.expectRevert("overflow protection");
        }
        vesting.addTokens(totalAmount);

        if (failure) {
            cheat.expectRevert("not that many tokens available");
        }
        vesting.fund(recipients, amounts);
        cheat.stopPrank();

        if (failure) return false;

        require(vesting.initialLockedSupply() == totalAmount);
        for (uint i; i < seeds.length; i++) {
            uint256 stored = vesting.initialLocked(recipients[i]);

            emit Amount(stored);

            emit Amount(amounts[i]);

            require(stored == amounts[i]);
        }
        require(vesting.unallocatedSupply() == 0);
        return true;
    }

    function testClaim(uint256[] calldata seeds, address extraAddr, bool choice) public {
        bool res = testFunding(seeds, choice);
        if (!res) {
            return;
        }
        if (vesting.initialLocked(extraAddr) == 0) {
            uint256 initialBal = fireToken.balanceOf(extraAddr);
            cheat.expectEmit(true, false, false, true);
            emit Claim(extraAddr, address(this), 0);
            vesting.claim(extraAddr);
            require(fireToken.balanceOf(extraAddr) == initialBal);
        }
        for (uint256 i; i < seeds.length; i++) {
            address recipient = seed2Address(seeds[i], i);

            uint256 initialBal = fireToken.balanceOf(recipient);
            cheat.expectEmit(true, false, false, true);
            emit Claim(recipient, address(this), 0);
            vesting.claim(recipient);
            require(fireToken.balanceOf(recipient) == initialBal);
        }

        cheat.warp(startTime);
        if (vesting.initialLocked(extraAddr) == 0) {
            uint256 initialBal = fireToken.balanceOf(extraAddr);
            cheat.expectEmit(true, false, false, true);
            emit Claim(extraAddr, address(this), 0);
            vesting.claim(extraAddr);
            require(fireToken.balanceOf(extraAddr) == initialBal);
        }
        for (uint256 i; i < seeds.length; i++) {
            address recipient = seed2Address(seeds[i], i);

            uint256 initialBal = fireToken.balanceOf(recipient);
            cheat.expectEmit(true, false, false, true);
            emit Claim(recipient, address(this), 0);
            vesting.claim(recipient);
            require(fireToken.balanceOf(recipient) == initialBal);
        }

        cheat.warp(startTime + totalTime / 2);
        if (vesting.initialLocked(extraAddr) == 0) {
            uint256 initialBal = fireToken.balanceOf(extraAddr);
            cheat.expectEmit(true, false, false, true);
            emit Claim(extraAddr, address(this), 0);
            vesting.claim(extraAddr);
            require(fireToken.balanceOf(extraAddr) == initialBal);
        }
        for (uint256 i; i < seeds.length; i++) {
            address recipient = seed2Address(seeds[i], i);

            uint256 initialBal = fireToken.balanceOf(recipient);
            cheat.expectEmit(true, false, false, true);
            emit Claim(recipient, address(this), seeds[i] / 2);
            vesting.claim(recipient);
            require(fireToken.balanceOf(recipient) == initialBal + seeds[i] / 2);
        }

        cheat.warp(startTime + totalTime);
        if (vesting.initialLocked(extraAddr) == 0) {
            uint256 initialBal = fireToken.balanceOf(extraAddr);
            cheat.expectEmit(true, false, false, true);
            emit Claim(extraAddr, address(this), 0);
            vesting.claim(extraAddr);
            require(fireToken.balanceOf(extraAddr) == initialBal);
        }
        for (uint256 i; i < seeds.length; i++) {
            address recipient = seed2Address(seeds[i], i);

            uint256 initialBal = fireToken.balanceOf(recipient);
            cheat.expectEmit(true, false, false, true);
            emit Claim(recipient, address(this), seeds[i] / 2 + seeds[i] % 2);
            vesting.claim(recipient);
            require(fireToken.balanceOf(recipient) == initialBal + seeds[i] / 2 + seeds[i] % 2);
        }

        require(fireToken.balanceOf(address(vesting)) == 0);
    }

    function testExample() public {
        assertTrue(true);
    }
}

contract FireToken is ERC20 {

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address recipient, uint256 amount) public {
        _mint(recipient, amount);
    }
}

contract FundAdmin {
}