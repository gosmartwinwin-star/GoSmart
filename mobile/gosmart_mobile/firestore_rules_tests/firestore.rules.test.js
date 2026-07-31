import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'gosmart-rules-test';
const here = dirname(fileURLToPath(import.meta.url));
const rulesPath = resolve(here, '..', 'firestore.rules');
let testEnv;

function emulatorAddress() {
  const address = process.env.FIRESTORE_EMULATOR_HOST;
  if (!address) {
    throw new Error('Tests must run inside firebase emulators:exec.');
  }
  const separator = address.lastIndexOf(':');
  return {
    host: address.slice(0, separator),
    port: Number(address.slice(separator + 1)),
  };
}

before(async () => {
  const { host, port } = emulatorAddress();
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host,
      port,
      rules: await readFile(rulesPath, 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    const createdAt = Timestamp.fromMillis(1_700_000_000_000);
    const approvedAt = Timestamp.fromMillis(1_700_086_400_000);
    const oldPurchase = Timestamp.fromMillis(1_700_100_000_000);
    const currentPurchase = Timestamp.fromMillis(1_700_200_000_000);
    const expiresAt = Timestamp.fromMillis(1_800_000_000_000);

    batch.set(doc(db, 'driverProfiles/driver-a'), {
      authUserId: 'user-a', status: 'approved', createdAt, approvedAt,
      suspendedAt: null,
    });
    batch.set(doc(db, 'driverProfiles/driver-b'), {
      authUserId: 'user-b', status: 'approved', createdAt, approvedAt,
      suspendedAt: null,
    });
    batch.set(doc(db, 'driverAccessPasses/pass-a-current'), {
      driverId: 'driver-a', plan: 'monthly', status: 'active',
      purchasedAt: currentPurchase, activatedAt: approvedAt, expiresAt,
    });
    batch.set(doc(db, 'driverAccessPasses/pass-a-old'), {
      driverId: 'driver-a', plan: 'weekly', status: 'expired',
      purchasedAt: oldPurchase, activatedAt: approvedAt, expiresAt: currentPurchase,
    });
    batch.set(doc(db, 'driverAccessPasses/pass-b-current'), {
      driverId: 'driver-b', plan: 'monthly', status: 'active',
      purchasedAt: currentPurchase, activatedAt: approvedAt, expiresAt,
    });
    batch.set(doc(db, 'driverAccessPasses/pass-missing-profile'), {
      driverId: 'driver-missing', plan: 'daily', status: 'active',
      purchasedAt: currentPurchase, activatedAt: approvedAt, expiresAt,
    });
    batch.set(doc(db, 'driverAccessPasses/pass-invalid-driver-type'), {
      driverId: 42, plan: 'daily', status: 'active',
      purchasedAt: currentPurchase, activatedAt: approvedAt, expiresAt,
    });
    batch.set(doc(db, 'driverProfiles/driver-auth-mismatch'), {
      authUserId: 'user-b', status: 'approved', createdAt, approvedAt,
      suspendedAt: null,
    });
    batch.set(doc(db, 'driverAccessPasses/pass-auth-mismatch'), {
      driverId: 'driver-auth-mismatch', plan: 'daily', status: 'active',
      purchasedAt: currentPurchase, activatedAt: approvedAt, expiresAt,
    });
    await batch.commit();
  });
});

const dbFor = (uid) => uid
  ? testEnv.authenticatedContext(uid).firestore()
  : testEnv.unauthenticatedContext().firestore();

test('1 unauthenticated user cannot get a driver profile', async () => {
  await assertFails(getDoc(doc(dbFor(), 'driverProfiles/driver-a')));
});
test('2 user-a can get own profile', async () => {
  await assertSucceeds(getDoc(doc(dbFor('user-a'), 'driverProfiles/driver-a')));
});
test('3 user-a cannot get user-b profile', async () => {
  await assertFails(getDoc(doc(dbFor('user-a'), 'driverProfiles/driver-b')));
});
test('4 user-b can get own profile', async () => {
  await assertSucceeds(getDoc(doc(dbFor('user-b'), 'driverProfiles/driver-b')));
});
test('5 user-b cannot get user-a profile', async () => {
  await assertFails(getDoc(doc(dbFor('user-b'), 'driverProfiles/driver-a')));
});
test('6 profile repository query succeeds and returns only driver-a', async () => {
  const db = dbFor('user-a');
  const snapshot = await assertSucceeds(getDocs(query(
    collection(db, 'driverProfiles'), where('authUserId', '==', 'user-a'), limit(2),
  )));
  assert.deepEqual(snapshot.docs.map((item) => item.id), ['driver-a']);
});
test('7 user-a cannot query user-b profiles', async () => {
  const db = dbFor('user-a');
  await assertFails(getDocs(query(collection(db, 'driverProfiles'), where('authUserId', '==', 'user-b'))));
});
test('8 unfiltered profile collection query fails', async () => {
  await assertFails(getDocs(collection(dbFor('user-a'), 'driverProfiles')));
});
test('9 insufficient profile status filter fails', async () => {
  const db = dbFor('user-a');
  await assertFails(getDocs(query(collection(db, 'driverProfiles'), where('status', '==', 'approved'))));
});

const ownProfileWrites = [
  ['10 create own profile', (db) => setDoc(doc(db, 'driverProfiles/driver-a-new'), { authUserId: 'user-a' })],
  ['11 update own status', (db) => updateDoc(doc(db, 'driverProfiles/driver-a'), { status: 'suspended' })],
  ['12 update own approvedAt', (db) => updateDoc(doc(db, 'driverProfiles/driver-a'), { approvedAt: Timestamp.now() })],
  ['13 update own authUserId', (db) => updateDoc(doc(db, 'driverProfiles/driver-a'), { authUserId: 'user-b' })],
  ['14 delete own profile', (db) => deleteDoc(doc(db, 'driverProfiles/driver-a'))],
  ['15 create another profile', (db) => setDoc(doc(db, 'driverProfiles/driver-b-new'), { authUserId: 'user-b' })],
  ['16 update another profile', (db) => updateDoc(doc(db, 'driverProfiles/driver-b'), { status: 'rejected' })],
  ['17 delete another profile', (db) => deleteDoc(doc(db, 'driverProfiles/driver-b'))],
];
for (const [name, operation] of ownProfileWrites) {
  test(`${name} is denied`, async () => assertFails(operation(dbFor('user-a'))));
}

test('18 unauthenticated user cannot get a pass', async () => {
  await assertFails(getDoc(doc(dbFor(), 'driverAccessPasses/pass-a-current')));
});
test('19 user-a can get current own pass', async () => {
  await assertSucceeds(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-a-current')));
});
test('20 user-a can get old own pass', async () => {
  await assertSucceeds(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-a-old')));
});
test('21 user-a cannot get user-b pass', async () => {
  await assertFails(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-b-current')));
});
test('22 user-b can get own pass', async () => {
  await assertSucceeds(getDoc(doc(dbFor('user-b'), 'driverAccessPasses/pass-b-current')));
});
test('23 user-b cannot get user-a pass', async () => {
  await assertFails(getDoc(doc(dbFor('user-b'), 'driverAccessPasses/pass-a-current')));
});

async function latestPass(uid, driverId) {
  const db = dbFor(uid);
  return getDocs(query(
    collection(db, 'driverAccessPasses'), where('driverId', '==', driverId),
    orderBy('purchasedAt', 'desc'), limit(1),
  ));
}
test('24 user-a repository query returns latest own pass', async () => {
  const snapshot = await assertSucceeds(latestPass('user-a', 'driver-a'));
  assert.equal(snapshot.docs[0].id, 'pass-a-current');
});
test('25 user-b repository query returns latest own pass', async () => {
  const snapshot = await assertSucceeds(latestPass('user-b', 'driver-b'));
  assert.equal(snapshot.docs[0].id, 'pass-b-current');
});
test('26 user-a cannot query driver-b passes', async () => {
  await assertFails(latestPass('user-a', 'driver-b'));
});
test('27 unfiltered pass collection query fails', async () => {
  await assertFails(getDocs(collection(dbFor('user-a'), 'driverAccessPasses')));
});
test('28 order and limit without driverId filter fail', async () => {
  const db = dbFor('user-a');
  await assertFails(getDocs(query(collection(db, 'driverAccessPasses'), orderBy('purchasedAt', 'desc'), limit(1))));
});
test('29 owned driverId query can return multiple own passes', async () => {
  const db = dbFor('user-a');
  const snapshot = await assertSucceeds(getDocs(query(
    collection(db, 'driverAccessPasses'), where('driverId', '==', 'driver-a'),
  )));
  assert.deepEqual(snapshot.docs.map((item) => item.id).sort(), ['pass-a-current', 'pass-a-old']);
});

const passWrites = [
  ['30 create own pass', (db) => setDoc(doc(db, 'driverAccessPasses/pass-a-new'), { driverId: 'driver-a' })],
  ['31 update own pass status', (db) => updateDoc(doc(db, 'driverAccessPasses/pass-a-current'), { status: 'expired' })],
  ['32 update own expiresAt', (db) => updateDoc(doc(db, 'driverAccessPasses/pass-a-current'), { expiresAt: Timestamp.now() })],
  ['33 update own activatedAt', (db) => updateDoc(doc(db, 'driverAccessPasses/pass-a-current'), { activatedAt: Timestamp.now() })],
  ['34 update own driverId', (db) => updateDoc(doc(db, 'driverAccessPasses/pass-a-current'), { driverId: 'driver-b' })],
  ['35 delete own pass', (db) => deleteDoc(doc(db, 'driverAccessPasses/pass-a-current'))],
  ['36 create another pass', (db) => setDoc(doc(db, 'driverAccessPasses/pass-b-new'), { driverId: 'driver-b' })],
  ['37 update another pass', (db) => updateDoc(doc(db, 'driverAccessPasses/pass-b-current'), { status: 'expired' })],
  ['38 delete another pass', (db) => deleteDoc(doc(db, 'driverAccessPasses/pass-b-current'))],
];
for (const [name, operation] of passWrites) {
  test(`${name} is denied`, async () => assertFails(operation(dbFor('user-a'))));
}

test('39 pass pointing to missing profile cannot be read', async () => {
  await assertFails(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-missing-profile')));
});
test('40 pass with non-string driverId cannot be read', async () => {
  await assertFails(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-invalid-driver-type')));
});
test('41 pass linked to profile owned by another user cannot be read', async () => {
  await assertFails(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-auth-mismatch')));
});
test('42 pass cannot be read after its profile is removed', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), 'driverProfiles/driver-a'));
  });
  await assertFails(getDoc(doc(dbFor('user-a'), 'driverAccessPasses/pass-a-current')));
});
