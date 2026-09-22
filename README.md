# Ortak Notlar

Paylasilan not oturumlari: bir oturum acarsin, kodu paylasirsin, oturuma
katilan herkes ayni listeye not ekler, herkes notlari checkbox ile
isaretleyebilir ve **yeni bir not eklendiginde oturumdaki diger herkese push
bildirimi gider**.

Tek kod tabani: **Android** ve **Web**. iOS hedefi de projede duruyor ama
henuz derlenmedi (bkz. [iOS](#ios)).

**Canli surum:** https://note-app-a3675.web.app
(ayni site: https://note-app-a3675.firebaseapp.com)

---

## Ne yapiyor

| Ozellik | Durum |
| --- | --- |
| E-posta/sifre ve misafir (anonim) giris | ✅ |
| Oturum acma, 6 haneli katilma kodu | ✅ |
| Kod ile oturuma katilma / oturumdan ayrilma | ✅ |
| Ortak not listesi, canli senkronizasyon (Firestore) | ✅ |
| Checkbox ile isaretleme — kimin isaretledigi gorunur | ✅ |
| Not duzenleme / silme / tamamlananlari toplu silme | ✅ |
| Yeni notta tum uyelere push bildirimi (FCM) | ✅ |
| Uygulama acikken ust banner, bildirime tiklayinca oturuma gitme | ✅ |
| Web ve mobil ayni hesapla | ✅ |

---

## Mimari

```
Flutter (Android + Web)
  ├── lib/models/      Firestore dokumanlarinin Dart karsiliklari
  ├── lib/services/    auth · session · note · notification
  ├── lib/screens/     login · sessions · session · setup_required
  └── lib/widgets/     note_tile · member_avatars · prompt_dialog · feedback

Firebase
  ├── Auth             e-posta/sifre + anonim
  ├── Firestore        canli senkronizasyon + guvenlik kurallari
  └── Cloud Messaging  Android bildirimi + Web Push

relay/                 Cloudflare Worker -- FCM gonderimini yapan sunucu
functions/             ayni isin Cloud Functions surumu (Blaze plani gerekir)
```

Bildirimi gonderen sunucu tarafi **Cloudflare Worker**'da (`relay/`): Firebase
Spark planinda Cloud Functions deploy edilemiyor, FCM'e gonderim ise servis
hesabi anahtari istedigi icin istemciden yapilamaz. `functions/` ayni mantigin
Firestore trigger'li surumu olarak duruyor; Blaze'e gecersen onu kullanabilirsin.

### Veri modeli

```
users/{uid}
  displayName, email, isGuest, fcmTokens[]

joinCodes/{KOD}                 ← koddan oturuma ulasmak icin ayri tablo
  sessionId, ownerId

sessions/{sessionId}
  title, joinCode, ownerId
  memberIds[]                   ← guvenlik kurallari ve sorgular icin
  memberNames{uid: isim}        ← ekranda isim gostermek icin (denormalize)
  createdAt, updatedAt

sessions/{sessionId}/notes/{noteId}
  text, done
  authorId, authorName, createdAt, updatedAt
  doneById, doneByName, doneAt  ← isaretleyen kisi
```

`joinCodes` neden ayri: guvenlik kurallari, oturumu **henuz okuyamayan** bir
kullanicinin oturum dokumanini sorgulamasina izin vermez. Kod → sessionId
eslemesi bu yuzden herkesin okuyabilecegi ayri bir koleksiyonda durur.

---

## Kurulum

### 1. Flutter

Bu repoda Flutter **3.47.5** ile calisildi. SDK kurulu degilse:

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"     # kalici olmasi icin ~/.zshrc'ye ekle
flutter --version
```

### 2. Firebase projesi

1. <https://console.firebase.google.com> uzerinden yeni proje ac.
2. **Authentication → Sign-in method**: `E-posta/Sifre` ve `Anonim` yontemlerini
   etkinlestir.
3. **Firestore Database** olustur (production mode; kurallari 4. adimda
   yukleyecegiz).
4. **Project Settings → Cloud Messaging → Web Push certificates**: bir anahtar
   cifti olustur, degerini not et (VAPID anahtari).

### 3. Projeyi bagla

Bu repo **`note-app-a3675`** projesine bagli olarak gelir:

| Yer | Durum |
| --- | --- |
| `android/app/google-services.json` | ✅ eklendi |
| `lib/firebase_options.dart` → `android` | ✅ dolduruldu |
| `lib/firebase_options.dart` → `webPushVapidKey` | ✅ dolduruldu |
| `lib/firebase_options.dart` → `web` | ⬜ Web App kaydi bekliyor |
| `web/firebase-messaging-sw.js` → `firebaseConfig` | ⬜ ayni degerler |

Android paket adi: **`com.example.ortaknotlar`** (google-services.json ile ayni
olmak zorunda).

Web'i tamamlamak icin Firebase Console → **Project settings → Your apps →
Web app** bolumundeki `firebaseConfig` nesnesinden `apiKey` ve `appId`
degerlerini al; ikisini birden su iki dosyaya yaz:

- `lib/firebase_options.dart` → `DefaultFirebaseOptions.web`
- `web/firebase-messaging-sw.js` → `firebaseConfig`

(Service worker Dart kodunu okuyamadigi icin ayni degerler iki yerde durur.)

Alternatif olarak tek komutla da yapilabilir -- ancak bu komut
`firebase_options.dart` dosyasinin **uzerine yazar** ve `webPushVapidKey`
sabitini siler, sonradan geri eklemen gerekir:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=note-app-a3675 --platforms=android,web
```

> Yapilandirmasi eksik olan platformda uygulama cokmez; acilista ne yapilmasi
> gerektigini anlatan bir **kurulum ekrani** gosterir. Yani su an Android
> calisir, web kurulum ekranini gosterir.

### 4. Kurallari yayinla

```bash
# firebase-tools Node.js 20+ ister.
# Sistemde eski bir Node varsa: https://github.com/nvm-sh/nvm
npm install -g firebase-tools
firebase login
# .firebaserc zaten note-app-a3675 projesini gosteriyor

firebase deploy --only firestore:rules,firestore:indexes
```

### 5. Bildirim relay'ini yayinla

Bildirimler `relay/` altindaki Cloudflare Worker uzerinden gider. Kurulum
adimlari (servis hesabi anahtari, `wrangler deploy`, adresin uygulamaya
yazilmasi) **[relay/README.md](relay/README.md)** icinde.

Relay kurulmazsa uygulamanin geri kalani (ortak liste, canli senkronizasyon,
checkbox) sorunsuz calisir; yalnizca **hicbir bildirim gitmez** — uygulama ici
banner da FCM mesajiyla tetiklendigi icin o da gorunmez.

> **Alternatif:** Proje **Blaze (kullandikca ode)** planindaysa ayni isi
> `functions/index.js` Firestore trigger'i ile yapar:
> `cd functions && npm install && cd .. && firebase deploy --only functions`.
> Ikisini birden acik birakma; ayni not icin iki bildirim gider.

---

## Calistirma

```bash
export PATH="$HOME/flutter/bin:$PATH"

# Web (gelistirme)
flutter run -d chrome

# Android (cihaz/emulator bagliyken)
flutter run -d android

# Web (yayin derlemesi)
flutter build web --release
firebase deploy --only hosting        # build/web dizinini yayinlar
```

Web'de push bildirimi **yalnizca HTTPS** (veya `localhost`) uzerinde calisir.
`firebase deploy --only hosting` zaten HTTPS verir.

Yayinlanan adres: https://note-app-a3675.web.app

### Android APK

```bash
flutter build apk --release
# cikti: build/app/outputs/flutter-apk/app-release.apk
```

`android/app/build.gradle.kts` icindeki release imzasi su an **debug**
anahtarini kullaniyor. Play Store'a cikacaksan kendi keystore'unu tanimla.

### iOS

> **iOS derlemesi bu depoda yapilamaz.** Apple'in araç zinciri yalnizca macOS'ta
> calisir; Linux/Windows'ta `flutter build ios` / `flutter build ipa` komutlari
> Flutter'da kayitli bile degildir. Asagidaki adimlarin tamami bir **Mac**'te
> kosulur.

Projede hazir olanlar (`flutter create --platforms=ios` ile eklendi):

| Ayar | Deger |
| --- | --- |
| Bundle id | `com.example.ortaknotlar` (Android ile ayni) |
| Gorunen ad | Ortak Notlar |
| Minimum surum | iOS 15.0 (Firebase iOS SDK'nin istedigi taban) |
| Arka plan modu | `remote-notification` (Info.plist) |

Eksik olanlar ve Mac'te yapilacaklar:

1. **Xcode + CocoaPods** kurulu olsun (`sudo gem install cocoapods`).
2. **Firebase'de iOS uygulamasi ac.** Console > Add app > iOS, bundle id
   `com.example.ortaknotlar`. Sonra:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=ios
   ```
   Bu komut `lib/firebase_options.dart` icindeki `ios` alanindaki
   `REPLACE_ME_*` degerlerini doldurur ve
   `ios/Runner/GoogleService-Info.plist` dosyasini ekler. Doldurulmadan
   uygulama iOS'ta cokmez, **kurulum ekranini** gosterir.
3. **Push yetkisi.** Xcode > Runner > Signing & Capabilities:
   - Team sec (imzalama icin **Apple Developer Program** uyeligi gerekir),
   - `+ Capability` > **Push Notifications** ekle.
4. **APNs anahtari.** Apple Developer > Keys > yeni **APNs Auth Key** (.p8) →
   Firebase Console > Project settings > Cloud Messaging > *Apple app
   configuration* bolumune yukle. Bu yapilmadan iOS'a bildirim gitmez.
5. Derle:
   ```bash
   flutter build ipa                 # cikti: build/ios/ipa/*.ipa
   # veya Xcode ile: flutter build ios --release && open ios/Runner.xcworkspace
   ```
   Simulator icin uyelik gerekmez: `flutter run -d <simulator-adi>`.

CocoaPods ilk `flutter build ios` sirasinda `ios/Podfile` dosyasini kendisi
uretir. Bagimlilik cozumunde surum sikayeti gelirse Podfile'daki
`platform :ios, '15.0'` satirini acikca yaz.

### MIUI / HyperOS kurulum kisitlamasi

Xiaomi cihazlarda `adb install` bir sure sonra
`INSTALL_FAILED_USER_RESTRICTED: Install canceled by user` donmeye basliyor
(gelistirici secenekleri > "USB ile yukleme" kisitlamasi). Shell uzerinden
kurulum bu kisitlamaya takilmiyor:

```bash
tool/preinstall_for_test.sh <cihaz-id>
flutter test integration_test/backend_test.dart -d <cihaz-id>
```

Betik APK'yi `pm install` ile kurar ve Flutter'in `/data/local/tmp/sky.<pkg>.sha1`
isaretini birakir; boylece `flutter test` kurulum adimini atlar.

> Dikkat: `flutter test integration_test/...` giris noktasi **test dosyasi**
> olan bir APK uretir. O APK kuruluyken uygulama simgesine dokununca normal
> uygulama acilmaz. Cihazda gercek uygulamayi kullanmak icin
> `flutter build apk --release` cikitisini kur.

### Derleme bellegi

`android/gradle.properties` icindeki JVM tavanlari Flutter sablonunun
varsayilanindan (`-Xmx8G`) dusuruldu:

```properties
org.gradle.jvmargs=-Xmx2560m -XX:MaxMetaspaceSize=1g -XX:ReservedCodeCacheSize=256m
kotlin.daemon.jvmargs=-Xmx1536m
org.gradle.workers.max=2
```

Sablon degerleri, Gradle ve Kotlin daemon'lari birlikte 16 GB tavan istedigi
icin 15 GB'lik bir makinede cekirdek OOM killer'ini tetikliyordu. Daha bol
bellegi olan bir makinede bu satirlari yukseltebilirsin.

---

## Bildirimler nasil calisiyor

1. Kullanici not ekler → `sessions/{id}/notes/{noteId}` dokumani olusur.
2. `NoteService.addNote` yazma bittikten sonra relay'i tetikler:
   `POST <worker>/notify { sessionId, noteId }` + Firebase ID token.
   Cagri beklenmez; basarisiz olursa not yine de kaydedilmistir.
3. Worker token'i dogrular ve **notu gercekten o kullanicinin yazdigini**
   Firestore'dan okuyarak kanitlar. Istemci kime gonderilecegini soylemez.
4. Oturumun `memberIds` listesinden **notu yazan disindaki** herkesin
   `users/{uid}.fcmTokens` token'lari toplanir, FCM HTTP v1 ile gonderilir.
5. Nota `notifiedAt` damgasi yazilir; ayni not icin ikinci cagri bos doner.
6. Gecersiz hale gelmis token'lar (`UNREGISTERED`) kullanici dokumanindan
   otomatik temizlenir.

Istemci tarafinda:

| Durum | Ne olur |
| --- | --- |
| Android, uygulama kapali/arka planda | Sistem bildirimi (FCM `notification` yuku) |
| Android, uygulama acik | `flutter_local_notifications` + uygulama ici banner |
| Web, sekme kapali/arka planda | `web/firebase-messaging-sw.js` bildirimi gosterir |
| Web, sekme acik | Uygulama ici banner |
| Bildirime tiklandi | Ilgili oturum ekrani acilir (`/#/session/<id>`) |

---

## Test

Iki katman var:

```bash
flutter analyze        # 0 uyari
flutter test           # 55 birim/widget testi -- sahte Firestore, cihaz gerekmez

# Cihazda, GERCEK Firebase projesine karsi (guvenlik kurallarini da sinar):
flutter test integration_test/backend_test.dart -d <cihaz-id>
```

`backend_test.dart` neden ayri: birim testleri `fake_cloud_firestore`
kullandigi icin **guvenlik kurallarini calistirmaz**. Kurallarla uygulamanin
celisebilecegi yerler ancak gercek projeye karsi gorunur -- nitekim iki hata
boyle yakalandi (bkz. asagidaki not).

Yerelde dogrulanan derlemeler:

| Komut | Sonuc |
| --- | --- |
| `flutter analyze` | 0 uyari |
| `flutter test` | 57 test gecti |
| `flutter build web --release` | ✅ (tarayicida acilip render ettigi goruldu) |
| `flutter build apk --debug` | ✅ (`com.example.ortaknotlar`, Firebase kaynaklari APK icinde) |

> Not: Testler `fake_cloud_firestore` kullandigi icin **guvenlik kurallarini
> calistirmaz**. Kurallari dogrulamak icin Firebase emulator suite ya da gercek
> proje gerekir. Testler relay'in cagrildigini dogrular ama ag'a cikmaz; push
> bildiriminin uctan uca akisi yalnizca yayindaki Worker ve gercek iki cihazla
> (ya da iki farkli hesapla) denenebilir.

`fake_cloud_firestore` ve `firebase_auth_mocks` sayesinde testler **gercek bir
Firebase projesi olmadan** calisir:

- `test/session_service_test.dart` — oturum acma, kod uretimi, katilma,
  ayrilma, silme, isim senkronizasyonu
- `test/note_service_test.dart` — not ekleme, isaretleme, duzenleme,
  tamamlananlari temizleme
- `test/session_screen_test.dart` — oturum ekraninin gercek veriyle
  render edilmesi, checkbox etkilesimi, not gonderme
- `test/formatting_test.dart` — tarih/kod bicimlendirme, hata mesajlari

---

## Guvenlik kurallari ozeti

`firestore.rules` dosyasi sunlari garanti eder:

- Oturumu **yalnizca uyeleri** okuyabilir.
- Uye olmayan biri oturum dokumanina **yalnizca kendini ekleyerek** dokunabilir
  (katilma); baslik, kod ve sahiplik degistirilemez.
- Uye kendini listeden cikarabilir (ayrilma), baskasini cikaramaz.
- Baslik degistirme ve oturum silme **yalnizca sahibe** aittir.
- Not ekleyen, `authorId` alanina baskasinin kimligini yazamaz.
- Notu oturumdaki herkes isaretleyebilir/duzenleyebilir, ama `authorId`
  degistirilemez.
- Notu yalnizca **yazari** veya **oturum sahibi** silebilir.

Kurallari degistirirsen yayinlamayi unutma:
`firebase deploy --only firestore:rules`

---

## Gercek projeye karsi test ederken bulunan hatalar

Sahte Firestore ile yazilan birim testleri guvenlik kurallarini
calistirmadigi icin sunlar ancak cihazda, gercek projeye karsi gorundu:

1. **Kodla katilma hic calismiyordu.** `joinByCode` uyeyi eklemeden once
   oturumu bir transaction icinde okuyordu; kurallar ise oturumu yalnizca
   uyelerine okutuyor. Katilmak isteyen kisi henuz uye olmadigi icin akis
   basta kilitleniyordu. Cozum: okuma kaldirildi, dogrudan `arrayUnion` ile
   yaziliyor -- dogrulamayi sunucudaki kurallar yapiyor.

2. **Silinmis oturum "yetkiniz yok" diyordu.** Var olmayan dokumanda
   `resource` null oldugu icin `uid() in resource.data.memberIds` hata verip
   reddediliyordu. `allow read: if isSignedIn() && (resource == null || isMember())`
   ile duzeltildi; olmayan dokumanda sizdirilacak veri zaten yok.

3. **Silinen hesabin profili kaliyordu.** `users` icin `allow delete: if false`
   yazilmisti; hesabini silen kullanicinin dokumanini silecek kimse kalmiyordu.
   Artik kullanici kendi dokumanini silebiliyor.

## Bilinen sinirlar

- **iOS hic derlenmedi.** `ios/` hedefi projede var ama Apple araç zinciri
  macOS istedigi icin bu depoda bir kez bile derlenemedi; Firebase iOS
  yapilandirmasi ve APNs anahtari da eksik. Kod tarafinda engel yok — kullanilan
  paketlerin hepsi iOS'u destekliyor ve `NotificationService` iOS dalini zaten
  iceriyor. Adimlar: [iOS](#ios).
- **Bildirim istemcinin cagrisiyla tetiklenir**, Firestore trigger'i ile degil.
  Not yazildiktan hemen sonra uygulama kapanirsa (veya ag koparsa) o notun
  bildirimi gitmez; not yine de kaydedilmistir. Firestore trigger'i Blaze
  plani ister — `functions/index.js` o gun icin hazir duruyor.
- **Misafir (anonim) giris Firebase Console'da kapali.** Giris ekraninda
  "Misafir" sekmesi duruyor ama secilince
  `admin-restricted-operation` hatasi aliniyor. Ya Authentication >
  Sign-in method > Anonymous acilmali, ya da sekme kaldirilmali.
- **Misafir hesaplar cihaza baglidir.** Tarayici verisi silinirse oturumlara
  erisim kaybolur. Kalici erisim icin e-posta/sifre ile kayit ol.
- **Cevrimdisi**: Firestore'un yerel onbellegi sayesinde notlar cevrimdisi
  yazilabilir ve baglanti gelince senkronize olur; ancak bildirim ancak sunucu
  yazmayi aldiginda gider.
