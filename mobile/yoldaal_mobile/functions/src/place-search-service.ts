import {HttpsError} from "firebase-functions/v2/https";
import {
  PlaceAutocompleteInput,
  PlaceDetailsInput,
  validatePlaceAutocompleteInput,
  validatePlaceDetailsInput,
} from "./place-search-helpers.js";

export type PlaceSuggestion = {
  placeId: string;
  title: string;
  description: string;
};

export type ResolvedPlace = {
  id: string;
  title: string;
  description: string;
  latitude: number;
  longitude: number;
};

export type PlacesHttpResponse = {
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
};

export type PlacesHttpClient = (
  url: string,
  options: {
    method: "GET" | "POST";
    headers: Record<string, string>;
    body?: string;
  },
) => Promise<PlacesHttpResponse>;

const defaultHttpClient: PlacesHttpClient = async (url, options) =>
  fetch(url, options);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const readString = (value: unknown): string | null =>
  typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;

const requireApiKey = (apiKey: string): string => {
  const value = apiKey.trim();
  if (value.length === 0) {
    throw new HttpsError(
      "internal",
      "Adres arama servisi yap\u0131land\u0131r\u0131lamad\u0131.",
      {reason: "places_configuration_missing"},
    );
  }
  return value;
};

/**
 * Throws a sanitized upstream availability error.
 *
 */
function upstreamFailure(): never {
  throw new HttpsError(
    "unavailable",
    "Adres arama servisine ula\u015f\u0131lamad\u0131.",
    {reason: "places_upstream_error"},
  );
}

/**
 * Throws when a successful Places response is malformed.
 *
 */
function invalidResponse(): never {
  throw new HttpsError(
    "internal",
    "Adres arama sonucu i\u015flenemedi.",
    {reason: "places_invalid_response"},
  );
}

const requestPlaces = async (
  http: PlacesHttpClient,
  url: string,
  options: Parameters<PlacesHttpClient>[1],
): Promise<PlacesHttpResponse> => {
  try {
    return await http(url, options);
  } catch {
    upstreamFailure();
  }
};

const readPlacesJson = async (
  response: PlacesHttpResponse,
): Promise<unknown> => {
  try {
    return await response.json();
  } catch {
    invalidResponse();
  }
};

export const searchPlaces = async (
  rawInput: unknown,
  apiKey: string,
  http: PlacesHttpClient = defaultHttpClient,
): Promise<{suggestions: PlaceSuggestion[]}> => {
  const input: PlaceAutocompleteInput =
    validatePlaceAutocompleteInput(rawInput);

  const key = requireApiKey(apiKey);

  const response = await requestPlaces(
    http,
    "https://places.googleapis.com/v1/places:autocomplete",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        "X-Goog-FieldMask": [
          "suggestions.placePrediction.placeId",
          "suggestions.placePrediction.structuredFormat.mainText.text",
          "suggestions.placePrediction.structuredFormat.secondaryText.text",
        ].join(","),
      },
      body: JSON.stringify({
        input: input.input,
        languageCode: "tr",
        regionCode: "tr",
        sessionToken: input.sessionToken,
      }),
    },
  );

  if (!response.ok) upstreamFailure();

  const payload = await readPlacesJson(response);
  if (!isRecord(payload)) invalidResponse();

  const rawSuggestions = payload.suggestions;
  if (rawSuggestions === undefined) {
    return {suggestions: []};
  }
  if (!Array.isArray(rawSuggestions)) invalidResponse();

  const suggestions: PlaceSuggestion[] = [];

  for (const rawSuggestion of rawSuggestions) {
    if (!isRecord(rawSuggestion)) invalidResponse();

    const prediction = rawSuggestion.placePrediction;
    if (prediction === undefined) {
      continue;
    }
    if (!isRecord(prediction)) invalidResponse();

    const placeId = readString(prediction.placeId);
    const structured = prediction.structuredFormat;

    if (!placeId || !isRecord(structured)) invalidResponse();

    const mainText = structured.mainText;
    const secondaryText = structured.secondaryText;

    if (!isRecord(mainText)) invalidResponse();

    const title = readString(mainText.text);
    const description = isRecord(secondaryText) ?
      readString(secondaryText.text) ?? "" :
      "";

    if (!title) invalidResponse();

    suggestions.push({
      placeId,
      title,
      description,
    });
  }

  return {suggestions};
};

export const resolvePlace = async (
  rawInput: unknown,
  apiKey: string,
  http: PlacesHttpClient = defaultHttpClient,
): Promise<{place: ResolvedPlace}> => {
  const input: PlaceDetailsInput =
    validatePlaceDetailsInput(rawInput);

  const key = requireApiKey(apiKey);

  const query = new URLSearchParams({
    languageCode: "tr",
    regionCode: "TR",
    sessionToken: input.sessionToken,
  });

  const url =
    "https://places.googleapis.com/v1/places/" +
    encodeURIComponent(input.placeId) +
    "?" +
    query.toString();

  const response = await requestPlaces(http, url, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": key,
      "X-Goog-FieldMask":
        "id,displayName.text,formattedAddress,location",
    },
  });

  if (!response.ok) upstreamFailure();

  const payload = await readPlacesJson(response);
  if (!isRecord(payload)) invalidResponse();

  const id = readString(payload.id);
  const formattedAddress = readString(payload.formattedAddress);
  const displayName = payload.displayName;
  const location = payload.location;

  if (
    !id ||
    !formattedAddress ||
    !isRecord(displayName) ||
    !isRecord(location)
  ) {
    invalidResponse();
  }

  const title = readString(displayName.text);
  const latitude = location.latitude;
  const longitude = location.longitude;

  if (
    !title ||
    typeof latitude !== "number" ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== "number" ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    invalidResponse();
  }

  return {
    place: {
      id,
      title,
      description: formattedAddress,
      latitude,
      longitude,
    },
  };
};
