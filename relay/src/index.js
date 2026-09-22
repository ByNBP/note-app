/**
 * Ortak Notlar bildirim relay'i (Cloudflare Worker).
 *
 * Firebase Spark planinda Cloud Functions deploy edilemedigi icin, FCM'e
 * gonderimi yapan sunucu tarafi buraya tasindi. Akis:
 *
 *   istemci notu Firestore'a yazar
 *     -> POST /notify { sessionId, noteId } + Firebase ID token
 *       -> token dogrulanir, notun gercekten o kullanici tarafindan yazildigi
 *          Firestore'dan okunarak kanitlanir
 *         -> oturumun diger uyelerinin fcmTokens'lerine FCM HTTP v1 ile gonderilir
 *
 * Istemci "kime gonderilecegini" soylemez; yalnizca hangi notun yazildigini
 * soyler. Alicilari ve metni her zaman sunucu Firestore'dan okur -- boylece
 * ele gecirilmis bir istemci baskasinin oturumuna bildirim yagdiramaz.
 *
 * Servis hesabi anahtari yalnizca Worker secret'inda durur (FIREBASE_SERVICE_ACCOUNT).
 */

const GOOGLE_JWK_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPES = [
  'https://www.googleapis.com/auth/datastore',
  'https://www.googleapis.com/auth/firebase.messaging',
].join(' ');

/** Bu yastan eski notlar icin bildirim gonderilmez (tekrar oynatma korumasi). */
const MAX_NOTE_AGE_MS = 10 * 60 * 1000;

/** Ayni anda acilacak FCM istegi sayisi. */
const SEND_CONCURRENCY = 50;

/** Token'i kalici olarak olu sayacagimiz FCM hatalari. */
const DEAD_TOKEN_CODES = new Set([
  'UNREGISTERED',
  'INVALID_ARGUMENT',
  'SENDER_ID_MISMATCH',
]);

// Worker izolati yasadigi surece paylasilan onbellekler.
let jwkCache = null; // { keys: Map<kid, CryptoKey>, expiresAt }
let accessTokenCache = null; // { token, expiresAt }
let signingKeyCache = null; // CryptoKey

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== 'POST') {
      return json({ error: 'method_not_allowed' }, 405, cors);
    }
    if (new URL(request.url).pathname !== '/notify') {
      return json({ error: 'not_found' }, 404, cors);
    }

    try {
      const result = await handleNotify(request, env);
      return json(result, 200, cors);
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ error: error.code }, error.status, cors);
      }
      console.error('relay hatasi', error && error.stack ? error.stack : error);
      return json({ error: 'internal' }, 500, cors);
    }
  },
};

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

async function handleNotify(request, env) {
  const account = serviceAccount(env);
  const projectId = account.project_id;

  const idToken = bearerToken(request);
  const claims = await verifyIdToken(idToken, projectId);
  const uid = claims.sub;

  const body = await request.json().catch(() => null);
  const sessionId = idSegment(body && body.sessionId);
  const noteId = idSegment(body && body.noteId);

  const accessToken = await getAccessToken(account);
  const docs = docBase(projectId);

  const notePath = `${docs}/sessions/${sessionId}/notes/${noteId}`;
  const [note, session] = await Promise.all([
    getDocument(notePath, accessToken),
    getDocument(`${docs}/sessions/${sessionId}`, accessToken),
  ]);

  if (!note || !session) throw new HttpError(404, 'note_not_found');

  // Cagiran kisi gercekten bu notu yazmis ve oturumun uyesi olmali.
  const memberIds = session.memberIds || [];
  if (note.authorId !== uid) throw new HttpError(403, 'not_note_author');
  if (!memberIds.includes(uid)) throw new HttpError(403, 'not_a_member');

  // Ayni not icin ikinci kez gonderme.
  if (note.notifiedAt) return { status: 'already_sent' };

  const createdAt = note.createdAt ? Date.parse(note.createdAt) : Date.now();
  if (Number.isFinite(createdAt) && Date.now() - createdAt > MAX_NOTE_AGE_MS) {
    return { status: 'too_old' };
  }

  // Notu yazan kisiye kendi notunu bildirmiyoruz.
  const recipientIds = memberIds.filter((id) => id !== uid);
  if (recipientIds.length === 0) {
    await markNotified(docs, notePath, accessToken);
    return { status: 'no_recipients' };
  }

  const tokenOwner = await collectTokens(docs, recipientIds, accessToken);
  const tokens = [...tokenOwner.keys()];
  if (tokens.length === 0) {
    await markNotified(docs, notePath, accessToken);
    return { status: 'no_tokens' };
  }

  const title = session.title || 'Oturum';
  const author = note.authorName || 'Bir uye';
  const message = {
    title,
    body: `${author}: ${truncate(note.text || '', 120)}`,
    sessionId,
    noteId,
  };

  const { successCount, deadTokens } = await sendAll(
    tokens,
    message,
    projectId,
    accessToken,
  );

  await markNotified(docs, notePath, accessToken);
  await removeDeadTokens(docs, deadTokens, tokenOwner, accessToken);

  return {
    status: 'sent',
    successCount,
    tokenCount: tokens.length,
    deadTokens: deadTokens.length,
  };
}

// ---------------------------------------------------------------------------
// FCM
// ---------------------------------------------------------------------------

async function sendAll(tokens, message, projectId, accessToken) {
  const deadTokens = [];
  let successCount = 0;

  for (let i = 0; i < tokens.length; i += SEND_CONCURRENCY) {
    const chunk = tokens.slice(i, i + SEND_CONCURRENCY);
    const results = await Promise.all(
      chunk.map((token) => sendOne(token, message, projectId, accessToken)),
    );
    for (let j = 0; j < results.length; j++) {
      if (results[j].ok) successCount++;
      else if (results[j].dead) deadTokens.push(chunk[j]);
    }
  }

  return { successCount, deadTokens };
}

async function sendOne(token, message, projectId, accessToken) {
  const payload = {
    message: {
      token,
      notification: { title: message.title, body: message.body },
      data: {
        type: 'new_note',
        sessionId: message.sessionId,
        noteId: message.noteId,
        sessionTitle: message.title,
      },
      android: {
        priority: 'HIGH',
        notification: { channel_id: 'new_notes', tag: message.sessionId },
      },
      apns: {
        payload: { aps: { sound: 'default', 'thread-id': message.sessionId } },
      },
      webpush: {
        notification: {
          title: message.title,
          body: message.body,
          tag: message.sessionId,
        },
        fcm_options: { link: `/#/session/${message.sessionId}` },
      },
    },
  };

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${accessToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    },
  );

  if (response.ok) return { ok: true, dead: false };

  const detail = await response.json().catch(() => ({}));
  const code = fcmErrorCode(detail);
  console.warn(`FCM gonderilemedi (${response.status} ${code})`);
  return { ok: false, dead: DEAD_TOKEN_CODES.has(code) || response.status === 404 };
}

function fcmErrorCode(detail) {
  const error = detail && detail.error;
  if (!error) return 'UNKNOWN';
  for (const item of error.details || []) {
    if (item.errorCode) return item.errorCode;
  }
  return error.status || 'UNKNOWN';
}

// ---------------------------------------------------------------------------
// Firestore REST
// ---------------------------------------------------------------------------

function docBase(projectId) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

async function getDocument(path, accessToken) {
  const response = await fetch(path, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Firestore ${response.status}: ${await response.text()}`);
  }
  return decodeFields((await response.json()).fields);
}

/** Alicilarin fcmTokens'lerini toplar: token -> sahibi olan uid. */
async function collectTokens(docs, recipientIds, accessToken) {
  const response = await fetch(`${docs}:batchGet`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      documents: recipientIds.map((id) => `${docs}/users/${id}`),
    }),
  });
  if (!response.ok) {
    throw new Error(`Firestore batchGet ${response.status}: ${await response.text()}`);
  }

  const tokenOwner = new Map();
  for (const entry of await response.json()) {
    if (!entry.found) continue;
    const uid = entry.found.name.split('/').pop();
    const fields = decodeFields(entry.found.fields);
    for (const token of fields.fcmTokens || []) {
      // Ayni token birden fazla kullanicida gorunuyorsa (ayni cihazda hesap
      // degisimi) sonuncusu kazanir.
      tokenOwner.set(token, uid);
    }
  }
  return tokenOwner;
}

/** Notu "bildirildi" diye isaretler; ayni not icin ikinci cagri bos doner. */
async function markNotified(docs, notePath, accessToken) {
  await commit(docs, accessToken, [
    {
      update: {
        name: resourceName(notePath),
        fields: { notifiedAt: { timestampValue: new Date().toISOString() } },
      },
      updateMask: { fieldPaths: ['notifiedAt'] },
      currentDocument: { exists: true },
    },
  ]);
}

/** Gecersiz token'lari sahiplerinin dokumanindan siler. */
async function removeDeadTokens(docs, deadTokens, tokenOwner, accessToken) {
  if (deadTokens.length === 0) return;

  /** @type {Map<string, string[]>} uid -> silinecek token listesi */
  const byUser = new Map();
  for (const token of deadTokens) {
    const ownerId = tokenOwner.get(token);
    if (!ownerId) continue;
    if (!byUser.has(ownerId)) byUser.set(ownerId, []);
    byUser.get(ownerId).push(token);
  }

  const writes = [...byUser].map(([ownerId, stale]) => ({
    transform: {
      document: resourceName(`${docs}/users/${ownerId}`),
      fieldTransforms: [
        {
          fieldPath: 'fcmTokens',
          removeAllFromArray: { values: stale.map((t) => ({ stringValue: t })) },
        },
      ],
    },
  }));

  await commit(docs, accessToken, writes);
}

async function commit(docs, accessToken, writes) {
  const response = await fetch(`${docs}:commit`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ writes }),
  });
  if (!response.ok) {
    console.warn(`Firestore commit ${response.status}: ${await response.text()}`);
  }
}

/** Tam URL'i Firestore'un bekledigi kaynak adina cevirir. */
function resourceName(url) {
  return url.replace('https://firestore.googleapis.com/v1/', '');
}

/** Firestore'un tipli deger bicimini duz JS degerlerine cevirir. */
function decodeFields(fields) {
  const out = {};
  for (const [key, value] of Object.entries(fields || {})) {
    out[key] = decodeValue(value);
  }
  return out;
}

function decodeValue(value) {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in value) return decodeFields(value.mapValue.fields);
  return null;
}

// ---------------------------------------------------------------------------
// Firebase ID token dogrulama
// ---------------------------------------------------------------------------

async function verifyIdToken(token, projectId) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new HttpError(401, 'malformed_token');

  const header = JSON.parse(utf8(base64UrlDecode(parts[0])));
  const claims = JSON.parse(utf8(base64UrlDecode(parts[1])));

  if (header.alg !== 'RS256' || !header.kid) {
    throw new HttpError(401, 'bad_token_header');
  }

  const key = await googleKey(header.kid);
  if (!key) throw new HttpError(401, 'unknown_key');

  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlDecode(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) throw new HttpError(401, 'bad_signature');

  const now = Math.floor(Date.now() / 1000);
  if (claims.aud !== projectId) throw new HttpError(401, 'bad_audience');
  if (claims.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new HttpError(401, 'bad_issuer');
  }
  if (!claims.sub) throw new HttpError(401, 'bad_subject');
  if (typeof claims.exp !== 'number' || claims.exp <= now) {
    throw new HttpError(401, 'token_expired');
  }
  if (typeof claims.iat !== 'number' || claims.iat > now + 60) {
    throw new HttpError(401, 'token_from_future');
  }

  return claims;
}

async function googleKey(kid) {
  if (!jwkCache || jwkCache.expiresAt < Date.now()) {
    const response = await fetch(GOOGLE_JWK_URL);
    if (!response.ok) throw new Error(`JWK alinamadi: ${response.status}`);
    const body = await response.json();

    const keys = new Map();
    for (const jwk of body.keys || []) {
      keys.set(
        jwk.kid,
        await crypto.subtle.importKey(
          'jwk',
          jwk,
          { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
          false,
          ['verify'],
        ),
      );
    }
    jwkCache = { keys, expiresAt: Date.now() + maxAge(response) * 1000 };
  }
  return jwkCache.keys.get(kid);
}

function maxAge(response) {
  const header = response.headers.get('cache-control') || '';
  const match = header.match(/max-age=(\d+)/);
  return match ? Math.min(Number(match[1]), 86400) : 3600;
}

// ---------------------------------------------------------------------------
// Servis hesabi -> OAuth2 access token
// ---------------------------------------------------------------------------

function serviceAccount(env) {
  if (!env.FIREBASE_SERVICE_ACCOUNT) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT secret tanimli degil');
  }
  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  if (!account.project_id || !account.client_email || !account.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT eksik alan iceriyor');
  }
  return account;
}

async function getAccessToken(account) {
  if (accessTokenCache && accessTokenCache.expiresAt > Date.now() + 60_000) {
    return accessTokenCache.token;
  }

  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: account.client_email,
      scope: SCOPES,
      aud: TOKEN_URL,
      iat: now,
      exp: now + 3600,
    },
    account.private_key,
  );

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`Access token alinamadi: ${await response.text()}`);
  }

  const body = await response.json();
  accessTokenCache = {
    token: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return accessTokenCache.token;
}

async function signJwt(header, claims, privateKeyPem) {
  if (!signingKeyCache) {
    signingKeyCache = await crypto.subtle.importKey(
      'pkcs8',
      pemToBytes(privateKeyPem),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    );
  }

  const input = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(
    JSON.stringify(claims),
  )}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    signingKeyCache,
    new TextEncoder().encode(input),
  );
  return `${input}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function pemToBytes(pem) {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  return base64Decode(body);
}

// ---------------------------------------------------------------------------
// Kucuk yardimcilar
// ---------------------------------------------------------------------------

function bearerToken(request) {
  const header = request.headers.get('authorization') || '';
  if (!header.startsWith('Bearer ')) throw new HttpError(401, 'missing_token');
  return header.slice(7).trim();
}

/** Yol enjeksiyonunu engellemek icin id'leri dar bir alfabeye hapsediyoruz. */
function idSegment(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HttpError(400, 'bad_id');
  }
  return value;
}

function corsHeaders(request, env) {
  const allowed = (env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
  const origin = request.headers.get('origin');

  const headers = {
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
    vary: 'Origin',
  };
  // Android istemcisinde Origin yoktur; CORS yalnizca web'i ilgilendirir.
  if (origin && allowed.includes(origin)) {
    headers['access-control-allow-origin'] = origin;
  }
  return headers;
}

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'content-type': 'application/json' },
  });
}

function truncate(text, max) {
  const clean = text.replace(/\s+/g, ' ').trim();
  return clean.length <= max ? clean : `${clean.slice(0, max - 1)}…`;
}

function base64UrlEncode(input) {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(value) {
  return base64Decode(value.replace(/-/g, '+').replace(/_/g, '/'));
}

function base64Decode(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function utf8(bytes) {
  return new TextDecoder().decode(bytes);
}
