/**
 * Yeni bir not olusturuldugunda, o oturumun notu yazan disindaki tum
 * uyelerine FCM push bildirimi gonderir.
 *
 * Gecersiz hale gelmis token'lar kullanici dokumanindan temizlenir.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/** FCM'in tek istekte kabul ettigi maksimum token sayisi. */
const FCM_BATCH_SIZE = 500;

/** Bir token'i kalici olarak olu sayacagimiz hata kodlari. */
const DEAD_TOKEN_ERRORS = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

exports.onNoteCreated = onDocumentCreated(
  {
    document: "sessions/{sessionId}/notes/{noteId}",
    region: "europe-west1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const note = snapshot.data();
    const { sessionId, noteId } = event.params;

    const sessionSnap = await db.collection("sessions").doc(sessionId).get();
    if (!sessionSnap.exists) {
      logger.warn(`Oturum bulunamadi: ${sessionId}`);
      return;
    }
    const session = sessionSnap.data();

    // Notu yazan kisiye kendi notunu bildirmiyoruz.
    const recipientIds = (session.memberIds || []).filter(
      (id) => id !== note.authorId
    );
    if (recipientIds.length === 0) {
      logger.info(`Bildirilecek uye yok (session=${sessionId})`);
      return;
    }

    const userSnaps = await db.getAll(
      ...recipientIds.map((id) => db.collection("users").doc(id))
    );

    // token -> sahibi olan uid. Ayni token birden fazla kullanicida
    // gorunuyorsa (ayni cihazda hesap degisimi) sonuncusu kazanir.
    const tokenOwner = new Map();
    for (const userSnap of userSnaps) {
      if (!userSnap.exists) continue;
      for (const token of userSnap.get("fcmTokens") || []) {
        tokenOwner.set(token, userSnap.id);
      }
    }

    const tokens = [...tokenOwner.keys()];
    if (tokens.length === 0) {
      logger.info(`Kayitli FCM token yok (session=${sessionId})`);
      return;
    }

    const title = session.title || "Oturum";
    const author = note.authorName || "Bir uye";
    const body = `${author}: ${truncate(note.text || "", 120)}`;

    const deadTokens = [];
    let successCount = 0;

    for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
      const batch = tokens.slice(i, i + FCM_BATCH_SIZE);

      const response = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data: {
          type: "new_note",
          sessionId,
          noteId,
          sessionTitle: title,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "new_notes",
            tag: sessionId, // ayni oturumun bildirimleri ust uste yiginlanir
          },
        },
        apns: {
          payload: { aps: { sound: "default", threadId: sessionId } },
        },
        webpush: {
          notification: { title, body, tag: sessionId },
          fcmOptions: { link: `/#/session/${sessionId}` },
        },
      });

      successCount += response.successCount;

      response.responses.forEach((result, index) => {
        if (result.success) return;
        const code = result.error && result.error.code;
        logger.warn(`Gonderilemedi (${code})`, { token: batch[index] });
        if (DEAD_TOKEN_ERRORS.has(code)) {
          deadTokens.push(batch[index]);
        }
      });
    }

    logger.info(
      `Bildirim: ${successCount}/${tokens.length} basarili, ${deadTokens.length} olu token`
    );

    await removeDeadTokens(deadTokens, tokenOwner);
  }
);

/** Gecersiz token'lari sahiplerinin dokumanindan siler. */
async function removeDeadTokens(deadTokens, tokenOwner) {
  if (deadTokens.length === 0) return;

  /** @type {Map<string, string[]>} uid -> silinecek token listesi */
  const byUser = new Map();
  for (const token of deadTokens) {
    const ownerId = tokenOwner.get(token);
    if (!ownerId) continue;
    if (!byUser.has(ownerId)) byUser.set(ownerId, []);
    byUser.get(ownerId).push(token);
  }

  const batch = db.batch();
  for (const [ownerId, staleTokens] of byUser) {
    batch.update(db.collection("users").doc(ownerId), {
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
    });
  }
  await batch.commit();
}

function truncate(text, max) {
  const clean = text.replace(/\s+/g, " ").trim();
  return clean.length <= max ? clean : `${clean.slice(0, max - 1)}…`;
}
