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
