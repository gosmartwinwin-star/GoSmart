import assert from "node:assert/strict";
import test from "node:test";
import {
  FareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  PickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";
import {
  createTariffZoneResolverV1,
} from "./ride-tariff-zone-resolver-v1.js";

const quoteAtMillis = 1757000000000;

const request = (
  addressLabel = "Client label",
): FareQuoteRequestV1 => ({
  requestId:
    "shared_quote_ride_request_1234",
  pickup: {
    latitude: 39.92077,
    longitude: 32.85411,
    addressLabel,
  },
  dropoff: {
    latitude: 39.95,
    longitude: 32.88,
    addressLabel: "Dropoff",
  },
});

const evidence =
  (): PickupJurisdictionEvidenceV1 => ({
    source:
      "google-address-components-v1",
    countryCode: "TR",
    administrativeAreaLevel1: {
      longText: "Ankara",
      shortText: "Ankara",
    },
    administrativeAreaLevel2: {
      longText: "Cankaya",
      shortText: "Cankaya",
    },
    locality: {
      longText: "Ankara",
      shortText: "Ankara",
    },
  });

test(
  "resolver returns backend policy zone id",
  async () => {
    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async () =>
            "TR-TEST-ZONE",
      });

    assert.equal(
      await resolver(
        request(),
        quoteAtMillis,
      ),
      "TR-TEST-ZONE",
    );
  },
);

test(
  "zone policy receives only normalized evidence and quote time",
  async () => {
    const calls: unknown[] = [];
    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async (jurisdiction, at) => {
            calls.push({
              jurisdiction,
              at,
            });
            return "TR-TEST-ZONE";
          },
      });

    await resolver(
      request(),
      quoteAtMillis,
    );

    assert.deepEqual(
      calls,
      [{
        jurisdiction: evidence(),
        at: quoteAtMillis,
      }],
    );
  },
);

test(
  "raw request fields are not passed to zone policy",
  async () => {
    let seen:
      Record<string, unknown> | null =
        null;

    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async (jurisdiction) => {
            seen =
              jurisdiction as unknown as
                Record<string, unknown>;
            return "TR-TEST-ZONE";
          },
      });

    await resolver(
      request("Injected label"),
      quoteAtMillis,
    );

    assert.ok(seen);
    for (const forbidden of [
      "requestId",
      "pickup",
      "dropoff",
      "addressLabel",
      "latitude",
      "longitude",
    ]) {
      assert.equal(
        forbidden in
          (seen as Record<string, unknown>),
        false,
      );
    }
  },
);

test(
  "policy zone id uses tariff repository technical shape",
  async () => {
    const accepted =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async () =>
            "  TR-TEST-ZONE  ",
      });

    assert.equal(
      await accepted(
        request(),
        quoteAtMillis,
      ),
      "TR-TEST-ZONE",
    );

    const exact120 = "z".repeat(120);
    const boundary =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async () => exact120,
      });

    assert.equal(
      await boundary(
        request(),
        quoteAtMillis,
      ),
      exact120,
    );
  },
);

test(
  "invalid policy zone id fails closed",
  async () => {
    for (const invalid of [
      null,
      "",
      "   ",
      "z".repeat(121),
      "zone\ninjected",
    ]) {
      const resolver =
        createTariffZoneResolverV1({
          getPickupJurisdictionEvidence:
            async () => evidence(),
          resolveZoneFromEvidence:
            async () => invalid,
        });

      await assert.rejects(
        () =>
          resolver(
            request(),
            quoteAtMillis,
          ),
        /tariff_zone_id_invalid/u,
      );
    }
  },
);

test(
  "invalid quote time fails before evidence or policy",
  async () => {
    let evidenceCalls = 0;
    let policyCalls = 0;

    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => {
            evidenceCalls += 1;
            return evidence();
          },
        resolveZoneFromEvidence:
          async () => {
            policyCalls += 1;
            return "TR-TEST-ZONE";
          },
      });

    await assert.rejects(
      () =>
        resolver(
          request(),
          -1,
        ),
      /tariff_quote_at_invalid/u,
    );

    assert.equal(
      evidenceCalls,
      0,
    );
    assert.equal(
      policyCalls,
      0,
    );
  },
);

test(
  "evidence failure is preserved and policy is not called",
  async () => {
    let policyCalls = 0;

    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => {
            throw new RangeError(
              "tariff_zone_jurisdiction_evidence_unavailable",
            );
          },
        resolveZoneFromEvidence:
          async () => {
            policyCalls += 1;
            return "TR-TEST-ZONE";
          },
      });

    await assert.rejects(
      () =>
        resolver(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_jurisdiction_evidence_unavailable/u,
    );

    assert.equal(
      policyCalls,
      0,
    );
  },
);

test(
  "policy failure is sanitized",
  async () => {
    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async () => {
            throw new Error(
              "private policy detail",
            );
          },
      });

    await assert.rejects(
      () =>
        resolver(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_policy_unavailable/u,
    );
  },
);

test(
  "changed client label cannot directly change policy input",
  async () => {
    const seen: unknown[] = [];
    const resolver =
      createTariffZoneResolverV1({
        getPickupJurisdictionEvidence:
          async () => evidence(),
        resolveZoneFromEvidence:
          async (jurisdiction, at) => {
            seen.push({
              jurisdiction,
              at,
            });
            return "TR-TEST-ZONE";
          },
      });

    const first =
      await resolver(
        request("One"),
        quoteAtMillis,
      );
    const second =
      await resolver(
        request("Two"),
        quoteAtMillis,
      );

    assert.equal(
      first,
      second,
    );
    assert.deepEqual(
      seen[0],
      seen[1],
    );
  },
);

test(
  "resolver defines no concrete jurisdiction mapping",
  () => {
    const source =
      createTariffZoneResolverV1
        .toString();

    for (const forbidden of [
      "Ankara",
      "Cankaya",
      "UKOME",
      "municipality",
      "administrativeAreaLevel1.shortText ===",
      "administrativeAreaLevel2.shortText ===",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);
