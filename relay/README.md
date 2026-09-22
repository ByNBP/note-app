# Bildirim relay'i (Cloudflare Worker)

Yeni not eklendiginde oturumun diger uyelerine FCM push bildirimi gonderir.
`functions/index.js` ile ayni isi yapar; farki, **Blaze planina gerek
duymamasi**: Firebase Spark planinda Cloud Functions deploy edilemedigi icin
gonderim burada, Cloudflare'in ucretsiz katmaninda calisiyor.

```
istemci notu Firestore'a yazar
  → POST /notify { sessionId, noteId } + Firebase ID token
     → token dogrulanir
     → notun gercekten o kullanici tarafindan yazildigi Firestore'dan okunur
     → oturumun diger uyelerinin fcmTokens'lerine FCM HTTP v1 ile gonderilir
```

Istemci **kime** gonderilecegini soylemez; yalnizca hangi notu yazdigini soyler.
Alicilari ve bildirim metnini her zaman Worker, Firestore'dan okuyarak belirler.
Ele gecirilmis bir istemci baskasinin oturumuna bildirim yagdiramaz.

Servis hesabi anahtari yalnizca Worker secret'inda durur, uygulama paketine
girmez.

---

## Kurulum

### 1. Servis hesabi anahtari

Firebase Console → Project settings → **Service accounts** → *Generate new
private key*. Inen JSON dosyasini gecici bir yere koy; repoya **koyma**.

### 2. Worker'i yayinla

```bash
export PATH="$HOME/.local/node20/bin:$PATH"   # wrangler Node 20+ ister
cd relay
npm install
npx wrangler login

# Anahtari secret olarak yukle (dosyayi boru ile ver, kopyalama hatasi olmasin)
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < /gecici/yol/service-account.json

npx wrangler deploy
```

Cikti bir adres verir:

```
https://ortak-notlar-relay.<hesabin>.workers.dev
```

### 3. Adresi uygulamaya yaz

`lib/services/notification_relay.dart` icindeki `relayEndpoint` sabitinin
`defaultValue` alanina yaz, ya da derlerken gec:

```bash
flutter build web --release --dart-define=NOTIFY_RELAY_URL=https://ortak-notlar-relay.<hesabin>.workers.dev
```

Adres ayarlanmazsa uygulama calisir ama bildirim gondermez (sessizce atlar).

### 4. Istemcileri yeniden yayinla

```bash
flutter build web --release
firebase deploy --only hosting
flutter build apk --release        # Android icin
```

---

## Ayarlar

| Yer | Ad | Ne ise yarar |
| --- | --- | --- |
| `wrangler.toml` → `[vars]` | `ALLOWED_ORIGINS` | Web'den fetch'e izin verilen kokenler (virgulle). Android'i ilgilendirmez. |
| Worker secret | `FIREBASE_SERVICE_ACCOUNT` | Servis hesabi JSON'u, tek parca metin olarak. |

Yeni bir hosting adresi eklersen `ALLOWED_ORIGINS`'e eklemeyi unutma, yoksa
tarayici istegi CORS'ta takilir.

---

## Ucu

`POST /notify`

```
Authorization: Bearer <Firebase ID token>
Content-Type: application/json

{ "sessionId": "...", "noteId": "..." }
```

Yanit `200` ve bir durum dondurur:

| `status` | Anlami |
| --- | --- |
| `sent` | Gonderildi (`successCount` / `tokenCount` alanlari da doner) |
| `already_sent` | Bu not icin daha once gonderilmis |
| `no_recipients` | Oturumda yazan disinda uye yok |
| `no_tokens` | Alicilarda kayitli FCM token yok |
| `too_old` | Not 10 dakikadan eski, tekrar gonderilmiyor |

Hatalar `{ "error": "<kod>" }` ile doner: `missing_token`, `token_expired`,
`bad_audience`, `not_note_author`, `not_a_member`, `note_not_found`, `bad_id`.

Ayni not icin ikinci cagri bos doner: Worker gonderdikten sonra nota
`notifiedAt` damgasi yazar.

---

## Gunluk ve sorun giderme

```bash
npx wrangler tail          # canli log
```

- **Bildirim gelmiyor, log'da `no_tokens`** → alicinin cihazi FCM token
  kaydetmemis. Uygulamada bildirim izni verildi mi, web'de VAPID anahtari
  dolu mu (`firebase_options.dart` → `webPushVapidKey`) bak.
- **`not_note_author`** → istemci baskasinin notunu bildirmeye calisiyor;
  normal kullanimda gorulmez.
- **Kendine bildirim gelmiyor** → dogru davranis: notu yazan kisiye kendi notu
  gonderilmez. Test ederken web ve telefonda **farkli hesap** kullan.
- **Web'de CORS hatasi** → `ALLOWED_ORIGINS` icinde o koken yok.

---

## Blaze'e gecersen

`functions/index.js` ayni isi Firestore trigger'i ile yapar ve duruyor. Blaze'e
gecersen `firebase deploy --only functions` yeterli; o zaman bu Worker'i
kaldirabilir ve `relayEndpoint` sabitini bos birakabilirsin. Ikisini birden
acik birakirsan ayni not icin iki bildirim gider.
