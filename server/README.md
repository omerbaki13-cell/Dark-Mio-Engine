# dark-engine-service

**Dark Mio Engine** oyununun hesap, puan ve liderlik tablosu servisi.
Tek bir Node/Express sunucusu: JSON API + iki hazır web paneli.

> Bu klasör (`server/`), oyun deposunun içinde durur ama oyundan bağımsızdır.
> Ayrı bir Node servisi olarak çalışır; Haxe/Lime derlemesini etkilemez.
> Yalnızca bu klasörü ayrı bir depoya (ör. `dark-engine-service`) kopyalarsan
> da aynı şekilde çalışır.

- `POST /register`, `POST /login` — hesap işlemleri (eski API ile uyumlu)
- `POST /score` — maç sonu puan yazma (tekrar gönderime dayanıklı)
- `GET /leaderboard` — toplam puana göre sıralama
- Yönetim: kullanıcı arama, **puan verme/düşürme**, **iki aşamalı hesap silme**, işlem geçmişi
- Supabase varsa oraya, yoksa **bellek içi demo moduna** yazar

---

## 1. Hızlı başlangıç (yerel, veritabanı gerekmez)

```bash
git clone https://github.com/omerbaki13-cell/Dark-Mio-Engine.git
cd Dark-Mio-Engine/server
npm install
ADMIN_KEY=dev-admin-key npm start
```

Konsolda şunu görürsün:

```
dark-engine-service http://0.0.0.0:3000 (storage: memory)
UYARI: Supabase anahtarlari yok, DEMO (memory) modunda calisiyor.
Yonetim paneli icin ADMIN_KEY: dev-admin-key
```

Aç:

| Adres | Ne işe yarar |
| --- | --- |
| <http://localhost:3000/> | Ana sayfa (servis durumu + linkler) |
| <http://localhost:3000/board> | Liderlik tablosu |
| <http://localhost:3000/panel> | Yönetim paneli |
| <http://localhost:3000/health> | JSON sağlık kontrolü |

> Demo kullanıcılar: `baki`, `mio`, `player1`, `test` — **şifreleri `1234`**.
> Bellek modunda sunucu yeniden başlayınca veriler sıfırlanır.

Demo olmadan paneli denemek istersen: `/panel` → **Demo modu** düğmesi
(veya doğrudan `/admin.html?mock=1`). Sunucuya hiçbir istek gitmez.

---

## 2. Supabase ile gerçek kurulum

1. Supabase projesi aç → **SQL Editor** → `supabase/migration.sql` dosyasının
   tamamını yapıştır ve çalıştır. Bu; `users` (puan kolonu dahil), `scores`,
   `matches` ve `admin_logs` tablolarını + indeksleri oluşturur.
2. **Project Settings → API** bölümünden şu iki değeri al:
   - `Project URL` → `SUPABASE_URL`
   - `service_role` (gizli!) → `SUPABASE_SERVICE_ROLE_KEY`
3. Sunucuyu başlat:

```bash
SUPABASE_URL=https://xxxx.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=eyJ... \
ADMIN_KEY=$(node -e "console.log(require('crypto').randomBytes(24).toString('hex'))") \
npm start
```

`/health` cevabında `"storage":"supabase"` görüyorsan bağlantı tamam.

> ⚠️ `service_role` anahtarı **asla** oyun istemcisine veya web sayfasına
> konmaz. Tarayıcı sadece bu sunucuyla konuşur, yönetim isteklerinde
> `X-Admin-Key` başlığını taşır. Tablolarda RLS açıktır ve policy yoktur,
> yani `anon` anahtarıyla kimse okuyamaz.

### Eski veritabanı (puan kolonu olmayan)

Servis, `users.points` kolonu yoksa otomatik olarak onsuz çalışmaya devam eder
(puanlar `scores` tablosundan toplanır). Kalıcı çözüm için migration'daki
`alter table ... add column if not exists points` satırını çalıştır.

---

## 3. Render'a deploy

### A) `render.yaml` ile (Blueprint)

Repo'da `render.yaml` hazır. Render → **New → Blueprint** → repoyu seç →
`ADMIN_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` değerlerini gir.

### B) Elle

- **New → Web Service** → repo bağla
- Build: `npm install` · Start: `npm start`
- Environment:

| Değişken | Zorunlu | Açıklama |
| --- | --- | --- |
| `ADMIN_KEY` | **evet** | Yönetim paneli anahtarı. Uzun ve rastgele olsun. |
| `SUPABASE_URL` | hayır | Yoksa demo modu |
| `SUPABASE_SERVICE_ROLE_KEY` | hayır | Yoksa demo modu |
| `PORT` | hayır | Render otomatik verir |
| `HOST` | hayır | Varsayılan `0.0.0.0` |

Render ücretsiz planı 15 dakika boşta kalınca uyur; ilk istek 30–60 saniye
sürebilir. Panellerde 90 saniyelik zaman aşımı ve "Render uyanıyor olabilir"
uyarısı bu yüzden var.

---

## 4. API sözleşmesi

Tüm cevaplar JSON. Hata formatı: `{ "success": false, "error": "mesaj" }`.

### Herkese açık

| Metot | Yol | Gövde / Sorgu | Cevap |
| --- | --- | --- | --- |
| `GET` | `/health` | — | `{status, storage, admin_enabled, detail}` |
| `POST` | `/register` | `{username, password}` | `{success, user_id, username, points}` · `409` kullanıcı varsa |
| `POST` | `/login` | `{username, password}` | `{success, user_id, username, points}` · `401` hatalıysa |
| `POST` | `/score` | `{user_id, score, song_name, points?, match_id?}` | `{success, points, added, duplicate}` |
| `GET` | `/leaderboard` | `?limit=25` | `{leaderboard:[{rank,user_id,username,points,songs_played,best_score,last_played}], updated_at}` |

`/register` kuralları: kullanıcı adı `^[A-Za-z0-9_-]{2,24}$`, şifre en az 4 karakter.

`/score` notları:
- `points` verilmezse `score` puan olarak sayılır (eski istemciler bozulmasın diye).
- `match_id` verilirse aynı maç ikinci kez puan yazmaz → `duplicate: true`, `added: 0`.
- Oyun tarafındaki ekonomi: **20 kombo = 1 puan**, maç başına en fazla 25 puan.

Geriye dönük uyumluluk: `GET /leaderboard?raw=1` eski `scores` tabanlı listeyi
döndürür (`{leaderboard:[{score, song_name, created_at, users:{username}}]}`).

### Yönetim (gerekli başlık: `X-Admin-Key: <ADMIN_KEY>`)

`Authorization: Bearer <ADMIN_KEY>` de kabul edilir. Anahtar yanlışsa `401`,
sunucuda `ADMIN_KEY` tanımlı değilse `503`.

| Metot | Yol | Gövde / Sorgu | Cevap |
| --- | --- | --- | --- |
| `GET` | `/users` | `?q=ara&limit=50` | `{users:[{user_id, username, points}]}` |
| `GET` | `/users/:id` | — | `{user:{user_id, username, points, created_at, songs_played, best_score, last_played}}` |
| `DELETE` | `/users/:id` | — | `{success:true}` — skorları ve maç kayıtları da silinir |
| `POST` | `/points` | `{user_id, amount, reason?}` | `{success, points, change}` |
| `POST` | `/users/:id/points` | `{amount, reason?}` | aynı |
| `GET` | `/admin/logs` | `?limit=50` | `{logs:[{action, target_username, amount, reason, admin_ip, created_at}]}` |
| `GET` | `/admin/summary` | — | `{users, total_points, top_user}` |

`amount` negatif olabilir (puan düşürme). Sonuç 0'ın altına inmez.
Puan değiştiren ve hesap silen her işlem `admin_logs` tablosuna yazılır.

### Örnek

```bash
# puan ver
curl -X POST https://SUNUCU/points \
  -H "X-Admin-Key: $ADMIN_KEY" -H 'Content-Type: application/json' \
  -d '{"user_id":1,"amount":10,"reason":"etkinlik odulu"}'

# hesap sil
curl -X DELETE https://SUNUCU/users/1 -H "X-Admin-Key: $ADMIN_KEY"
```

---

## 5. Oyun istemcisiyle bağlantı

Oyunun kullandığı adres **tek bir yerde** durur:

```
source/states/LoginState.hx  ->  public static var SERVER_URL:String = "https://dark-mio-engine.onrender.com";
```

- `/login` ve `/register` çağrıları bu adrese gider.
- `PlayState.finishMatchRecord()` maç sonu puanını
  `SERVER_URL + '/score'` adresine `{user_id, score, song_name, points, match_id}`
  gövdesiyle yollar (adres oradan okunur, ikinci kez yazılmaz).
- Sunucu adresi değişirse **sadece bu satırı** güncelle.

CORS açık olduğu için tarayıcı tabanlı (HTML5) derlemede de sorunsuz çalışır.

## 6. Web panelleri

### Liderlik tablosu — `web/leaderboard.html`

- İlk 3 için podyum, altında tam tablo
- Oyuncu arama, 10/25/50/100 limiti, 30 saniyede otomatik yenileme
- `?user=baki` → oyuncuyu vurgular
- `?server=https://baska-sunucu` → farklı sunucuya bakar
- `?mock=1` → internetsiz demo verisi
- Sunucu adresi boşsa bulunduğu adresi kullanır (yani Render'da ek ayar gerekmez)

### Yönetim paneli — `web/admin.html`

- Sunucu adresi + `ADMIN_KEY` girilir, `localStorage`'da saklanır
- Kullanıcı arama, kullanıcı seçme, puan (+1/+5/+10/+50, −1/−5) ve sebep yazma
- **Hesap silme iki aşamalı:** kullanıcı adını elle yazmadan silme düğmesi açılmaz,
  ardından ayrıca onay penceresi çıkar
- Sunucu işlem geçmişi + bu cihazdaki işlemlerin yerel kaydı
- `?mock=1` → sunucusuz deneme

Paneller tek dosyadır; gerekirse olduğu gibi başka bir yere de kopyalanabilir
(sadece `server` parametresini değiştirmen yeterli).

---

## 7. Dosya yapısı

```
server/server.js              # Express uygulaması, tüm rotalar
server/lib/db.js              # Supabase / bellek ikili veri katmanı
server/web/index.html         # ana sayfa
server/web/leaderboard.html   # liderlik tablosu (tek dosya)
server/web/admin.html         # yönetim paneli (tek dosya)
server/supabase/migration.sql # tablolar + indeksler + RLS
server/render.yaml            # Render Blueprint
server/.env.example           # değişken şablonu
```

Render'da **Root Directory** olarak `server` yazmayı unutma.

## 8. Notlar

- CORS tamamen açıktır: oyun istemcisi (Flixel/Haxe) doğrudan çağırabilir.
- Gövde limiti 64 KB, yönetim rotalarında dakikada 20 istek sınırı vardır.
- Aynı kullanıcı adıyla kayıt `409` döner (Supabase'de `23505` yakalanır).
- Şifreler `bcrypt` ile hashlenir; hiçbir cevapta hash veya `service_role` dönmez.
