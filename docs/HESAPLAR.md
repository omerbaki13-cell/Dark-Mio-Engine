# Hesaplar (çok hesaplı giriş)

Oyun cihazda **en fazla 4 hesap** saklar. Hesaplar arasında şifre girmeden geçiş
yapılır ve **her hesabın puanı ayrıdır**.

## Ekran

Ana menüde sağ üstteki kullanıcı adına tıkla → **HESAPLAR** ekranı:

```
              HESAPLAR
     Hesap sec veya yeni hesap ekle

              PUAN: 47

 > Older12166   47 P  (aktif)      <- dokun: puanı yenile
   mio          25 P               <- dokun: bu hesaba geç
   + Giris yap                     <- dokun: yeni hesap ekle
   + Giris yap

           PUANI YENILE
             Cikis Yap
             Geri Don
```

- **Dolu satır** = cihazda kayıtlı hesap. Dokununca o hesaba geçilir; puan o
  hesabın kendi puanıdır.
- **`+ Giris yap`** = boş slot. Dokununca giriş/kayıt formu açılır; giriş
  başarılı olunca hesap listeye eklenir ve aktif olur.
- **PUANI YENİLE** = aktif hesabın puanını sunucuyla eşitler (aşağıya bak).
- **Çıkış Yap** = aktif hesabı listeden çıkarır. Puanı silinmez: sunucuya
  yazılır, tekrar giriş yapınca geri gelir.
- **Geri Don** = ana menü.

## Puan yenileme

Ekran açılınca bir kez otomatik, ayrıca düğmeye basınca:

1. `GET /profile?username=...` → sunucudaki puan okunur.
2. Sunucu yüksekse cihazdaki puan yükseltilir → `+N puan guncellendi`.
3. Cihazdaki yüksekse fark `POST /sync` ile sunucuya yazılır →
   `N puan sunucuya gonderildi`.
4. **Puan asla azalmaz.**

Hesap değiştirirken ve çıkarken de eski hesabın puanı arka planda sunucuya
gönderilir, böylece puanlar hiçbir hesapta kaybolmaz.

## Teknik

`source/backend/UserSession.hx`

| Alan / metot | Açıklama |
| --- | --- |
| `accounts` (kayıt içinde) | `[{username, userId, points}]`, en fazla 4 |
| `MAX_ACCOUNTS` | 4 |
| `getAccounts()` | listedeki hesapların kopyası |
| `loginAccount(name, id, serverPoints)` | giriş/kayıt sonrası: ekle veya güncelle, aktif yap |
| `switchAccount(name)` | kayıtlı hesaba geç |
| `removeAccount(name)` | hesabı listeden çıkar (puanı sunucuda kalır) |
| `points` / `addPoints()` | **sadece aktif hesaba** yazar |

`source/backend/MatchRecords.hx`

- `awardedTotal()` artık **hesap başına** (`awardedByUser`). Eskiden global tek
  toplam tutuluyordu; bu yüzden hesap değiştirince puan diğer hesaba sızıyor ve
  "hesabı değiştirdim puan aynı" hatası oluşuyordu.
- Eski (global) toplam, ilk açılışta aktif kullanıcıya bir kez taşınır.

## Sunucu uçları

| Metot | Yol | Açıklama |
| --- | --- | --- |
| `GET` | `/profile/:id` | kullanıcı + puan + istatistik (salt okuma) |
| `GET` | `/profile?username=` | aynı; eski `user_id` taşıyan istemciler için |
| `POST` | `/sync` | `{user_id, points}` — sadece yukarı yazar |
