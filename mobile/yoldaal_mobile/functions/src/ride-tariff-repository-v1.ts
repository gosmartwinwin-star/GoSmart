import {Firestore} from "firebase-admin/firestore";
import {
  parseTariffVersionV1,
  selectApprovedTariffVersionV1,
  TariffVersionV1,
} from "./ride-tariff-v1.js";

export const FARE_TARIFFS_COLLECTION = "fareTariffs" as const;
export const MAX_TARIFF_VERSIONS_PER_ZONE = 100;
const TARIFF_QUERY_LIMIT = MAX_TARIFF_VERSIONS_PER_ZONE + 1;

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const codeUnit = character.charCodeAt(0);
    return codeUnit <= 31 || codeUnit === 127;
  });

const requireTariffZoneId = (
  value: string,
): string => {
  if (typeof value !== "string") {
    return fail("tariff_zone_id_invalid");
  }
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > 120 ||
    hasAsciiControlCharacter(normalized)
  ) {
    return fail("tariff_zone_id_invalid");
  }
  return normalized;
};

const requireQuoteAtMillis = (
  value: number,
): number => {
  if (!Number.isSafeInteger(value) || value < 0) {
    return fail("tariff_quote_at_invalid");
  }
  return value;
};

export const loadApprovedTariffVersionV1 = async (
  firestore: Firestore,
  tariffZoneIdRaw: string,
  quoteAtMillisRaw: number,
): Promise<TariffVersionV1> => {
  const tariffZoneId = requireTariffZoneId(tariffZoneIdRaw);
  const quoteAtMillis = requireQuoteAtMillis(quoteAtMillisRaw);

  let snapshot;
  try {
    snapshot = await firestore
      .collection(FARE_TARIFFS_COLLECTION)
      .where("tariffZoneId", "==", tariffZoneId)
      .limit(TARIFF_QUERY_LIMIT)
      .get();
  } catch (_error: unknown) {
    return fail("tariff_repository_unavailable");
  }

  if (snapshot.docs.length > MAX_TARIFF_VERSIONS_PER_ZONE) {
    return fail("tariff_zone_version_limit_exceeded");
  }

  const versions = snapshot.docs.map((document) => {
    const parsed = parseTariffVersionV1(document.data());
    if (parsed.tariffVersionId !== document.id) {
      return fail("tariff_document_id_mismatch");
    }
    return parsed;
  });

  return selectApprovedTariffVersionV1(
    versions,
    tariffZoneId,
    quoteAtMillis,
  );
};
