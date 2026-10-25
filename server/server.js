'use strict';

/**
 * dark-engine-service
 * ------------------------------------------------------------------
 * Dark Mio Engine icin hesap / puan / liderlik servisi.
 *
 * Oyun istemcisinin kullandigi endpointler (geriye donuk uyumlu):
 *   POST /register   { username, password }
 *   POST /login      { username, password }  -> { success, user_id, username, points }
 *   POST /score      { user_id, score, song_name, points?, match_id? }
 *   GET  /leaderboard[?limit=50&raw=1]
 *   GET  /health
 *
 * Yonetim (X-Admin-Key gerekir):
 *   GET    /users?q=&limit=
 *   GET    /users/:id
 *   DELETE /users/:id
 *   POST   /points            { user_id, amount, reason }
 *   GET    /admin/logs?limit=
 *   GET    /admin/summary
 * ------------------------------------------------------------------
 */

const path = require('path');
const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');

const { createDb } = require('./lib/db');

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';

const db = createDb();
const isMemory = db.kind === 'memory';

// ADMIN_KEY yoksa: memory modunda demo anahtari uret, gercek modda yonetim kapali kalir.
let ADMIN_KEY = process.env.ADMIN_KEY || '';
if (!ADMIN_KEY && isMemory) ADMIN_KEY = 'dev-admin-key';

const app = express();
app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '64kb' }));

/* ---------------------------- yardimcilar ---------------------------- */

const asyncRoute = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

const bad = (res, code, message) => res.status(code).json({ success: false, error: message });

const USERNAME_RE = /^[A-Za-z0-9_\-]{2,24}$/;

function validateCredentials(username, password) {
  if (typeof username !== 'string' || typeof password !== 'string') return 'username ve password gerekli';
  if (!USERNAME_RE.test(username)) return 'Kullanici adi 2-24 karakter olmali (harf, rakam, _ veya -)';
  if (password.length < 4) return 'Sifre en az 4 karakter olmali';
  return null;
}

// basit hiz siniri (ayni IP, dakikada N istek)
// Oyun trafigi icin ayri ve daha yuksek bir sinir kullaniyoruz: ayni IP
// arkasinda birden fazla oyuncu olabilir (mobil operator NAT'i gibi) ve
// 20/dk siniri mac sonu puanlarinin sessizce dusmesine yol aciyordu.
function makeLimit(max) {
  const hits = new Map(); // her sinirin kendi sayaci var (birbirini etkilemesin)
  return function rateLimit(req, res, next) {
    const ip = req.ip || 'unknown';
    const now = Date.now();
    const item = hits.get(ip) || { count: 0, reset: now + 60_000 };
    if (now > item.reset) {
      item.count = 0;
      item.reset = now + 60_000;
    }
    item.count++;
    hits.set(ip, item);
    if (item.count > max) return bad(res, 429, 'Cok fazla istek, biraz bekleyin');
    next();
  };
}

const authLimit = makeLimit(20); // giris / kayit (deneme saldirisina karsi)
const rateLimit = makeLimit(300); // skor, profil, sync

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function requireAdmin(req, res, next) {
  if (!ADMIN_KEY) {
    return bad(res, 503, 'Yonetim kapali: ADMIN_KEY ortam degiskeni tanimli degil');
  }
  const header = req.get('x-admin-key') || (req.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!header || !safeEqual(header, ADMIN_KEY)) {
    return bad(res, 401, 'Yetkisiz: X-Admin-Key hatali veya eksik');
  }
  next();
}

const publicUser = (u) => (u ? { user_id: u.id, username: u.username, points: Number(u.points || 0) } : null);

/* ------------------------------ saglik ------------------------------ */

app.get('/health', asyncRoute(async (req, res) => {
  const h = await db.health();
  res.json({
    status: h.ok ? 'ok' : 'degraded',
    storage: db.kind,
    admin_enabled: Boolean(ADMIN_KEY),
    time: new Date().toISOString(),
    detail: h.detail,
  });
}));

/* --------------------------- hesap islemleri ------------------------ */

app.post('/register', authLimit, asyncRoute(async (req, res) => {
  const { username, password } = req.body || {};
  const err = validateCredentials(username, password);
  if (err) return bad(res, 400, err);

  const existing = await db.findUserByUsername(username);
  if (existing) return bad(res, 409, 'Bu kullanici adi zaten alinmis');

  const hash = await bcrypt.hash(password, 10);
  try {
    const created = await db.createUser({ username, passwordHash: hash });
    res.status(201).json({ success: true, user_id: created.id, username: created.username, points: 0 });
  } catch (e) {
    if (e.code === 'USER_EXISTS') return bad(res, 409, 'Bu kullanici adi zaten alinmis');
    throw e;
  }
}));

app.post('/login', authLimit, asyncRoute(async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return bad(res, 400, 'username ve password gerekli');

  const user = await db.findUserByUsername(username);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');

  const ok = await bcrypt.compare(String(password), String(user.password || ''));
  if (!ok) return bad(res, 401, 'Sifre yanlis');

  res.json({
    success: true,
    user_id: user.id,
    username: user.username,
    points: Number(user.points || 0),
  });
}));

/* ------------------------- mac sonu / puan -------------------------- */

// Eski istemci: POST /score { user_id, score, song_name }
// Yeni istemci:  POST /score { user_id, points, match_id, song_name }
// `points` verilmezse `score` puan olarak kullanilir (eski oyun build'i boyle gonderiyor).
app.post('/score', rateLimit, asyncRoute(async (req, res) => {
  const body = req.body || {};
  const userId = Number(body.user_id);
  if (!userId) return bad(res, 400, 'user_id gerekli');

  const rawScore = body.score != null ? Number(body.score) : null;
  let points = body.points != null ? Number(body.points) : rawScore;
  if (body.add_points === false) points = 0;
  if (points == null || Number.isNaN(points)) points = 0;
  if (points < 0) points = 0;
  if (points > 10000) return bad(res, 400, 'points cok buyuk');

  const result = await db.recordMatch({
    userId,
    points,
    score: rawScore != null && rawScore >= 0 ? rawScore : (points || 0),
    songName: body.song_name || null,
    matchId: body.match_id || null,
  });

  if (!result) return bad(res, 404, 'Kullanici bulunamadi');
  res.json({ success: true, points: result.points, added: result.duplicate ? 0 : points, duplicate: Boolean(result.duplicate) });
}));

/* ---------------------------- liderlik ------------------------------ */

app.get('/leaderboard', asyncRoute(async (req, res) => {
  const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 50));

  if (req.query.raw === '1') {
    // Eski istemci formati: { leaderboard: [{score, song_name, created_at, users:{username}}] }
    return res.json({ leaderboard: await db.rawLeaderboard(limit) });
  }

  res.json({ leaderboard: await db.leaderboard(limit), updated_at: new Date().toISOString() });
}));

/* --------------------- mac kaydi arsivi (oyun) --------------------- */

// Oyun, mac kaydini normalde dogrudan Supabase'e yazar. Tablo yoksa
// (PGRST205/404) buraya duser; boylece ekranda "HATA 404" kalmaz.
// Hem Supabase hem sunucu icin ayni govde kullanilir.
app.post(['/matches', '/match-records'], rateLimit, asyncRoute(async (req, res) => {
  const body = req.body || {};
  const matchId = String(body.match_id || body.matchId || '').trim();
  if (!matchId) return bad(res, 400, 'match_id gerekli');

  const result = await db.saveMatchRecord({
    matchId,
    username: body.username || null,
    userId: body.user_id != null ? body.user_id : body.userId,
    song: body.song || null,
    difficulty: body.difficulty || null,
    score: body.score,
    maxCombo: body.max_combo != null ? body.max_combo : body.maxCombo,
    misses: body.misses,
    accuracy: body.accuracy,
    points: body.points,
    botplay: body.botplay,
    infiniteMode: body.infinite_mode != null ? body.infinite_mode : body.infiniteMode,
    practiceMode: body.practice_mode != null ? body.practice_mode : body.practiceMode,
    storyMode: body.story_mode != null ? body.story_mode : body.storyMode,
    playedAt: body.played_at || body.playedAt || null,
  });

  res.json({
    success: true,
    match_id: matchId,
    archived: Boolean(result && result.archived),
    duplicate: Boolean(result && result.duplicate),
    missing_table: Boolean(result && result.missingTable),
    storage: db.kind,
  });
}));

app.get('/matches', rateLimit, asyncRoute(async (req, res) => {
  const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 50));
  res.json({ matches: await db.listMatchRecords(limit) });
}));

/* ------------------------- oyuncu: puan yenileme -------------------- */

// Oyunun "PUANI YENILE" dugmesi icin. Sadece okuma yapar, sifre/hash donmez.
// Kullanim: GET /profile/12   veya   GET /profile?username=baki
app.get('/profile/:id', rateLimit, asyncRoute(async (req, res) => {
  const user = await db.getUser(req.params.id);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');

  const stats = await db.userStats(user.id);
  res.json({
    success: true,
    user_id: user.id,
    username: user.username,
    points: Number(user.points || 0),
    songs_played: stats.songs_played || 0,
    best_score: stats.best_score || 0,
    last_played: stats.last_played || null,
  });
}));

// Kullanici adiyla arama: istemci eski bir user_id tasiyorsa (sunucu degisti)
// dogru kimligi buradan bulur.
app.get('/profile', rateLimit, asyncRoute(async (req, res) => {
  const username = String(req.query.username || '').trim();
  if (!USERNAME_RE.test(username)) return bad(res, 400, 'username gerekli');

  const user = await db.findUserByUsername(username);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');

  const stats = await db.userStats(user.id);
  res.json({
    success: true,
    user_id: user.id,
    username: user.username,
    points: Number(user.points || 0),
    songs_played: stats.songs_played || 0,
    best_score: stats.best_score || 0,
    last_played: stats.last_played || null,
  });
}));

// Yerel puan sunucudan yuksek kaldiysa (istekler ulasmadiysa) aradaki farki
// tasir. Sadece YUKARI yazar; puan asla azalmaz.
// Not: bu oyun istemci tabanli puan kullaniyor, /score de istemciden gelen
// puan degerini kabul ediyor; bu uc yeni bir yetki genisligi getirmiyor.
app.post('/sync', rateLimit, asyncRoute(async (req, res) => {
  const body = req.body || {};
  const user = await db.getUser(body.user_id);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');

  const points = Number(body.points);
  if (!Number.isFinite(points) || points < 0) return bad(res, 400, 'points gerekli');
  if (points > 1000000) return bad(res, 400, 'points cok buyuk');

  const before = Number(user.points || 0);
  if (points <= before) {
    return res.json({ success: true, points: before, added: 0, user_id: user.id });
  }

  const next = await db.addPoints(user.id, points - before);
  if (next == null) return bad(res, 404, 'Kullanici bulunamadi');

  res.json({ success: true, points: next, added: points - before, user_id: user.id });
}));

/* ------------------------- yonetim: kullanicilar -------------------- */

app.get('/users', requireAdmin, asyncRoute(async (req, res) => {
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));
  const users = await db.listUsers(String(req.query.q || '').trim(), limit);
  res.json({ users: users.map(publicUser) });
}));

app.get('/users/:id', requireAdmin, asyncRoute(async (req, res) => {
  const user = await db.getUser(req.params.id);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');
  const stats = await db.userStats(req.params.id);
  res.json({ user: { ...publicUser(user), created_at: user.created_at, ...stats } });
}));

app.delete('/users/:id', requireAdmin, asyncRoute(async (req, res) => {
  const user = await db.getUser(req.params.id);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');

  const ok = await db.deleteUser(user.id);
  if (!ok) return bad(res, 404, 'Kullanici bulunamadi');

  await db.logAction({
    action: 'delete_user',
    target_user_id: user.id,
    target_username: user.username,
    amount: null,
    reason: String((req.body && req.body.reason) || 'panelden silindi'),
    admin_ip: req.ip,
  });

  res.json({ success: true, deleted_user_id: user.id, username: user.username });
}));

/* --------------------------- yonetim: puan -------------------------- */

async function applyPoints(req, res, userId) {
  const body = req.body || {};
  const amount = Number(body.amount);
  if (!Number.isFinite(amount) || amount === 0) return bad(res, 400, 'amount sifirdan farkli bir sayi olmali');
  if (Math.abs(amount) > 100000) return bad(res, 400, 'amount cok buyuk');

  const user = await db.getUser(userId);
  if (!user) return bad(res, 404, 'Kullanici bulunamadi');

  const next = await db.addPoints(user.id, amount);
  if (next == null) return bad(res, 404, 'Kullanici bulunamadi');

  await db.logAction({
    action: amount > 0 ? 'add_points' : 'remove_points',
    target_user_id: user.id,
    target_username: user.username,
    amount,
    reason: String(body.reason || '').slice(0, 200) || null,
    admin_ip: req.ip,
  });

  res.json({
    success: true,
    user_id: user.id,
    username: user.username,
    points: next,
    change: amount,
  });
}

app.post('/points', requireAdmin, asyncRoute((req, res) => applyPoints(req, res, (req.body || {}).user_id)));
app.post('/users/:id/points', requireAdmin, asyncRoute((req, res) => applyPoints(req, res, req.params.id)));

/* --------------------------- yonetim: loglar ------------------------ */

app.get('/admin/logs', requireAdmin, asyncRoute(async (req, res) => {
  const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 50));
  res.json({ logs: await db.listLogs(limit) });
}));

app.get('/admin/summary', requireAdmin, asyncRoute(async (req, res) => {
  const users = await db.listUsers('', 100);
  const board = await db.leaderboard(1000);
  const totalPoints = board.reduce((sum, r) => sum + Number(r.points || 0), 0);
  res.json({
    success: true,
    storage: db.kind,
    users: users.length,
    total_points: totalPoints,
    top_user: board[0] || null,
  });
}));

/* ------------------------- statik dosyalar --------------------------- */
// DIKKAT: API rotalarindan SONRA gelmeli, yoksa /leaderboard istegi
// leaderboard.html dosyasini dondurur.
// /leaderboard ve /users API'dir; sayfalar /board ve /panel adreslerinde.
app.get(['/board', '/panel'], (req, res) => {
  res.sendFile(path.join(__dirname, 'web', req.path === '/board' ? 'leaderboard.html' : 'admin.html'));
});
app.use(express.static(path.join(__dirname, 'web'), { extensions: ['html'], index: ['index.html'] }));

/* ----------------------------- hata yakalama ------------------------ */

app.use((req, res) => bad(res, 404, 'Endpoint bulunamadi: ' + req.method + ' ' + req.path));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[server] hata:', err);
  const message = err && err.message ? err.message : 'Sunucu hatasi';
  bad(res, 500, message);
});

db.init()
  .catch((e) => console.warn('[db] init uyarisi:', e.message))
  .finally(() => {
    app.listen(PORT, HOST, () => {
      console.log(`dark-engine-service http://${HOST}:${PORT} (storage: ${db.kind})`);
      if (isMemory) {
        console.log('UYARI: Supabase anahtarlari yok, DEMO (memory) modunda calisiyor.');
        console.log(`Yonetim paneli icin ADMIN_KEY: ${ADMIN_KEY}`);
      } else if (!process.env.ADMIN_KEY) {
        console.log('UYARI: ADMIN_KEY tanimli degil, yonetim endpointleri kapali.');
      }
    });
  });

module.exports = app;
