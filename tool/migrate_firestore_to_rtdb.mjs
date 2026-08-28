/**
 * One-time Firestore → Realtime Database migration for GMSERP.
 *
 * Prerequisites:
 *   1. Enable Realtime Database in Firebase Console (gmserp-ffc76).
 *   2. Download a service account key JSON for the project.
 *   3. npm install firebase-admin (in this folder or globally).
 *
 * Usage:
 *   set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\serviceAccount.json
 *   node tool/migrate_firestore_to_rtdb.mjs
 *
 * Optional:
 *   set RTDB_URL=https://gmserp-ffc76-default-rtdb.asia-southeast1.firebasedatabase.app
 */

import admin from 'firebase-admin';

const projectId = process.env.FIREBASE_PROJECT_ID || 'gmserp-ffc76';
const databaseURL =
  process.env.RTDB_URL ||
  'https://gmserp-ffc76-default-rtdb.firebaseio.com';

if (!admin.apps.length) {
  admin.initializeApp({
    projectId,
    databaseURL,
  });
}

const firestore = admin.firestore();
const rtdb = admin.database();

function convertValue(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return { latitude: value.latitude, longitude: value.longitude };
  }
  if (Array.isArray(value)) {
    return value.map(convertValue);
  }
  if (typeof value === 'object') {
    const out = {};
    for (const [key, child] of Object.entries(value)) {
      out[key] = convertValue(child);
    }
    return out;
  }
  return value;
}

function convertDoc(data) {
  const out = convertValue(data);
  if (out && typeof out === 'object' && Array.isArray(out.recipientIds)) {
    out.recipientIds = Object.fromEntries(
      out.recipientIds.filter(Boolean).map((id) => [id, true]),
    );
  }
  return out;
}

async function copyCollection(collectionName) {
  const snapshot = await firestore.collection(collectionName).get();
  if (snapshot.empty) {
    console.log(`  (empty) ${collectionName}`);
    return 0;
  }
  const updates = {};
  for (const doc of snapshot.docs) {
    updates[doc.id] = convertDoc(doc.data());
  }
  await rtdb.ref(collectionName).set(updates);
  console.log(`  copied ${snapshot.size} docs → /${collectionName}`);
  return snapshot.size;
}

async function copyCompanies() {
  const snapshot = await firestore.collection('companies').get();
  if (snapshot.empty) {
    console.log('  (empty) companies');
    return 0;
  }

  let total = 0;
  for (const doc of snapshot.docs) {
    const companyData = convertDoc(doc.data());
    const companyRef = rtdb.ref(`companies/${doc.id}`);
    await companyRef.set(companyData);
    total += 1;

    const staffSnap = await doc.ref.collection('staff').get();
    if (!staffSnap.empty) {
      const staff = {};
      for (const staffDoc of staffSnap.docs) {
        staff[staffDoc.id] = convertDoc(staffDoc.data());
      }
      await companyRef.child('staff').set(staff);
      console.log(`    staff: ${staffSnap.size} under companies/${doc.id}`);
    }

    const tasksSnap = await doc.ref.collection('tasks').get();
    if (!tasksSnap.empty) {
      const tasks = {};
      for (const taskDoc of tasksSnap.docs) {
        tasks[taskDoc.id] = convertDoc(taskDoc.data());
      }
      await companyRef.child('tasks').set(tasks);
      console.log(`    tasks: ${tasksSnap.size} under companies/${doc.id}`);
    }
  }

  console.log(`  copied ${total} companies`);
  return total;
}

async function main() {
  console.log(`Migrating Firestore → RTDB (${databaseURL})`);

  const collections = [
    'users',
    'timeEntries',
    'timeCardSettings',
    'leaveRequests',
    'clockRequests',
    'timeCardChangeRequests',
    'appConfig',
    'salaryRateChanges',
    'announcements',
  ];

  let count = 0;
  count += await copyCompanies();
  for (const name of collections) {
    count += await copyCollection(name);
  }

  console.log(`Done. Migrated ${count} top-level records (plus nested staff/tasks).`);
  console.log('Publish database.rules.json: firebase deploy --only database');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
