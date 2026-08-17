import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";
import {
  isRideMatchMeasurementEligible,
  RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
  RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
} from "./ride-match-offer-helpers.js";

type ParityCase = {
  name: string;
  pickupRouteIndex: number;
  dropoffRouteIndex: number;
  pickupDetourMeters: number;
  pickupDetourSeconds: number;
  dropoffDetourMeters: number;
  dropoffDetourSeconds: number;
  expectedEligible: boolean;
  expectedReason: string | null;
};

type ParityContract = {
  version: number;
  maximumDetourMeters: number;
  maximumDetourSeconds: number;
  subscriptionRequired: boolean;
  subscriptionRequiredReason: string;
  cases: ParityCase[];
};

const contractPath =
  resolve(
    __dirname,
    "../../test/fixtures/matching_policy_parity.json",
  );

const contract =
  JSON.parse(
    readFileSync(contractPath, "utf8"),
  ) as ParityContract;

test(
  "backend measurement policy matches shared Flutter parity contract",
  () => {
    assert.equal(contract.version, 1);

    assert.equal(
      RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
      contract.maximumDetourMeters,
    );

    assert.equal(
      RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
      contract.maximumDetourSeconds,
    );

    assert.equal(
      contract.subscriptionRequired,
      true,
    );

    assert.equal(
      contract.subscriptionRequiredReason,
      "subscription_required",
    );

    assert.ok(contract.cases.length > 0);

    const names = new Set(
      contract.cases.map((entry) => entry.name),
    );

    assert.equal(
      names.size,
      contract.cases.length,
    );

    for (const entry of contract.cases) {
      const eligible =
        isRideMatchMeasurementEligible({
          pickupRouteIndex:
            entry.pickupRouteIndex,
          dropoffRouteIndex:
            entry.dropoffRouteIndex,
          pickupDetourMeters:
            entry.pickupDetourMeters,
          pickupDetourSeconds:
            entry.pickupDetourSeconds,
          dropoffDetourMeters:
            entry.dropoffDetourMeters,
          dropoffDetourSeconds:
            entry.dropoffDetourSeconds,
        });

      assert.equal(
        eligible,
        entry.expectedEligible,
        entry.name,
      );
    }
  },
);

test(
  "backend discovery keeps shared subscription reason",
  () => {
    const discoverySource =
      readFileSync(
        resolve(
          __dirname,
          "../src/ride-match-offer-discovery.ts",
        ),
        "utf8",
      );

    assert.ok(
      discoverySource.includes(
        contract.subscriptionRequiredReason,
      ),
    );
  },
);
