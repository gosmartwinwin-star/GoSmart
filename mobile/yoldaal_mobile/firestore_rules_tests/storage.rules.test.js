import {after, before, beforeEach, test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteObject, getBytes, listAll, ref, uploadBytes,
} from 'firebase/storage';

const projectId = 'gosmart-rules-test';
const bucket = 'gosmart-rules-test.appspot.com';
const here = dirname(fileURLToPath(import.meta.url));
let testEnv;

function emulatorAddress() {
  const address = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
  if (!address) throw new Error('Tests must run inside Storage emulator.');
  const separator = address.lastIndexOf(':');
  return {host: address.slice(0, separator), port: Number(address.slice(separator + 1))};
}

before(async () => {
  const {host, port} = emulatorAddress();
  testEnv = await initializeTestEnvironment({
    projectId,
    storage: {host, port, rules: await readFile(resolve(here, '..', 'storage.rules'), 'utf8')},
  });
});
after(async () => testEnv?.cleanup());
beforeEach(async () => testEnv.clearStorage());

const storageFor = (uid) => uid
  ? testEnv.authenticatedContext(uid).storage(bucket)
  : testEnv.unauthenticatedContext().storage(bucket);
const pathFor = (uid, type, name = 'current') =>
  `driverApplicationUploads/${uid}/${type}/${name}`;
const metadataFor = (uid, type, contentType) => ({
  contentType, customMetadata: {documentType: type, ownerUid: uid},
});
const upload = (uid, type, contentType, size = 1, path = pathFor(uid, type)) =>
  uploadBytes(ref(storageFor(uid), path), new Uint8Array(size),
    metadataFor(uid, type, contentType));
async function seed(path) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(bucket), path), new Uint8Array([1]),
      {contentType: 'image/jpeg'});
  });
}

test('1 unauthenticated cannot read staging', async () => {
  await seed(pathFor('user-a', 'driverLicenseFront'));
  await assertFails(getBytes(ref(storageFor(), pathFor('user-a', 'driverLicenseFront'))));
});
test('2 unauthenticated cannot upload staging', async () => assertFails(
  uploadBytes(ref(storageFor(), pathFor('user-a', 'driverLicenseFront')),
    new Uint8Array([1]), metadataFor('user-a', 'driverLicenseFront', 'image/jpeg'))));
test('3 owner can upload valid staging', async () => assertSucceeds(
  upload('user-a', 'driverLicenseFront', 'image/jpeg')));
test('4 owner can read staging', async () => {
  await assertSucceeds(upload('user-a', 'driverLicenseFront', 'image/jpeg'));
  await assertSucceeds(getBytes(ref(storageFor('user-a'), pathFor('user-a', 'driverLicenseFront'))));
});
test('5 cannot upload another owner staging', async () => assertFails(
  uploadBytes(ref(storageFor('user-a'), pathFor('user-b', 'driverLicenseFront')),
    new Uint8Array([1]), metadataFor('user-b', 'driverLicenseFront', 'image/jpeg'))));
test('6 cannot read another owner staging', async () => {
  await seed(pathFor('user-b', 'driverLicenseFront'));
  await assertFails(getBytes(ref(storageFor('user-a'), pathFor('user-b', 'driverLicenseFront'))));
});
test('7 arbitrary nested path denied', async () => assertFails(
  upload('user-a', 'driverLicenseFront', 'image/jpeg', 1,
    'driverApplicationUploads/user-a/driverLicenseFront/nested/current')));
test('8 unknown document type denied', async () => assertFails(
  upload('user-a', 'unknown', 'image/jpeg')));
test('9 non-current filename denied', async () => assertFails(
  upload('user-a', 'driverLicenseFront', 'image/jpeg', 1,
    pathFor('user-a', 'driverLicenseFront', 'other'))));

for (const [number, type, mime, succeeds] of [
  [10, 'driverLicenseFront', 'image/jpeg', true],
  [11, 'driverLicenseFront', 'image/png', true],
  [12, 'driverLicenseFront', 'application/pdf', false],
  [13, 'identityCardFront', 'application/pdf', false],
  [14, 'driverProfilePhoto', 'image/jpeg', true],
  [15, 'driverProfilePhoto', 'image/png', true],
  [16, 'driverProfilePhoto', 'application/pdf', false],
  [17, 'vehicleRegistration', 'application/pdf', true],
  [18, 'criminalRecord', 'application/pdf', true],
  [19, 'criminalRecord', 'application/octet-stream', false],
]) test(`${number} MIME policy`, async () => {
  const operation = upload('user-a', type, mime);
  await (succeeds ? assertSucceeds(operation) : assertFails(operation));
});
test('20 missing contentType denied', async () => assertFails(uploadBytes(
  ref(storageFor('user-a'), pathFor('user-a', 'driverLicenseFront')),
  new Uint8Array([1]), {customMetadata: {
    documentType: 'driverLicenseFront', ownerUid: 'user-a'}})));
test('21 empty file denied', async () => assertFails(
  upload('user-a', 'driverLicenseFront', 'image/jpeg', 0)));
for (const [number, type, size, succeeds] of [
  [22, 'driverProfilePhoto', 5 * 1024 * 1024, true],
  [23, 'driverProfilePhoto', 5 * 1024 * 1024 + 1, false],
  [24, 'driverLicenseFront', 10 * 1024 * 1024, true],
  [25, 'driverLicenseFront', 10 * 1024 * 1024 + 1, false],
]) test(`${number} size policy`, async () => {
  const operation = upload('user-a', type, 'image/jpeg', size);
  await (succeeds ? assertSucceeds(operation) : assertFails(operation));
});
test('26 matching documentType metadata accepted', async () => assertSucceeds(
  upload('user-a', 'identityCardBack', 'image/jpeg')));
test('27 mismatched documentType metadata denied', async () => assertFails(
  uploadBytes(ref(storageFor('user-a'), pathFor('user-a', 'identityCardBack')),
    new Uint8Array([1]), metadataFor('user-a', 'identityCardFront', 'image/jpeg'))));
test('28 matching owner metadata accepted', async () => assertSucceeds(
  upload('user-a', 'identityCardBack', 'image/jpeg')));
test('29 mismatched owner metadata denied', async () => assertFails(
  uploadBytes(ref(storageFor('user-a'), pathFor('user-a', 'identityCardBack')),
    new Uint8Array([1]), metadataFor('user-b', 'identityCardBack', 'image/jpeg'))));

const immutable = 'driverApplicationSubmissions/user-a/set-a/driverLicenseFront';
test('30 owner cannot read immutable', async () => {
  await seed(immutable);
  await assertFails(getBytes(ref(storageFor('user-a'), immutable)));
});
test('31 owner cannot write immutable', async () => assertFails(uploadBytes(
  ref(storageFor('user-a'), immutable), new Uint8Array([1]),
  {contentType: 'image/jpeg'})));
test('32 owner cannot delete immutable', async () => {
  await seed(immutable);
  await assertFails(deleteObject(ref(storageFor('user-a'), immutable)));
});
test('33 another user cannot read immutable', async () => {
  await seed(immutable);
  await assertFails(getBytes(ref(storageFor('user-b'), immutable)));
});
test('34 broad list denied', async () => assertFails(
  listAll(ref(storageFor('user-a'), 'driverApplicationUploads/user-a'))));
test('35 client cannot delete staging', async () => {
  await assertSucceeds(upload('user-a', 'driverLicenseFront', 'image/jpeg'));
  await assertFails(deleteObject(ref(storageFor('user-a'),
    pathFor('user-a', 'driverLicenseFront'))));
});
test('36 valid current object can be overwritten', async () => {
  await assertSucceeds(upload('user-a', 'driverLicenseFront', 'image/jpeg'));
  await assertSucceeds(upload('user-a', 'driverLicenseFront', 'image/png', 2));
});
test('37 custom-claim admin client cannot read immutable', async () => {
  await seed(immutable);
  const storage = testEnv.authenticatedContext('admin-a', {
    gosmartAdmin: true,
  }).storage(bucket);
  await assertFails(getBytes(ref(storage, immutable)));
});
