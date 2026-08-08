// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @notice VERBATIM Solodit PoC (ZachObront / OlympusDAO H-03) with only the
///         SiloIncentivesController interface filled in so forge can compile.
/// @dev Source: https://github.com/solodit/solodit_content/blob/main/reports/ZachObront/2023-06-23-OlympusDAO.md
///      Finding: [H-03] Yield cannot be harvested because wrong token is passed to Incentives Controller
///      Severity: High Risk
///      Fork block: 17407114 (as published)
///      Policy: FORK_ONLY — no broadcast

interface SiloIncentivesController {
    function assets(address asset) external view returns (uint104 emissionPerSecond, uint104 index, uint104 lastUpdateTimestamp);
}

contract SiloRewardsTest is Test {
    address ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address collateralToken = 0x907136B74abA7D5978341eBA903544134A66B065;
    address collateralOnlyToken = 0xFDdfEd73b29B8859c6AE234aD64E2841614De559;
    address debtToken = 0x85A44Ff42F6B89125a541F64c77840977b0097E2;

    SiloIncentivesController incentives = SiloIncentivesController(0x6c1603aB6CecF89DD60C24530DdE23F97DA3C229);

    function testWhichTokensHaveIncentives() public {
        // published PoC used createSelectFork inside the test; Fork Lab also pins --fork-block-number
        uint104 emissionsPerSecond;

        (emissionsPerSecond,,) = incentives.assets(ohm);
        console.log("OHM: ", emissionsPerSecond);
        assertEq(emissionsPerSecond, 0, "Solodit: OHM must have 0 emissions");

        (emissionsPerSecond,,) = incentives.assets(collateralToken);
        console.log("Collateral: ", emissionsPerSecond);
        assertEq(emissionsPerSecond, 6430041152263380, "Solodit: collateral emissions mismatch");

        (emissionsPerSecond,,) = incentives.assets(collateralOnlyToken);
        console.log("Collateral Only: ", emissionsPerSecond);
        assertEq(emissionsPerSecond, 0, "Solodit: collateral-only must be 0");

        (emissionsPerSecond,,) = incentives.assets(debtToken);
        console.log("Debt: ", emissionsPerSecond);
        assertEq(emissionsPerSecond, 38580246913580, "Solodit: debt emissions mismatch");
    }
}
