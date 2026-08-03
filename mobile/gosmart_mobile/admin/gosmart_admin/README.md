# GoSmart Yönetim

Mobil müşteri/sürücü uygulamasından ayrı Flutter Web yönetim panelidir.
Yalnız ID token'ında gerçek boolean `gosmartAdmin: true` claim'i bulunan
hesaplar erişebilir. Girişte token zorla yenilenir.

```powershell
flutter run -d chrome
flutter build web --release
```

Panel Firestore veya Storage client SDK kullanmaz. Yönetici okumaları
`europe-west1` bölgesindeki callable işlevler üzerinden yapılır. Belge
görüntüleme kısa süreli signed URL üreten callable üzerinden panel içindeki
geçici görüntü/PDF alanında yapılır. URL yalnız bellekte tutulur; log,
localStorage, sessionStorage veya IndexedDB'ye yazılmaz. `getDownloadURL`,
Firestore ve Storage client erişimi kullanılmaz.

Belge onayı, kontrollü yeniden yükleme isteği ve başvuru nihai kararları
callable işlevler üzerinden gönderilir. Backend nihai yetki, bütünlük ve stale
review otoritesidir. Mutation sonrasında ayrıntı ve liste backend'den yeniden
yüklenir. Otomatik testler gerçek production kararı veya signed URL üretmez.

Yerel manuel incelemede yönetici girişinden sonra pending başvuru açılır,
belge önizlemesinin panel içinde çalıştığı ve URL metninin görünmediği kontrol
edilir. Production kararları yalnız gerçek inceleme tamamlandıktan sonra
yönetici tarafından verilir. Bu çalışma Firebase deploy yapmaz ve credential,
yönetici hesabı ya da UID içermez.

## Firebase Hosting

Admin panel, mobil uygulamadan ayrı `gosmart-admin-fd8f6` Firebase Hosting
sitesini ve `admin` deploy target'ını kullanır. Canlı deploy öncesinde
`admin-review` adlı, 7 gün süreli preview channel kullanılır. Preview URL herkese
açık kabul edilmeli ve paylaşılmamalıdır; asıl erişim kontrolü Firebase Auth ile
gerçek boolean `gosmartAdmin: true` claim'idir. Preview gerçek production
Firebase backend ile çalışır ve production kararları yalnız manuel inceleme
sonrasında verilmelidir.

Hosting yapılandırması SPA rewrite, temel güvenlik header'ları ve kritik app shell
dosyalarında `no-cache, no-store, must-revalidate` davranışı içerir. Asset'ler
kısa süreli cache edilir. `robots.txt` ile HTML robots meta etiketi
`noindex, nofollow` uygular; bunlar erişim kontrolü değildir. Content Security
Policy, gerçek Firebase Auth, callable, CanvasKit, görüntü ve PDF originleriyle
ayrı allowlist testi yapılmak üzere sonraki aşamaya bırakılmıştır. Bu hazırlıkta
canlı deploy yapılmamıştır.

## İnceleme Geçmişi

Başvuru ayrıntısındaki inceleme geçmişi yalnız admin yetkili, salt okunur
callable üzerinden alınır. Admin panel Firestore client SDK kullanmaz ve audit
koleksiyonuna client tarafından doğrudan erişim kapalıdır. Timeline görüntüleme
yeni bir audit kaydı üretmez; veriler cursor tabanlı sayfalanır.

Response ve arayüz reviewer UID'si, yönetici e-postası, başvuru kişisel verisi,
signed belge URL'si veya internal belge bağlamı içermez. Timeline yalnız bellekte
tutulur; çıkışta, yetki kaybında ve ayrıntı ekranından ayrılırken temizlenir.
Başarılı kararlar ve stale durumları sonrasında geçmiş backend'den yeniden
yüklenir. Bu geliştirme kapsamında Firebase deploy yapılmamıştır.
