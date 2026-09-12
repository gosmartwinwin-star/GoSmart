import assert from "node:assert/strict";
import test from "node:test";
import {
  classifyRideBackgroundOfferHint,
} from "./ride-background-offer-hint-helpers.js";

const matching = (
  round = 1,
) => ({
  passengerId:
    "passenger-1",
  driverId:
    null,
  status:
    "matching",
  matchRound:
    round,
});

test(
  "new matching ride emits generic hint",
  () => {
    assert.deepEqual(
      classifyRideBackgroundOfferHint(
        undefined,
        matching(),
      ),
      {
        type:
          "ride_offer_available",
      },
    );
  },
);

test(
  "ordinary matching update emits no duplicate",
  () => {
    assert.equal(
      classifyRideBackgroundOfferHint(
        matching(),
        {
          ...matching(),
          updatedAt:
            "changed",
        },
      ),
      null,
    );
  },
);

test(
  "driver cancellation rematch emits hint",
  () => {
    assert.deepEqual(
      classifyRideBackgroundOfferHint(
        {
          ...matching(),
          driverId:
            "driver-1",
          status:
            "driverEnRoute",
        },
        matching(2),
      ),
      {
        type:
          "ride_offer_available",
      },
    );
  },
);

test(
  "matching round increment emits hint",
  () => {
    assert.deepEqual(
      classifyRideBackgroundOfferHint(
        matching(1),
        matching(2),
      ),
      {
        type:
          "ride_offer_available",
      },
    );
  },
);

test(
  "assigned or malformed ride fails closed",
  () => {
    assert.equal(
      classifyRideBackgroundOfferHint(
        undefined,
        {
          ...matching(),
          driverId:
            "driver-1",
        },
      ),
      null,
    );

    assert.equal(
      classifyRideBackgroundOfferHint(
        undefined,
        {
          ...matching(),
          matchRound:
            0,
        },
      ),
      null,
    );
  },
);

test(
  "hint leaks no ride or passenger identifier",
  () => {
    const value =
      classifyRideBackgroundOfferHint(
        undefined,
        matching(),
      );

    assert.deepEqual(
      Object.keys(
        value ?? {},
      ),
      ["type"],
    );
  },
);
