/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {
  HttpsError,
} from "firebase-functions/v2/https";

import {
  discoverNearbyPassengerDriversForPassenger,
  type NearbyPassengerDiscoveryDependencies,
} from "./nearby-passenger-discovery-authority.js";

type Data =
  Record<string, unknown>;

type OrderByTrace = {
  field: string;
  direction: "asc" | "desc";
};

type QueryTrace = {
  collectionName: string;
  orderBy: readonly OrderByTrace[];
  startValue: unknown;
  endValue: unknown;
};

class FakeDocumentSnapshot {
  constructor(
    readonly id: string,
    private readonly value: Data | undefined,
  ) {}

  get exists(): boolean {
    return this.value !== undefined;
  }

  data(): Data | undefined {
    return this.value;
  }

  get(field: string): unknown {
    return this.value?.[field];
  }
}

class FakeQuerySnapshot {
  constructor(
    readonly docs: readonly FakeDocumentSnapshot[],
  ) {}
}

class FakeDocumentReference {
  constructor(
    private readonly firestore: FakeFirestore,
    private readonly collectionName: string,
    private readonly id: string,
  ) {}

  async get(): Promise<FakeDocumentSnapshot> {
    const path =
      `${this.collectionName}/${this.id}`;

    this.firestore.documentReads.push(path);

    return this.firestore.snapshot(path);
  }
}

class FakeQuery {
  constructor(
    private readonly firestore: FakeFirestore,
    private readonly collectionName: string,
    private readonly orderBys:
      readonly OrderByTrace[] = [],
    private readonly startValue:
      unknown = undefined,
    private readonly endValue:
      unknown = undefined,
  ) {}

  orderBy(
    field: string,
    direction: "asc" | "desc" = "asc",
  ): FakeQuery {
    return new FakeQuery(
      this.firestore,
      this.collectionName,
      [
        ...this.orderBys,
        {
          field,
          direction,
        },
      ],
      this.startValue,
      this.endValue,
    );
  }

  startAt(
    value: unknown,
  ): FakeQuery {
    return new FakeQuery(
      this.firestore,
      this.collectionName,
      this.orderBys,
      value,
      this.endValue,
    );
  }

  endBefore(
    value: unknown,
  ): FakeQuery {
    return new FakeQuery(
      this.firestore,
      this.collectionName,
      this.orderBys,
      this.startValue,
      value,
    );
  }

  async get(): Promise<FakeQuerySnapshot> {
    this.firestore.queryReads.push({
      collectionName:
        this.collectionName,
      orderBy:
        [...this.orderBys],
      startValue:
        this.startValue,
      endValue:
        this.endValue,
    });

    if (
      this.collectionName ===
        "nearbyDriverGeoIndexes" &&
      this.firestore.failGeoQuery
    ) {
      throw new Error(
        "synthetic geo query failure",
      );
    }

    return new FakeQuerySnapshot([]);
  }
}

class FakeCollection {
  constructor(
    private readonly firestore: FakeFirestore,
    private readonly name: string,
  ) {}

  doc(
    id: string,
  ): FakeDocumentReference {
    return new FakeDocumentReference(
      this.firestore,
      this.name,
      id,
    );
  }

  orderBy(
    field: string,
    direction: "asc" | "desc" = "asc",
  ): FakeQuery {
    return new FakeQuery(
      this.firestore,
      this.name,
    ).orderBy(
      field,
      direction,
    );
  }
}

class FakeFirestore {
  readonly documentReads: string[] = [];
  readonly queryReads: QueryTrace[] = [];

  failGeoQuery = false;

  private readonly documents =
    new Map<string, Data>();

  collection(
    name: string,
  ): FakeCollection {
    return new FakeCollection(
      this,
      name,
    );
  }

  seed(
    path: string,
    data: Data,
  ): void {
    this.documents.set(
      path,
      {...data},
    );
  }

  snapshot(
    path: string,
  ): FakeDocumentSnapshot {
    const slash =
      path.lastIndexOf("/");

    const id =
      slash >= 0 ?
        path.substring(slash + 1) :
        path;

    return new FakeDocumentSnapshot(
      id,
      this.documents.get(path),
    );
  }
}

const now =
  Timestamp.fromMillis(1_000_000);

const passengerId =
  "passenger-1";

const rideId =
  "ride-1";

const pickup = {
  latitude: 41.0082,
  longitude: 28.9784,
};

const dropoff = {
  latitude: 41.0182,
  longitude: 28.9884,
};

const seedMatchingPassengerRide = (
  firestore: FakeFirestore,
): void => {
  firestore.seed(
    `passengerActiveRides/${passengerId}`,
    {
      rideId,
      status: "matching",
    },
  );

  firestore.seed(
    `rides/${rideId}`,
    {
      passengerId,
      status: "matching",
      driverId: null,
      pickup,
      dropoff,
    },
  );
};

const dependenciesFor = (
  firestore: FakeFirestore,
): {
  dependencies:
    NearbyPassengerDiscoveryDependencies;
  measurementCalls: () => number;
} => {
  let calls = 0;

  const dependencies:
    NearbyPassengerDiscoveryDependencies = {
      firestore:
        firestore as unknown as Firestore,
      now:
        () => now,
      measureCompatibility:
        async () => {
          calls++;
          return null;
        },
    };

  return {
    dependencies,
    measurementCalls:
      () => calls,
  };
};

const expectHttpsError = async (
  promise: Promise<unknown>,
  code: string,
  reason?: string,
): Promise<void> => {
  await assert.rejects(
    promise,
    (error: unknown) => {
      assert.ok(
        error instanceof HttpsError,
      );

      assert.equal(
        error.code,
        code,
      );

      if (reason !== undefined) {
        const details =
          error.details as Data;

        assert.equal(
          details.reason,
          reason,
        );
      }

      return true;
    },
  );
};

test(
  "unauthenticated passenger fails before any Firestore read",
  async () => {
    const firestore =
      new FakeFirestore();

    const {
      dependencies,
      measurementCalls,
    } = dependenciesFor(firestore);

    await expectHttpsError(
      discoverNearbyPassengerDriversForPassenger(
        dependencies,
        "",
        {},
      ),
      "unauthenticated",
    );

    assert.deepEqual(
      firestore.documentReads,
      [],
    );

    assert.deepEqual(
      firestore.queryReads,
      [],
    );

    assert.equal(
      measurementCalls(),
      0,
    );
  },
);

test(
  "non-empty request payload is rejected before any Firestore read",
  async () => {
    const firestore =
      new FakeFirestore();

    const {
      dependencies,
      measurementCalls,
    } = dependenciesFor(firestore);

    await expectHttpsError(
      discoverNearbyPassengerDriversForPassenger(
        dependencies,
        passengerId,
        {
          radiusMeters: 1,
        },
      ),
      "invalid-argument",
      "invalid_nearby_passenger_discovery_payload",
    );

    assert.deepEqual(
      firestore.documentReads,
      [],
    );

    assert.deepEqual(
      firestore.queryReads,
      [],
    );

    assert.equal(
      measurementCalls(),
      0,
    );
  },
);

test(
  "missing passenger active ride fails closed",
  async () => {
    const firestore =
      new FakeFirestore();

    const {
      dependencies,
      measurementCalls,
    } = dependenciesFor(firestore);

    await expectHttpsError(
      discoverNearbyPassengerDriversForPassenger(
        dependencies,
        passengerId,
        {},
      ),
      "failed-precondition",
      "passenger_active_ride_required",
    );

    assert.deepEqual(
      firestore.documentReads,
      [
        `passengerActiveRides/${passengerId}`,
      ],
    );

    assert.deepEqual(
      firestore.queryReads,
      [],
    );

    assert.equal(
      measurementCalls(),
      0,
    );
  },
);

test(
  "non-matching passenger ride fails before geo discovery",
  async () => {
    const firestore =
      new FakeFirestore();

    firestore.seed(
      `passengerActiveRides/${passengerId}`,
      {
        rideId,
        status: "inProgress",
      },
    );

    const {
      dependencies,
      measurementCalls,
    } = dependenciesFor(firestore);

    await expectHttpsError(
      discoverNearbyPassengerDriversForPassenger(
        dependencies,
        passengerId,
        {},
      ),
      "failed-precondition",
      "passenger_ride_not_matching",
    );

    assert.deepEqual(
      firestore.documentReads,
      [
        `passengerActiveRides/${passengerId}`,
      ],
    );

    assert.deepEqual(
      firestore.queryReads,
      [],
    );

    assert.equal(
      measurementCalls(),
      0,
    );
  },
);

test(
  "complete geo coverage with zero indexed drivers succeeds with exact empty result",
  async () => {
    const firestore =
      new FakeFirestore();

    seedMatchingPassengerRide(
      firestore,
    );

    const {
      dependencies,
      measurementCalls,
    } = dependenciesFor(firestore);

    const result =
      await discoverNearbyPassengerDriversForPassenger(
        dependencies,
        passengerId,
        {},
      );

    assert.deepEqual(
      result,
      [],
    );

    assert.deepEqual(
      firestore.documentReads,
      [
        `passengerActiveRides/${passengerId}`,
        `rides/${rideId}`,
      ],
    );

    assert.ok(
      firestore.queryReads.length > 0,
    );

    for (
      const trace of
      firestore.queryReads
    ) {
      assert.equal(
        trace.collectionName,
        "nearbyDriverGeoIndexes",
      );

      assert.deepEqual(
        trace.orderBy,
        [
          {
            field: "geohash",
            direction: "asc",
          },
          {
            field: "updatedAt",
            direction: "asc",
          },
        ],
      );

      assert.equal(
        typeof trace.startValue,
        "string",
      );

      assert.equal(
        typeof trace.endValue,
        "string",
      );

      assert.ok(
        (trace.startValue as string) <
          (trace.endValue as string),
      );
    }

    assert.equal(
      measurementCalls(),
      0,
    );
  },
);

test(
  "geo query failure is explicit unavailable and never success-empty",
  async () => {
    const firestore =
      new FakeFirestore();

    seedMatchingPassengerRide(
      firestore,
    );

    firestore.failGeoQuery =
      true;

    const {
      dependencies,
      measurementCalls,
    } = dependenciesFor(firestore);

    await expectHttpsError(
      discoverNearbyPassengerDriversForPassenger(
        dependencies,
        passengerId,
        {},
      ),
      "unavailable",
      "nearby_driver_geo_query_failed",
    );

    assert.equal(
      firestore.queryReads.length,
      1,
    );

    assert.equal(
      measurementCalls(),
      0,
    );
  },
);
