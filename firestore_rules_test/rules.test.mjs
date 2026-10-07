import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, addDoc, arrayUnion, arrayRemove, serverTimestamp } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-ats',
  firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8085 },
});
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const [uid, role] of [['admin','admin'],['owner','employee'],['mate','employee'],['other','employee'],['new','employee']]) {
    await setDoc(doc(db, 'users', uid), { role, name: uid });
  }
  await setDoc(doc(db, 'leads', 'L1'), { assignedTo: 'owner', teamMembers: ['mate'], status: 'New', name: 'A' });
  await setDoc(doc(db, 'leads', 'L2'), { assignedTo: 'owner', status: 'New', name: 'legacy, no team field' });
  await setDoc(doc(db, 'quotations', 'Q1'), { leadId: 'L1', employeeId: 'owner' });
  await setDoc(doc(db, 'quotations', 'Q2'), { leadId: 'L2', employeeId: 'owner' });
});
const as = (uid) => env.authenticatedContext(uid).firestore();
let pass = 0, fail = 0;
async function t(name, p) { try { await p; pass++; console.log('ok  ', name); } catch (e) { fail++; console.log('FAIL', name, e.message?.slice(0,120)); } }

const owner = as('owner'), mate = as('mate'), other = as('other'), admin = as('admin');
await t('owner reads L1', assertSucceeds(getDoc(doc(owner,'leads','L1'))));
await t('mate reads L1', assertSucceeds(getDoc(doc(mate,'leads','L1'))));
await t('other cannot read L1', assertFails(getDoc(doc(other,'leads','L1'))));
await t('other cannot read legacy L2', assertFails(getDoc(doc(other,'leads','L2'))));
await t('owner reads legacy L2', assertSucceeds(getDoc(doc(owner,'leads','L2'))));
await t('owner list by assignedTo', assertSucceeds(getDocs(query(collection(owner,'leads'), where('assignedTo','==','owner')))));
await t('mate list by teamMembers', assertSucceeds(getDocs(query(collection(mate,'leads'), where('teamMembers','array-contains','mate')))));
await t('other list by teamMembers (own uid) ok/empty', assertSucceeds(getDocs(query(collection(other,'leads'), where('teamMembers','array-contains','other')))));
await t('other cannot list someone else team', assertFails(getDocs(query(collection(other,'leads'), where('teamMembers','array-contains','mate')))));
await t('mate updates status', assertSucceeds(updateDoc(doc(mate,'leads','L1'), { status: 'Contacted', lastModified: serverTimestamp() })));
await t('mate full-doc save with same assignedTo', assertSucceeds(updateDoc(doc(mate,'leads','L1'), { assignedTo: 'owner', remark: 'x', status: 'Contacted' })));
await t('mate cannot reassign', assertFails(updateDoc(doc(mate,'leads','L1'), { assignedTo: 'mate' })));
await t('mate cannot add to team', assertFails(updateDoc(doc(mate,'leads','L1'), { teamMembers: arrayUnion('other') })));
await t('mate cannot delete', assertFails(deleteDoc(doc(mate,'leads','L1'))));
await t('mate writes event', assertSucceeds(addDoc(collection(mate,'leads','L1','events'), { action: 'Note' })));
await t('other cannot write event', assertFails(addDoc(collection(other,'leads','L1','events'), { action: 'Note' })));
await t('mate reads owner quotation Q1', assertSucceeds(getDoc(doc(mate,'quotations','Q1'))));
await t('mate queries quotations by leadId', assertSucceeds(getDocs(query(collection(mate,'quotations'), where('leadId','==','L1')))));
await t('other cannot read Q1', assertFails(getDoc(doc(other,'quotations','Q1'))));
await t('other cannot read legacy Q2', assertFails(getDoc(doc(other,'quotations','Q2'))));
await t('mate cannot read L2 quote', assertFails(getDoc(doc(mate,'quotations','Q2'))));
await t('owner adds other to team', assertSucceeds(updateDoc(doc(owner,'leads','L1'), { teamMembers: arrayUnion('other'), lastModified: serverTimestamp() })));
await t('mate cannot remove other', assertFails(updateDoc(doc(mate,'leads','L1'), { teamMembers: arrayRemove('other'), lastModified: serverTimestamp() })));
await t('mate leaves', assertSucceeds(updateDoc(doc(mate,'leads','L1'), { teamMembers: arrayRemove('mate'), lastModified: serverTimestamp() })));
await t('mate no longer reads L1', assertFails(getDoc(doc(mate,'leads','L1'))));
await t('owner adds team on legacy L2', assertSucceeds(updateDoc(doc(owner,'leads','L2'), { teamMembers: arrayUnion('mate') })));
await t('admin removes from team', assertSucceeds(updateDoc(doc(admin,'leads','L2'), { teamMembers: arrayRemove('mate') })));
await t('admin full collection read', assertSucceeds(getDocs(collection(admin,'leads'))));
await t('employee create own lead', assertSucceeds(setDoc(doc(as('new'),'leads','L9'), { assignedTo: 'new', status: 'New' })));
console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);
