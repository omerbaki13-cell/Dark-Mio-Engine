'use strict';

/**
 * Veri katmani.
 *
 * Iki uygulamasi var:
 *   - supabase : SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY tanimliysa kullanilir (production)
 *   - memory   : anahtarlar yoksa devreye girer (yerel gelistirme / demo)
 *
 * Arayuz (hepsi async):
 *   init(), health(), findUserByUsername(), createUser(), getUser(),
 *   listUsers(), deleteUser(), addPoints(), recordMatch(), leaderboard(),
 *   rawLeaderboard(), userStats(), logAction(), listLogs()
 */

/* ------------------------------------------------------------------ */
/* MEMORY (demo / test)                                               */
/* ------------------------------------------------------------------ */

function createMemoryDb() {
  const now = () => new Date().toISOString();
  const users = new Map(); // id -> {id, username, password, points, created_at}
  const scores = []; // {id, user_id, score, song_name, created_at}
  const matches = new Map(); // match_id -> {user_id, points}
  const logs = []; // admin islem gecmisi
  let userSeq = 1;
  let scoreSeq = 1;
  let logSeq = 1;

  // Demo kullanicilari (hepsinin sifresi: 1234)
  const seed = [
    ['baki', 40],
    ['mio', 25],
    ['player1', 12],
    ['test', 3],
  ];
  for (const [name, pts] of seed) {
    const id = userSeq++;
    users.set(id, {
      id,
      username: name,
      password: '$2a$10$oUq4zloWlPf8IeO2Oe.z4.bJXc74dhnL/bVb0IRv.bRKdm7yH347K',
      points: pts,
      created_at: now(),
    });
  }

  const findByName = (username) =>
    [...users.values()].find(
      (u) => String(u.username).toLowerCase() === String(username).toLowerCase()
    );

  return {
    kind: 'memory',
    async init() {},

    async health() {
      return { ok: true, detail: { users: users.size, scores: scores.length } };
    },

    async findUserByUsername(username) {
      const u = findByName(username);
      return u ? { ...u } : null;
    },

    async createUser({ username, passwordHash }) {
      if (findByName(username)) {
        const err = new Error('Bu kullanici adi zaten alinmis');
        err.code = 'USER_EXISTS';
        throw err;
      }
      const id = userSeq++;
      const user = { id, username, password: passwordHash, points: 0, created_at: now() };
      users.set(id, user);
      return { id, username, points: user.points };
    },

    async getUser(id) {
      const u = users.get(Number(id));
      return u ? { ...u } : null;
    },

    async listUsers(q, limit = 20) {
      const needle = String(q || '').toLowerCase();
      return [...users.values()]
        .filter((u) => !needle || String(u.username).toLowerCase().includes(needle))
        .sort((a, b) => b.points - a.points)
        .slice(0, limit)
        .map((u) => ({ id: u.id, username: u.username, points: u.points, created_at: u.created_at }));
    },

    async deleteUser(id) {
      const uid = Number(id);
      if (!users.has(uid)) return false;
      users.delete(uid);
      for (let i = scores.length - 1; i >= 0; i--) if (scores[i].user_id === uid) scores.splice(i, 1);
      for (const [key, m] of matches) if (m.user_id === uid) matches.delete(key);
      return true;
    },

    async addPoints(id, amount) {
      const uid = Number(id);
      const u = users.get(uid);
      if (!u) return null;
      u.points = Math.max(0, Number(u.points || 0) + Number(amount || 0));
      return u.points;
    },

    async recordMatch({ userId, points, score, songName, matchId }) {
      const uid = Number(userId);
      if (!users.has(uid)) return null;

      if (matchId && matches.has(matchId)) return { duplicate: true, points: users.get(uid).points };
      if (matchId) matches.set(matchId, { user_id: uid, points: Number(points || 0) });

      if (score != null) {
        scores.push({
          id: scoreSeq++,
          user_id: uid,
          score: Number(score),
          song_name: songName || null,
          created_at: now(),
        });
      }
      const u = users.get(uid);
      if (Number(points || 0) > 0) u.points = Math.max(0, u.points + Number(points));
      return { duplicate: false, points: u.points };
    },

    async userStats(id) {
      const uid = Number(id);
      const mine = scores.filter((s) => s.user_id === uid);
      return {
        songs_played: mine.length,
        best_score: mine.length ? Math.max(...mine.map((s) => s.score)) : 0,
        last_played: mine.length ? mine[mine.length - 1].created_at : null,
      };
    },

    async leaderboard(limit = 50) {
      const rows = [];
      for (const u of users.values()) {
        const mine = scores.filter((s) => s.user_id === u.id);
        rows.push({
          user_id: u.id,
          username: u.username,
          points: u.points,
          songs_played: mine.length,
          best_score: mine.length ? Math.max(...mine.map((s) => s.score)) : 0,
          last_played: mine.length ? mine[mine.length - 1].created_at : null,
        });
      }
      rows.sort((a, b) => b.points - a.points || String(a.username).localeCompare(String(b.username)));
      return rows.slice(0, limit).map((r, i) => ({ rank: i + 1, ...r }));
    },

    async rawLeaderboard(limit = 50) {
      return scores
        .slice()
        .sort((a, b) => b.score - a.score)
        .slice(0, limit)
        .map((s) => ({
          score: s.score,
          song_name: s.song_name,
          created_at: s.created_at,
          users: { username: (users.get(s.user_id) || {}).username || 'bilinmeyen' },
        }));
    },

    async logAction(entry) {
      logs.unshift({ id: logSeq++, created_at: now(), ...entry });
      while (logs.length > 500) logs.pop();
    },

    async listLogs(limit = 50) {
      return logs.slice(0, limit);
    },
  };
}

/* ------------------------------------------------------------------ */
/* SUPABASE                                                           */
/* ------------------------------------------------------------------ */

function createSupabaseDb(url, serviceKey) {
  const { createClient } = require('@supabase/supabase-js');
  const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });

  let pointsColumn = true; // users.points var mi? (migration calistirilmadiysa false olur)

  const isMissingColumn = (error) => {
    if (!error) return false;
    const msg = String(error.message || '');
    return error.code === '42703' || /column .* does not exist/i.test(msg);
  };

  const mapUser = (u) => ({
    id: u.id,
    username: u.username,
    points: pointsColumn ? Number(u.points || 0) : 0,
    created_at: u.created_at,
  });

  async function selectUsers(columns, apply) {
    let query = supabase.from('users').select(columns);
    if (apply) query = apply(query);
    const res = await query;
    if (res.error && isMissingColumn(res.error) && pointsColumn) {
      // points kolonu yok -> onsuz tekrar dene
      pointsColumn = false;
      return selectUsers(columns.replace(/,\s*points/, ''), apply);
    }
    return res;
  }

  return {
    kind: 'supabase',
    async init() {
      const res = await selectUsers('id, username, points, created_at', (q) => q.limit(1));
      if (res.error && !isMissingColumn(res.error)) {
        // tablo hic yok olabilir; loglayip devam ediyoruz (health gosterecek)
        console.warn('[db] Supabase uyarisi:', res.error.message);
      }
    },

    async health() {
      const res = await selectUsers('id, username, points', (q) => q.limit(1));
      return {
        ok: !res.error,
        detail: {
          points_column: pointsColumn,
          error: res.error ? res.error.message : null,
        },
      };
    },

    async findUserByUsername(username) {
      const res = await selectUsers('*', (q) => q.eq('username', username).limit(1));
      if (res.error) throw new Error(res.error.message);
      const row = (res.data || [])[0];
      return row ? { ...row, points: pointsColumn ? Number(row.points || 0) : 0 } : null;
    },

    async createUser({ username, passwordHash }) {
      const payload = { username, password: passwordHash };
      if (pointsColumn) payload.points = 0;
      const res = await supabase.from('users').insert(payload).select('id, username').maybeSingle();
      if (res.error) {
        if (res.error.code === '23505') {
          const err = new Error('Bu kullanici adi zaten alinmis');
          err.code = 'USER_EXISTS';
          throw err;
        }
        throw new Error(res.error.message);
      }
      return res.data;
    },

    async getUser(id) {
      const res = await selectUsers('*', (q) => q.eq('id', Number(id)).limit(1));
      if (res.error) throw new Error(res.error.message);
      const row = (res.data || [])[0];
      return row ? mapUser(row) : null;
    },

    async listUsers(q, limit = 20) {
      const apply = (query) => {
        let out = query.order(pointsColumn ? 'points' : 'username', { ascending: false }).limit(limit);
        if (q) out = out.ilike('username', `%${q}%`);
        return out;
      };
      const res = await selectUsers('id, username, points, created_at', apply);
      if (res.error) throw new Error(res.error.message);
      return (res.data || []).map(mapUser);
    },

    async deleteUser(id) {
      const uid = Number(id);
      await supabase.from('scores').delete().eq('user_id', uid);
      await supabase.from('matches').delete().eq('user_id', uid);
      const res = await supabase.from('users').delete().eq('id', uid);
      if (res.error) throw new Error(res.error.message);
      return true;
    },

    async addPoints(id, amount) {
      const uid = Number(id);
      if (!pointsColumn) {
        throw new Error('users.points kolonu yok. supabase/migration.sql dosyasini calistir.');
      }
      const cur = await this.getUser(uid);
      if (!cur) return null;
      const next = Math.max(0, Number(cur.points || 0) + Number(amount || 0));
      const res = await supabase.from('users').update({ points: next }).eq('id', uid);
      if (res.error) throw new Error(res.error.message);
      return next;
    },

    async recordMatch({ userId, points, score, songName, matchId }) {
      const uid = Number(userId);
      const user = await this.getUser(uid);
      if (!user) return null;

      if (matchId) {
        const ins = await supabase
          .from('matches')
          .insert({ match_id: matchId, user_id: uid, points: Number(points || 0) })
          .select('match_id');
        if (ins.error) {
          if (ins.error.code === '23505') return { duplicate: true, points: user.points };
          // matches tablosu yoksa akisi bozmayalim
          if (!/relation .* does not exist/i.test(ins.error.message)) {
            console.warn('[db] match kaydi:', ins.error.message);
          }
        }
      }

      if (score != null) {
        const sres = await supabase
          .from('scores')
          .insert({ user_id: uid, score: Number(score), song_name: songName || null });
        if (sres.error) console.warn('[db] score kaydi:', sres.error.message);
      }

      let current = user.points;
      if (Number(points || 0) > 0) {
        current = await this.addPoints(uid, Number(points));
      }
      return { duplicate: false, points: current };
    },

    async userStats(id) {
      const uid = Number(id);
      const res = await supabase
        .from('scores')
        .select('score, created_at')
        .eq('user_id', uid)
        .order('created_at', { ascending: false })
        .limit(500);
      if (res.error) return { songs_played: 0, best_score: 0, last_played: null };
      const rows = res.data || [];
      return {
        songs_played: rows.length,
        best_score: rows.length ? Math.max(...rows.map((r) => Number(r.score) || 0)) : 0,
        last_played: rows.length ? rows[0].created_at : null,
      };
    },

    async leaderboard(limit = 50) {
      const usersRes = await selectUsers('id, username, points, created_at', (q) => q.limit(1000));
      if (usersRes.error) throw new Error(usersRes.error.message);

      // Skorlari tek seferde cekip JS'te topluyoruz (RPC gerektirmez)
      const scoresRes = await supabase
        .from('scores')
        .select('user_id, score, created_at')
        .order('created_at', { ascending: false })
        .limit(5000);
      const scores = scoresRes.error ? [] : scoresRes.data || [];

      const agg = new Map(); // user_id -> {songs_played, best_score, last_played}
      for (const s of scores) {
        const key = Number(s.user_id);
        const cur = agg.get(key) || { songs_played: 0, best_score: 0, last_played: null };
        cur.songs_played += 1;
        cur.best_score = Math.max(cur.best_score, Number(s.score) || 0);
        if (!cur.last_played) cur.last_played = s.created_at;
        agg.set(key, cur);
      }

      const rows = (usersRes.data || []).map((u) => {
        const a = agg.get(Number(u.id)) || { songs_played: 0, best_score: 0, last_played: null };
        return {
          user_id: u.id,
          username: u.username,
          points: pointsColumn ? Number(u.points || 0) : 0,
          songs_played: a.songs_played,
          best_score: a.best_score,
          last_played: a.last_played,
        };
      });

      rows.sort((a, b) => b.points - a.points || String(a.username).localeCompare(String(b.username)));
      return rows.slice(0, limit).map((r, i) => ({ rank: i + 1, ...r }));
    },

    async rawLeaderboard(limit = 50) {
      const res = await supabase
        .from('scores')
        .select('score, song_name, created_at, users(username)')
        .order('score', { ascending: false })
        .limit(limit);
      if (res.error) throw new Error(res.error.message);
      return res.data || [];
    },

    async logAction(entry) {
      const res = await supabase.from('admin_logs').insert(entry);
      if (res.error && !/relation .* does not exist/i.test(res.error.message)) {
        console.warn('[db] admin_logs:', res.error.message);
      }
    },

    async listLogs(limit = 50) {
      const res = await supabase
        .from('admin_logs')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(limit);
      if (res.error) return [];
      return res.data || [];
    },
  };
}

function createDb() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (url && key) return createSupabaseDb(url, key);
  return createMemoryDb();
}

module.exports = { createDb, createMemoryDb, createSupabaseDb };
