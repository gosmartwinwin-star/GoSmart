import assert from "node:assert/strict";
import test from "node:test";
import {
  PlacesHttpClient,
  resolvePlace,
  searchPlaces,
} from "./place-search-service.js";

const token = "123e4567-e89b-42d3-a456-426614174000";

test("autocomplete request maps place predictions", async () => {
  let capturedUrl = "";
  let capturedBody = "";
  let capturedHeaders: Record<string, string> = {};

  const http: PlacesHttpClient = async (url, options) => {
    capturedUrl = url;
    capturedBody = options.body ?? "";
    capturedHeaders = options.headers;

    return {
      ok: true,
      status: 200,
      json: async () => ({
        suggestions: [
          {
            placePrediction: {
              placeId: "place-1",
              structuredFormat: {
                mainText: {text: "Taksim Meydan\u0131"},
                secondaryText: {text: "Beyo\u011flu/\u0130stanbul"},
              },
            },
          },
          {
            queryPrediction: {
              text: {text: "ignored query"},
            },
          },
        ],
      }),
    };
  };

  const result = await searchPlaces(
    {input: "Taksim", sessionToken: token},
    "test-key",
    http,
  );

  assert.equal(
    capturedUrl,
    "https://places.googleapis.com/v1/places:autocomplete",
  );
  assert.equal(capturedHeaders["X-Goog-Api-Key"], "test-key");
  assert.match(
    capturedHeaders["X-Goog-FieldMask"],
    /placePrediction\.placeId/,
  );

  assert.deepEqual(JSON.parse(capturedBody), {
    input: "Taksim",
    languageCode: "tr",
    regionCode: "tr",
    sessionToken: token,
  });

  assert.deepEqual(result, {
    suggestions: [
      {
        placeId: "place-1",
        title: "Taksim Meydan\u0131",
        description: "Beyo\u011flu/\u0130stanbul",
      },
    ],
  });
});

test("autocomplete accepts empty suggestion response", async () => {
  const http: PlacesHttpClient = async () => ({
    ok: true,
    status: 200,
    json: async () => ({}),
  });

  assert.deepEqual(
    await searchPlaces(
      {input: "Taksim", sessionToken: token},
      "test-key",
      http,
    ),
    {suggestions: []},
  );
});

test("place details sends session token and maps coordinates", async () => {
  let capturedUrl = "";
  let capturedHeaders: Record<string, string> = {};

  const http: PlacesHttpClient = async (url, options) => {
    capturedUrl = url;
    capturedHeaders = options.headers;

    return {
      ok: true,
      status: 200,
      json: async () => ({
        id: "place/with space",
        displayName: {text: "Galata Kulesi"},
        formattedAddress: "Bereketzade, Beyo\u011flu/\u0130stanbul",
        location: {
          latitude: 41.0256,
          longitude: 28.9741,
        },
      }),
    };
  };

  const result = await resolvePlace(
    {
      placeId: "place/with space",
      sessionToken: token,
    },
    "test-key",
    http,
  );

  assert.match(
    capturedUrl,
    /^https:\/\/places\.googleapis\.com\/v1\/places\/place%2Fwith%20space\?/,
  );
  assert.match(capturedUrl, /languageCode=tr/);
  assert.match(capturedUrl, /regionCode=TR/);
  assert.match(
    capturedUrl,
    /sessionToken=123e4567-e89b-42d3-a456-426614174000/,
  );

  assert.equal(
    capturedHeaders["X-Goog-FieldMask"],
    "id,displayName.text,formattedAddress,location",
  );

  assert.deepEqual(result, {
    place: {
      id: "place/with space",
      title: "Galata Kulesi",
      description: "Bereketzade, Beyo\u011flu/\u0130stanbul",
      latitude: 41.0256,
      longitude: 28.9741,
    },
  });
});

test("upstream failure hides raw response body", async () => {
  const http: PlacesHttpClient = async () => ({
    ok: false,
    status: 403,
    json: async () => ({
      error: {
        message: "SECRET RAW GOOGLE ERROR",
      },
    }),
  });

  await assert.rejects(
    () => searchPlaces(
      {input: "Taksim", sessionToken: token},
      "test-key",
      http,
    ),
    (error: unknown) => {
      const value = error as {
        code?: string;
        message?: string;
        details?: {reason?: string};
      };

      assert.equal(value.code, "unavailable");
      assert.equal(
        value.details?.reason,
        "places_upstream_error",
      );
      assert.doesNotMatch(
        value.message ?? "",
        /SECRET RAW GOOGLE ERROR/,
      );
      return true;
    },
  );
});

test("missing api key fails before HTTP call", async () => {
  let called = false;

  const http: PlacesHttpClient = async () => {
    called = true;
    throw new Error("must not run");
  };

  await assert.rejects(
    () => searchPlaces(
      {input: "Taksim", sessionToken: token},
      "   ",
      http,
    ),
    (error: unknown) =>
      (error as {code?: string}).code === "internal",
  );

  assert.equal(called, false);
});

test("malformed successful response fails closed", async () => {
  const http: PlacesHttpClient = async () => ({
    ok: true,
    status: 200,
    json: async () => ({
      suggestions: [
        {
          placePrediction: {
            placeId: "place-1",
            structuredFormat: {},
          },
        },
      ],
    }),
  });

  await assert.rejects(
    () => searchPlaces(
      {input: "Taksim", sessionToken: token},
      "test-key",
      http,
    ),
    (error: unknown) =>
      (error as {
        details?: {reason?: string};
      }).details?.reason === "places_invalid_response",
  );
});

test("network rejection is sanitized for autocomplete", async () => {
  const http: PlacesHttpClient = async () => {
    throw new Error("SECRET NETWORK DETAIL");
  };

  await assert.rejects(
    () => searchPlaces(
      {input: "Taksim", sessionToken: token},
      "test-key",
      http,
    ),
    (error: unknown) => {
      const value = error as {
        code?: string;
        message?: string;
        details?: {reason?: string};
      };

      assert.equal(value.code, "unavailable");
      assert.equal(
        value.details?.reason,
        "places_upstream_error",
      );
      assert.doesNotMatch(
        value.message ?? "",
        /SECRET NETWORK DETAIL/,
      );
      return true;
    },
  );
});

test("invalid JSON is sanitized for autocomplete", async () => {
  const http: PlacesHttpClient = async () => ({
    ok: true,
    status: 200,
    json: async () => {
      throw new SyntaxError("SECRET JSON DETAIL");
    },
  });

  await assert.rejects(
    () => searchPlaces(
      {input: "Taksim", sessionToken: token},
      "test-key",
      http,
    ),
    (error: unknown) => {
      const value = error as {
        code?: string;
        message?: string;
        details?: {reason?: string};
      };

      assert.equal(value.code, "internal");
      assert.equal(
        value.details?.reason,
        "places_invalid_response",
      );
      assert.doesNotMatch(
        value.message ?? "",
        /SECRET JSON DETAIL/,
      );
      return true;
    },
  );
});

test("network rejection is sanitized for details", async () => {
  const http: PlacesHttpClient = async () => {
    throw new Error("SECRET DETAILS NETWORK");
  };

  await assert.rejects(
    () => resolvePlace(
      {
        placeId: "place-1",
        sessionToken: token,
      },
      "test-key",
      http,
    ),
    (error: unknown) => {
      const value = error as {
        code?: string;
        message?: string;
        details?: {reason?: string};
      };

      assert.equal(value.code, "unavailable");
      assert.equal(
        value.details?.reason,
        "places_upstream_error",
      );
      assert.doesNotMatch(
        value.message ?? "",
        /SECRET DETAILS NETWORK/,
      );
      return true;
    },
  );
});

test("invalid JSON is sanitized for details", async () => {
  const http: PlacesHttpClient = async () => ({
    ok: true,
    status: 200,
    json: async () => {
      throw new SyntaxError("SECRET DETAILS JSON");
    },
  });

  await assert.rejects(
    () => resolvePlace(
      {
        placeId: "place-1",
        sessionToken: token,
      },
      "test-key",
      http,
    ),
    (error: unknown) => {
      const value = error as {
        code?: string;
        message?: string;
        details?: {reason?: string};
      };

      assert.equal(value.code, "internal");
      assert.equal(
        value.details?.reason,
        "places_invalid_response",
      );
      assert.doesNotMatch(
        value.message ?? "",
        /SECRET DETAILS JSON/,
      );
      return true;
    },
  );
});
