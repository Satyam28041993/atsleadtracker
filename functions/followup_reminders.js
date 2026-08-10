const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");

const db = () => getFirestore();

// Same channel/sound the Android app already creates locally in
// ReminderService.init() — reusing it means a push-triggered reminder looks and
// sounds identical to the old locally-scheduled one.
const FOLLOWUP_CHANNEL_ID = "followup_reminders_v5";
const FOLLOWUP_SOUND = "pick_up";

// Only alert on follow-ups that came due inside this trailing window, so a
// first deploy (or a temporarily-down scheduler) can't suddenly blast pushes
// for every already-overdue lead sitting in the pipeline.
const LOOKBACK_MINUTES = 15;
const RUN_EVERY_MINUTES = 2;
const LOOKAHEAD_MINUTES = 2;

// Statuses where a follow-up reminder is pointless — the deal is already closed.
const CLOSED_STATUSES = new Set([
  "Won",
  "Lost",
  "Loss",
  "Disqualified",
]);

function toMillis(value) {
  if (!value) return null;
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const parsed = new Date(value).getTime();
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

/** True when both timestamps point at the same instant (within a second). */
function isSameInstant(a, b) {
  const aMillis = toMillis(a);
  const bMillis = toMillis(b);
  if (aMillis === null || bMillis === null) return false;
  return Math.abs(aMillis - bMillis) < 1000;
}

function buildBody(lead) {
  const who = (lead.name || "").trim() || (lead.company || "").trim() || "this lead";
  const company = (lead.company || "").trim() && (lead.name || "").trim()
    ? ` (${lead.company.trim()})`
    : "";
  const requirement = (lead.requirement || "").trim();
  return requirement
    ? `Follow-up is due for ${who}${company}.\nRequirement: ${requirement}`
    : `Follow-up is due for ${who}${company}.`;
}

async function sendFollowUpPush({ token, lead, leadId }) {
  await getMessaging().send({
    token,
    notification: {
      title: "Follow-up Reminder",
      body: buildBody(lead),
    },
    android: {
      priority: "high",
      notification: {
        channelId: FOLLOWUP_CHANNEL_ID,
        sound: FOLLOWUP_SOUND,
        priority: "max",
        visibility: "public",
        // Collapses repeats for the same lead into one tray entry.
        tag: `followup_${leadId}`,
      },
    },
    data: {
      type: "followup",
      leadId,
    },
  });
}

/**
 * Runs every couple of minutes. For each lead whose `nextFollowUpDate` has just
 * come due, looks up the assigned employee's FCM token and pushes a reminder to
 * that device only.
 *
 * This is the server-side complement to the on-device AlarmManager scheduling
 * in ReminderService: it fires regardless of whether the employee's app is
 * open, backgrounded, or fully killed, because it does not depend on their
 * device having run any app code since the follow-up was set.
 *
 * Writes exactly one field (`followUpReminderSentForDate`) back onto the lead,
 * and only after a push actually succeeded. No other lead data is read-modified
 * or deleted by this function.
 */
exports.checkDueFollowUpReminders = onSchedule(
  {
    schedule: `*/${RUN_EVERY_MINUTES} * * * *`,
    timeZone: "Asia/Kolkata",
    retryCount: 1,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const now = new Date();
    const windowStart = new Date(now.getTime() - LOOKBACK_MINUTES * 60 * 1000);
    const windowEnd = new Date(now.getTime() + LOOKAHEAD_MINUTES * 60 * 1000);

    const snap = await db()
      .collection("leads")
      .where("nextFollowUpDate", ">=", Timestamp.fromDate(windowStart))
      .where("nextFollowUpDate", "<=", Timestamp.fromDate(windowEnd))
      .get();

    if (snap.empty) {
      logger.info("checkDueFollowUpReminders: nothing due in this window.");
      return;
    }

    const userCache = new Map();
    const getUser = async (uid) => {
      if (userCache.has(uid)) return userCache.get(uid);
      const doc = await db().collection("users").doc(uid).get();
      const data = doc.exists ? doc.data() : null;
      userCache.set(uid, data);
      return data;
    };

    let sent = 0;
    let skippedNoToken = 0;
    let skippedAlreadySent = 0;
    let skippedClosed = 0;
    let failed = 0;

    for (const doc of snap.docs) {
      const lead = doc.data();

      if (CLOSED_STATUSES.has((lead.status || "").trim())) {
        skippedClosed += 1;
        continue;
      }

      const assignedTo = (lead.assignedTo || "").trim();
      if (!assignedTo) continue;

      if (isSameInstant(lead.followUpReminderSentForDate, lead.nextFollowUpDate)) {
        skippedAlreadySent += 1;
        continue;
      }

      const user = await getUser(assignedTo);
      const token = (user?.fcmToken || "").trim();
      if (!token) {
        skippedNoToken += 1;
        continue;
      }

      try {
        await sendFollowUpPush({ token, lead, leadId: doc.id });
        // Only stamp after a confirmed send, so a transient failure retries
        // on the next run rather than silently swallowing the reminder.
        await doc.ref.update({
          followUpReminderSentForDate: lead.nextFollowUpDate,
        });
        sent += 1;
      } catch (error) {
        failed += 1;
        const code = error?.errorInfo?.code || error?.code || "";
        // A token goes stale when the app is reinstalled or data cleared.
        // Drop it so we stop retrying; the next sign-in writes a fresh one.
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          try {
            await db().collection("users").doc(assignedTo).update({
              fcmToken: "",
            });
            userCache.set(assignedTo, { ...(user || {}), fcmToken: "" });
          } catch (clearError) {
            logger.warn("Could not clear stale fcmToken", {
              uid: assignedTo,
              error: clearError?.message || String(clearError),
            });
          }
        }
        logger.error("Follow-up push failed", {
          leadId: doc.id,
          uid: assignedTo,
          code,
          error: error?.message || String(error),
        });
      }
    }

    logger.info("checkDueFollowUpReminders finished", {
      scanned: snap.size,
      sent,
      skippedNoToken,
      skippedAlreadySent,
      skippedClosed,
      failed,
    });
  },
);
