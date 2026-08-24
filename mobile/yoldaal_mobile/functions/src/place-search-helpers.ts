import {HttpsError} from "firebase-functions/v2/https";

export const PLACE_SEARCH_MIN_INPUT_LENGTH = 3;
export const PLACE_SEARCH_MAX_INPUT_LENGTH = 120;
export const PLACE_SESSION_TOKEN_MAX_LENGTH = 36;
export const PLACE_ID_MAX_LENGTH = 256;

export type PlaceAutocompleteInput = {
  input: string;
  sessionToken: string;
};

export type PlaceDetailsInput = {
  placeId: string;
  sessionToken: string;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const hasExactKeys = (
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean => {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index]);
};

/**
 * Throws a sanitized invalid-argument error.
 *
 * @param {string} reason Stable machine-readable reason.
 */
function invalid(reason: string): never {
  throw new HttpsError(
    "invalid-argument",
    "Adres arama iste\u011fi ge\u00e7ersiz.",
    {reason},
  );
}

const readSessionToken = (
  value: unknown,
  reason: string,
): string => {
  if (typeof value !== "string") invalid(reason);

  const token = value.trim();
  if (
    token.length === 0 ||
    token.length > PLACE_SESSION_TOKEN_MAX_LENGTH ||
    !/^[A-Za-z0-9_-]+$/.test(token)
  ) {
    invalid(reason);
  }

  return token;
};

export const validatePlaceAutocompleteInput = (
  value: unknown,
): PlaceAutocompleteInput => {
  if (!isRecord(value) || !hasExactKeys(value, ["input", "sessionToken"])) {
    invalid("invalid_place_autocomplete_payload");
  }

  if (typeof value.input !== "string") {
    invalid("invalid_place_autocomplete_payload");
  }

  const input = value.input.trim();
  if (
    input.length < PLACE_SEARCH_MIN_INPUT_LENGTH ||
    input.length > PLACE_SEARCH_MAX_INPUT_LENGTH
  ) {
    invalid("invalid_place_autocomplete_payload");
  }

  return {
    input,
    sessionToken: readSessionToken(
      value.sessionToken,
      "invalid_place_autocomplete_payload",
    ),
  };
};

const containsControlCharacter = (value: string): boolean =>
  [...value].some((character) => {
    const code = character.charCodeAt(0);
    return code <= 0x1f || code === 0x7f;
  });
export const validatePlaceDetailsInput = (
  value: unknown,
): PlaceDetailsInput => {
  if (!isRecord(value) || !hasExactKeys(value, ["placeId", "sessionToken"])) {
    invalid("invalid_place_details_payload");
  }

  if (typeof value.placeId !== "string") {
    invalid("invalid_place_details_payload");
  }

  const placeId = value.placeId.trim();
  if (
    placeId.length === 0 ||
    placeId.length > PLACE_ID_MAX_LENGTH ||
    containsControlCharacter(placeId)
  ) {
    invalid("invalid_place_details_payload");
  }

  return {
    placeId,
    sessionToken: readSessionToken(
      value.sessionToken,
      "invalid_place_details_payload",
    ),
  };
};
