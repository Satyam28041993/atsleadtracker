const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const { v1 } = require("@google-cloud/firestore");

initializeApp();

// Registered after initializeApp() so the module can use the default app.
const followUpReminders = require("./followup_reminders");
const duplicateLeadCheck = require("./duplicate_lead_check");

const BACKUP_BUCKET = "atsleadtracker-firestore-backups";
const STATUS_DOC_PATH = "settings/automatic_backup";

function formatStamp(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    "_",
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join("");
}

async function writeBackupStatus(patch) {
  const db = getFirestore();
  await db.doc(STATUS_DOC_PATH).set(
    {
      ...patch,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function runFirestoreExport() {
  const projectId = process.env.GCLOUD_PROJECT;
  if (!projectId) {
    throw new Error("GCLOUD_PROJECT is not set.");
  }

  const client = new v1.FirestoreAdminClient();
  const databaseName = client.databasePath(projectId, "(default)");
  const now = new Date();
  const outputUri = `gs://${BACKUP_BUCKET}/automatic/${formatStamp(now)}`;

  await writeBackupStatus({
    status: "running",
    outputUri,
    bucket: BACKUP_BUCKET,
    schedule: "every 3 days at 3:00 AM IST",
    lastStartedAt: Timestamp.fromDate(now),
    errorMessage: FieldValue.delete(),
  });

  const [operation] = await client.exportDocuments({
    name: databaseName,
    outputUriPrefix: outputUri,
  });

  logger.info("Firestore export started", {
    outputUri,
    operationName: operation.name,
  });

  await writeBackupStatus({
    status: "exporting",
    outputUri,
    operationName: operation.name || "",
  });

  const [response] = await operation.promise();

  await writeBackupStatus({
    status: "completed",
    outputUri,
    operationName: operation.name || "",
    lastCompletedAt: Timestamp.fromDate(new Date()),
    outputFiles: response?.outputUriPrefixCount || 0,
    errorMessage: FieldValue.delete(),
  });

  logger.info("Firestore export completed", { outputUri, response });
  return outputUri;
}

exports.scheduledFirestoreBackup = onSchedule(
  {
    schedule: "0 3 */3 * *",
    timeZone: "Asia/Kolkata",
    retryCount: 2,
    timeoutSeconds: 1800,
    memory: "512MiB",
  },
  async () => {
    try {
      await runFirestoreExport();
    } catch (error) {
      logger.error("Scheduled Firestore backup failed", error);
      await writeBackupStatus({
        status: "failed",
        lastFailedAt: Timestamp.fromDate(new Date()),
        errorMessage: error?.message || String(error),
      });
      throw error;
    }
  },
);

// Server-side follow-up reminders — fire even when the employee's app is
// backgrounded or killed. See functions/followup_reminders.js.
exports.checkDueFollowUpReminders = followUpReminders.checkDueFollowUpReminders;

// Advisory duplicate-lead lookup across all owners. Read-only; see
// functions/duplicate_lead_check.js.
exports.checkDuplicateLead = duplicateLeadCheck.checkDuplicateLead;
