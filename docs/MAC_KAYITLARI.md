# Maç Kayıtları (Render + Supabase)

Bu sistem bir şarkı (maç) bittiğinde sonucu kaydeder.

## v2'de düzeltilen hatalar

| Hata | Sebep | Çözüm |
|---|---|---|
| Puanlar çıkıp girince siliniyordu | `UserSession` puanı sadece giriş yapılmışsa okuyordu, `logout()` puanı sıfırlıyordu | Puan her zaman yükleniyor, çıkışta silinmiyor, `MatchRecords` toplamından (ledger) geri toparlanıyor |
| Kayıtlar hep **BEKLİYOR** kalıyordu | `supabase.json` içindeki `.../rest/v1/` URL'sinin üzerine kod bir daha `/rest/v1/` ekliyordu → `.../rest/v1//rest/v1/match_records` → **404** | URL normalize ediliyor (sondaki `/`, `/rest/v1`, `/rest/v1/` kırpılır) |
| Ayar dosyası okunmuyordu | Sadece `mods/supabase.json` ve kök `supabase.json` aranıyordu | `supabase.json`, `mods/`, `example_mods/` ve bunların alt klasörleri taranıyor |
| Hatanın sebebi görünmüyordu | HTTP kodu kaydedilmiyordu | Her denemenin kodu/mesajı maç kaydına ve ekrana yazılıyor |
| "Hangi puanı aldım" belli değildi | Puan dökümü tutulmuyordu | Her eşik için `combo`, `at` (şarkı süresi), `points` kaydı tutuluyor |

### URL nasıl yazılmalı?

Aşağıdakilerin **hepsi** çalışır, kod hepsini aynı adrese çevirir:

```
https://PROJE.supabase.co
https://PROJE.supabase.co/
https://PROJE.supabase.co/rest/v1
https://PROJE.supabase.co/rest/v1/
https://PROJE.supabase.co/rest/v1/match_records
```

Efektif istek adresi her zaman: `https://PROJE.supabase.co/rest/v1/match_records?on_conflict=match_id`

## Puan kuralları

| Durum | Puan |
|---|---|
| Her **20 kombo** | **+1 puan** (40, 60, 80… diye devam eder) |
| Botplay açık | ❌ Puan yok |
| Sonsuz Mod (Infinite Mode) açık | ❌ Puan yok |
| Antrenman (Practice) modu | ❌ Puan yok |
| Chart modu | ❌ Puan yok |
| Aynı şarkı + zorluk daha önce puan aldıysa | ❌ Tekrar puan yok |

- Puan, kombo eşiğine ulaşıldığı anda **biriktirilir**, şarkı **bitince** hesaba yazılır.
  Böylece ölüp yeniden başlarsan puan kaybetmezsin, şarkıyı bitirirsen kazanırsın.
- Her eşik için `kombo / şarkı süresi / puan` dökümü maç kaydına yazılır
  (`points_log`) ve Maç Kayıtları ekranında görünür.
- Şarkı bitip puan hesaba yazıldığı an o maç "alındı" olarak işaretlenir
  (`MioEngine/mio_matches` kaydı), yani aynı şarkı + zorluk kombinasyonundan ikinci kez puan çıkmaz.
- Bir maçta en fazla **25 eşik** ödüllendirilir (en fazla 25 puan).
- Oyun içinde sol üstte puan durumu yazar:
  - `PUAN: 20 KOMBO = +1` → puan alınabilir
  - `PUAN: KAPALI (BOTPLAY / SONSUZ MOD)` → puan yok
  - `PUAN: BU MAÇTAN ALINDI` → bu şarkıdan daha önce puan alınmış

> "Her oynayışta tekrar puan alınsın" istersen `source/backend/MatchRecords.hx` içindeki
> `oncePerSong` değerini `false` yap (veya `mods/supabase.json` içine `"once_per_song": false` ekle).

## 0) Oyun içi "Maç Kayıtları" ekranı

Ana menüde sol üstte **MAÇ KAYITLARI [TAB]** yazısı vardır:

- Tıkla / dokun ya da **TAB** tuşuna bas → maç listesi açılır.
- Listede: sıra, şarkı (zorluk), skor, en yüksek kombo, kazanılan puan ve durum
  (`SENKRON` / `BEKLİYOR` / `HATA 404 ...`) görünür.
- Alt panelde seçili maçın **puanı, sebebi** (BOTPLAY / SONSUZ MOD / ZATEN ALINDI / KOMBO YOK),
  **eşik sayısı**, **puan alınan anlar** (`20x @00:35 = +1, 40x @01:05 = +1`) ve Supabase hata mesajı yazar.
- Üstte Supabase ayar durumu: ayar yoksa kırmızı, bağlıysa yeşil + son HTTP kodu.
- `ONAY` (veya ekrandaki A) → bekleyen kayıtları tekrar göndermeyi dener.
- `SIFIRLA` (veya ekrandaki B) → listeyi yeniler.
- **`SHIFT` basılı tutup `SIFIRLA`** → "puan alındı" işaretlerini temizler (test için:
  aynı şarkıdan yeniden puan alabilirsin; maç kayıtları silinmez).
- `GERİ` → ana menüye döner.

> Test sırasında bir şarkıdan puan aldıysan ve tekrar denemek istiyorsan bu kısayolu kullan.

## 1) Render dosyası

Her maç sonunda oyun klasörüne `render-ingame.json` yazılır:

```json
{
  "engine": "Dark Mio Engine",
  "render_file": "render-ingame.json",
  "updated_at": "2026-10-23 12:00:00",
  "supabase_url": "https://PROJE.supabase.co",
  "config_file": "<oyun klasörü>/mods/supabase.json",
  "config_error": null,
  "last_sync_status": 201,
  "last_sync_error": null,
  "total_matches": 3,
  "total_pending_sync": 0,
  "awarded_points_total": 12,
  "matches": [
    {
      "match_id": "bopeebo-normal",
      "username": "oyuncu",
      "user_id": 12,
      "song": "Bopeebo",
      "difficulty": "Normal",
      "score": 125000,
      "max_combo": 120,
      "misses": 3,
      "accuracy": 96.5,
      "points": 60,
      "botplay": false,
      "infinite_mode": false,
      "practice_mode": false,
      "story_mode": false,
      "eligible": true,
      "points_reason": "OK",
      "milestones": 5,
      "points_log": [
        { "combo": 20, "points": 1, "at": "00:35", "step": 217 },
        { "combo": 40, "points": 1, "at": "01:05", "step": 400 }
      ],
      "synced": true,
      "sync_status": "synced",
      "sync_error": null,
      "played_at": "2026-10-23 12:00:00"
    }
  ]
}
```

Dosya konumu:

- **Android**: uygulamanın dış dosya klasörü (`StorageUtil.getStorageDirectory()`)
- **Masaüstü**: oyunun çalıştığı klasör (`Sys.getCwd()`)

## 2) Supabase

### Ayar dosyası

Oyun klasörüne `mods/supabase.json` koy (örnek: `docs/supabase.example.json`).
Bu klasörde hazır bir `mods/supabase.json` var; kendi projen için düzenle.
Aynı dosya `example_mods/` içine de konabilir.

```json
{
  "url": "https://PROJE.supabase.co",
  "anon_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9....",
  "table": "match_records",
  "once_per_song": true
}
```

Ayar girilmezse kayıtlar kaybolmaz; `MioEngine/mio_matches` kaydında **bekleyen kuyrukta** tutulur
ve ayarlar eklendiğinde otomatik gönderilir (her frame denenir, oyunu dondurmaz).

### Tablo (SQL)

Supabase > SQL Editor:

```sql
create table if not exists public.match_records (
  id            bigint generated by default as identity primary key,
  match_id      text unique not null,
  username      text,
  user_id       bigint,
  song          text,
  difficulty    text,
  score         integer,
  max_combo     integer,
  misses        integer,
  accuracy      numeric,
  points        integer,
  botplay       boolean default false,
  infinite_mode boolean default false,
  practice_mode boolean default false,
  story_mode    boolean default false,
  played_at     text,
  created_at    timestamptz default now()
);

alter table public.match_records enable row level security;

create policy "anon can insert matches"
  on public.match_records for insert to anon with check (true);

create policy "anon can read matches"
  on public.match_records for select to anon using (true);
```

İstemci, `POST /rest/v1/match_records` isteğini `apikey` + `Authorization: Bearer <anon_key>`
başlıklarıyla atar. `match_id` tekil olduğu için aynı maç iki kez gönderilse bile tabloda
mükerrer kayıt oluşmaz (409 yanıtı başarı sayılır).

## 3) Hesap sunucusu

Puan kazanılan maçlarda eski uç noktaya da haber verilir:

`POST https://dark-mio-engine.onrender.com/score` → `{ "user_id": 1, "score": 60000, "song_name": "Bopeebo", "points": 3, "match_id": "..." }`

Bu istek yalnızca maç geçerliyse (botplay / sonsuz mod / antrenman kapalı) ve puan kazanıldıysa
atılır, böylece hesap tarafındaki puanlar da güncel kalır.
