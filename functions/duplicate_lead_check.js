const { getFirestore } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const db = () => getFirestore();

// Only these fields ever leave the function, and only for a matched lead.
// Nothing else about another employee's lead is exposed to the caller.
const PROJECTION = [
  "name",
  "phone",
  "email",
  "company",
  "status",
  "assignedTo",
  "leadDate",
  "createdAt",
  "isTender",
];

// Scanning the leads collection on every keystroke would be wasteful, so a
// warm function instance reuses its last projection for this long. A lead
// created seconds ago may therefore be missed by the very next check — an
// acceptable trade for not re-reading the collection dozens of times a minute.
const CACHE_TTL_MS = 60 * 1000;
let cache = null;

/** Digits only, last 10 — so "+91 98765 43210" and "9876543210" match. */
function normalizePhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  if (digits.length < 7) return "";
  return digits.slice(-10);
}

function normalizeEmail(raw) {
  return String(raw || "").trim().toLowerCase();
}

/** Lowercase, drop punctuation and the usual company suffixes. */
function normalizeCompany(raw) {
  let value = String(raw || "").toLowerCase();
  value = value.replace(/[^a-z0-9 ]/g, " ");
  value = value.replace(
    /\b(pvt|private|ltd|limited|llp|inc|co|company|corp|corporation|enterprises|industries|technologies|technology|solutions|systems|india)\b/g,
    " ",
  );
  return value.replace(/\s+/g, " ").trim();
}

async function loadLeadIndex() {
  const now = Date.now();
  if (cache && now - cache.at < CACHE_TTL_MS) return cache.rows;

  const snap = await db().collection("leads").select(...PROJECTION).get();
  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      name: (d.name || "").trim(),
      company: (d.company || "").trim(),
      status: (d.status || "").trim(),
      assignedTo: (d.assignedTo || "").trim(),
      isTender: d.isTender === true,
      phoneKey: normalizePhone(d.phone),
      emailKey: normalizeEmail(d.email),
      companyKey: normalizeCompany(d.company),
    };
  });

  cache = { at: now, rows };
  return rows;
}

const userNameCache = new Map();
async function resolveUserName(uid) {
  if (!uid) return "Unassigned";
  if (userNameCache.has(uid)) return userNameCache.get(uid);
  let name = "Another employee";
  try {
    const doc = await db().collection("users").doc(uid).get();
    if (doc.exists) {
      const data = doc.data() || {};
      name = (data.name || data.displayName || data.email || name).toString();
    }
  } catch (error) {
    logger.warn("resolveUserName failed", { uid, error: error?.message });
  }
  userNameCache.set(uid, name);
  return name;
}

/**
 * Tells the caller whether a lead with this phone / email / company already
 * exists anywhere in the CRM — including under another employee, which the
 * caller's own Firestore rules would not let them see.
 *
 * Read-only: this function never writes. It is advisory only; the app still
 * lets the user save a lead after seeing the warning.
 */
exports.checkDuplicateLead = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    // Caller must be a known app user, same bar as the Firestore rules use.
    const callerDoc = await db().collection("users").doc(request.auth.uid).get();
    const role = callerDoc.exists ? (callerDoc.data() || {}).role : null;
    if (role !== "admin" && role !== "employee") {
      throw new HttpsError("permission-denied", "No app role assigned.");
    }

    const phoneKey = normalizePhone(request.data?.phone);
    const emailKey = normalizeEmail(request.data?.email);
    const companyKey = normalizeCompany(request.data?.company);
    const excludeId = String(request.data?.excludeLeadId || "").trim();

    if (!phoneKey && !emailKey && !companyKey) {
      return { matches: [] };
    }

    const rows = await loadLeadIndex();
    const matches = [];

    for (const row of rows) {
      if (row.id === excludeId) continue;

      let matchedOn = null;
      if (phoneKey && row.phoneKey && row.phoneKey === phoneKey) {
        matchedOn = "phone";
      } else if (emailKey && row.emailKey && row.emailKey === emailKey) {
        matchedOn = "email";
      } else if (companyKey && row.companyKey && row.companyKey === companyKey) {
        matchedOn = "company";
      }
      if (!matchedOn) continue;

      matches.push({ ...row, matchedOn });
      // A handful is enough to make the point; keeps the payload small.
      if (matches.length >= 8) break;
    }

    const result = [];
    for (const m of matches) {
      result.push({
        leadId: m.id,
        matchedOn: m.matchedOn,
        name: m.name,
        company: m.company,
        status: m.status,
        isTender: m.isTender,
        ownerName: await resolveUserName(m.assignedTo),
        isMine: m.assignedTo === request.auth.uid,
      });
    }

    return { matches: result };
  },
);
