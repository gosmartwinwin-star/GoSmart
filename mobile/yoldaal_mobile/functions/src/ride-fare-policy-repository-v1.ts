import {Firestore} from "firebase-admin/firestore";
import {
  FarePolicyVersionV1,
  parseFarePolicyVersionV1,
  selectApprovedFarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {PRICING_FARE_V1} from "./ride-pricing-fare-v1.js";

export const FARE_POLICIES_COLLECTION = "farePolicies" as const;
export const MAX_FARE_POLICY_VERSIONS = 100;
const FARE_POLICY_QUERY_LIMIT = MAX_FARE_POLICY_VERSIONS + 1;

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const requireQuoteAtMillis = (
  value: number,
): number => {
  if (!Number.isSafeInteger(value) || value < 0) {
    return fail("fare_policy_quote_at_invalid");
  }
  return value;
};

export const loadApprovedFarePolicyVersionV1 = async (
  firestore: Firestore,
  quoteAtMillisRaw: number,
): Promise<FarePolicyVersionV1> => {
  const quoteAtMillis = requireQuoteAtMillis(
    quoteAtMillisRaw,
  );

  let snapshot;
  try {
    snapshot = await firestore
      .collection(FARE_POLICIES_COLLECTION)
      .where("pricingVersion", "==", PRICING_FARE_V1)
      .limit(FARE_POLICY_QUERY_LIMIT)
      .get();
  } catch (_error: unknown) {
    return fail("fare_policy_repository_unavailable");
  }

  if (snapshot.docs.length > MAX_FARE_POLICY_VERSIONS) {
    return fail("fare_policy_version_limit_exceeded");
  }

  const policies = snapshot.docs.map((document) => {
    const parsed = parseFarePolicyVersionV1(
      document.data(),
    );
    if (parsed.farePolicyVersionId !== document.id) {
      return fail("fare_policy_document_id_mismatch");
    }
    return parsed;
  });

  return selectApprovedFarePolicyVersionV1(
    policies,
    quoteAtMillis,
  );
};
