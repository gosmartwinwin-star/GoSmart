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
görüntüleme ve başvuru/belge kararları sonraki aşamaya bırakılmıştır.
Bu çalışma Firebase deploy yapmaz ve credential, yönetici hesabı ya da UID
içermez.
