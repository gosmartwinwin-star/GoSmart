import assert from "node:assert/strict";
import test from "node:test";
import {
  PICKUP_JURISDICTION_EVIDENCE_SOURCE_V1,
  parsePickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";

const component = (
  longText: string,
  shortText: string,
  types: string[],
) => ({
  longText,
  shortText,
  types,
  languageCode: "tr",
});

const canonical = () => [
  component(
    "Cankaya",
    "Cankaya",
    [
      "administrative_area_level_2",
      "political",
    ],
  ),
  component(
    "Ankara",
    "Ankara",
    [
      "administrative_area_level_1",
      "political",
    ],
  ),
  component(
    "Turkiye",
    "TR",
    [
      "country",
      "political",
    ],
  ),
  component(
    "Ankara",
    "Ankara",
    [
      "locality",
      "political",
    ],
  ),
  component(
    "Kizilay",
    "Kizilay",
    [
      "sublocality",
      "political",
    ],
  ),
];

test(
  "canonical Turkish components produce normalized evidence",
  () => {
    assert.deepEqual(
      parsePickupJurisdictionEvidenceV1(
        canonical(),
      ),
      {
        source:
          PICKUP_JURISDICTION_EVIDENCE_SOURCE_V1,
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
      },
    );
  },
);

test(
  "component order is not authority",
  () => {
    const reversed =
      [...canonical()].reverse();

    assert.deepEqual(
      parsePickupJurisdictionEvidenceV1(
        reversed,
      ),
      parsePickupJurisdictionEvidenceV1(
        canonical(),
      ),
    );
  },
);

test(
  "unrelated address components are ignored",
  () => {
    const result =
      parsePickupJurisdictionEvidenceV1(
        canonical(),
      );

    assert.equal(
      Object.keys(result).includes(
        "sublocality",
      ),
      false,
    );
  },
);

test(
  "country must be present and TR",
  () => {
    assert.throws(
      () =>
        parsePickupJurisdictionEvidenceV1(
          canonical().filter(
            (item) =>
              !item.types.includes(
                "country",
              ),
          ),
        ),
      /tariff_zone_jurisdiction_evidence_invalid/u,
    );

    const foreign = canonical().map(
      (item) =>
        item.types.includes("country") ?
          component(
            "Germany",
            "DE",
            ["country", "political"],
          ) :
          item,
    );

    assert.throws(
      () =>
        parsePickupJurisdictionEvidenceV1(
          foreign,
        ),
      /tariff_zone_jurisdiction_evidence_invalid/u,
    );
  },
);

test(
  "administrative area level one is mandatory",
  () => {
    assert.throws(
      () =>
        parsePickupJurisdictionEvidenceV1(
          canonical().filter(
            (item) =>
              !item.types.includes(
                "administrative_area_level_1",
              ),
          ),
        ),
      /tariff_zone_jurisdiction_evidence_invalid/u,
    );
  },
);

test(
  "optional level two and locality may be absent",
  () => {
    const minimal =
      canonical().filter(
        (item) =>
          !item.types.includes(
            "administrative_area_level_2",
          ) &&
          !item.types.includes("locality") &&
          !item.types.includes("sublocality"),
      );

    const result =
      parsePickupJurisdictionEvidenceV1(
        minimal,
      );

    assert.equal(
      result.administrativeAreaLevel2,
      null,
    );
    assert.equal(
      result.locality,
      null,
    );
  },
);

test(
  "duplicate authoritative component types fail closed",
  () => {
    for (const duplicateType of [
      "country",
      "administrative_area_level_1",
      "administrative_area_level_2",
      "locality",
    ]) {
      const base = canonical();
      const existing = base.find(
        (item) =>
          item.types.includes(
            duplicateType,
          ),
      );

      assert.ok(existing);

      assert.throws(
        () =>
          parsePickupJurisdictionEvidenceV1([
            ...base,
            {...existing},
          ]),
        /tariff_zone_jurisdiction_evidence_invalid/u,
      );
    }
  },
);

test(
  "malformed components fail closed",
  () => {
    const badInputs: unknown[] = [
      null,
      [],
      "components",
      [
        {
          longText: "Ankara",
          shortText: "Ankara",
          types:
            "administrative_area_level_1",
        },
      ],
      [
        {
          longText: "Ankara",
          shortText: "Ankara",
          types: [
            "administrative_area_level_1",
            "administrative_area_level_1",
          ],
        },
      ],
      [
        {
          longText: "Ankara",
          shortText: "Ankara",
          types: [
            "administrative_area_level_1",
          ],
          unexpected: true,
        },
      ],
    ];

    for (const input of badInputs) {
      assert.throws(
        () =>
          parsePickupJurisdictionEvidenceV1(
            input,
          ),
        /tariff_zone_jurisdiction_evidence_invalid/u,
      );
    }
  },
);

test(
  "control characters and empty texts fail closed",
  () => {
    for (const replacement of [
      component(
        "Ankara\nInjected",
        "Ankara",
        [
          "administrative_area_level_1",
        ],
      ),
      component(
        "Ankara",
        "   ",
        [
          "administrative_area_level_1",
        ],
      ),
    ]) {
      const input = canonical().map(
        (item) =>
          item.types.includes(
            "administrative_area_level_1",
          ) ?
            replacement :
            item,
      );

      assert.throws(
        () =>
          parsePickupJurisdictionEvidenceV1(
            input,
          ),
        /tariff_zone_jurisdiction_evidence_invalid/u,
      );
    }
  },
);

test(
  "evidence carries no tariff pricing identity or actor authority",
  () => {
    const result =
      parsePickupJurisdictionEvidenceV1(
        canonical(),
      );
    const keys =
      Object.keys(result);

    for (const forbidden of [
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "passengerId",
      "driverId",
      "addressLabel",
      "latitude",
      "longitude",
      "yoldaalFareMinor",
      "referenceEstimatedFareMinor",
    ]) {
      assert.equal(
        keys.includes(forbidden),
        false,
      );
    }
  },
);
