package backend;

import flixel.util.FlxSave;
import haxe.Http;
import haxe.Json;
import sys.thread.Thread;

/**
 * MAÇ KAYIT SİSTEMİ
 * ------------------------------------------------------------------
 * - Bir maç bitince sonucu kayıt altına alınır.
 * - Kayıtlar iki yere gider:
 *     1) RENDER  -> oyun klasörüne yazılan `render-ingame.json` dosyası
 *        (oyun içi render / sonuç dosyası, her maçta güncellenir)
 *     2) SUPABASE -> REST API üzerinden `match_records` tablosu
 * - Supabase ayarları boş bırakılırsa kayıtlar kaybolmaz, "bekleyen"
 *   kuyruğunda tutulur ve ayarlar girildiğinde otomatik gönderilir.
 * - Puan kuralı: aynı şarkı + zorluk kombinasyonundan SADECE 1 kez puan
 *   alınır. Puan alınmışsa o maçtan tekrar puan verilmez.
 * ------------------------------------------------------------------
 */
class MatchRecords
{
	// ---------------- SUPABASE AYARLARI ----------------
	// Örnek: https://abcdefghijklmno.supabase.co
	public static var SUPABASE_URL:String = 'https://YOUR_PROJECT.supabase.co';
	// Supabase > Project Settings > API > anon public key
	public static var SUPABASE_ANON_KEY:String = '';
	// Tablo adı (SQL için README/docs'a bak)
	public static var SUPABASE_TABLE:String = 'match_records';

	// true  -> aynı şarkı + zorluk için ömür boyu tek puan
	// false -> her oynayış ayrı maç sayılır (her seferinde puan alınabilir)
	public static var oncePerSong:Bool = true;

	public static var RENDER_FILE_NAME:String = 'render-ingame.json';
	public static var MAX_PENDING:Int = 50;

	static var _save:FlxSave = null;
	static var _loaded:Bool = false;

	static var _matches:Array<Dynamic> = []; // tamamlanmış maç kayıtları
	static var _claimed:Array<String> = []; // puanı alınmış maç anahtarları
	static var _pending:Array<Dynamic> = []; // Supabase'e gönderilecek kayıtlar
	static var _threadDone:Array<String> = []; // arka plandan dönen başarılı id'ler
	static var _sending:Bool = false;

	// ------------------------------------------------------------------
	// Kayıt (save) işlemleri
	// ------------------------------------------------------------------
	static function ensure():Void
	{
		if(_loaded) return;
		_loaded = true;

		_save = new FlxSave();
		_save.bind('mio_matches', 'MioEngine');

		var d:Dynamic = _save.data;
		if(d.matches != null) _matches = d.matches;
		if(d.claimed != null) _claimed = d.claimed;
		if(d.pending != null) _pending = d.pending;
		if(d.threadDone != null && d.threadDone.length > 0)
		{
			// Oyun kapanmadan önce gönderilmiş ama işlenememiş kayıtlar
			var savedDone:Array<Dynamic> = d.threadDone;
			for(id in savedDone) _threadDone.push(id);
			d.threadDone = null;
		}

		loadConfigFromFile();
	}

	/**
	 * Supabase bilgileri koda gömülü olmak zorunda değil:
	 * oyun klasöründeki `mods/supabase.json` (veya çalışma dizinindeki
	 * `supabase.json`) dosyasından okunur.
	 *
	 * {
	 *   "url": "https://xxxx.supabase.co",
	 *   "anon_key": "eyJhbGciOi...",
	 *   "table": "match_records"
	 * }
	 */
	static function loadConfigFromFile():Void
	{
		#if sys
		var files:Array<String> = [Paths.mods('supabase.json'), 'supabase.json'];
		for(file in files)
		{
			try
			{
				if(file == null || !sys.FileSystem.exists(file)) continue;
				var raw:String = sys.io.File.getContent(file);
				if(raw == null || raw.length < 2) continue;
				var cfg:Dynamic = Json.parse(raw);
				if(cfg == null) continue;

				if(cfg.url != null) SUPABASE_URL = Std.string(cfg.url);
				if(cfg.anon_key != null) SUPABASE_ANON_KEY = Std.string(cfg.anon_key);
				if(cfg.table != null) SUPABASE_TABLE = Std.string(cfg.table);
				if(cfg.once_per_song != null) oncePerSong = cfg.once_per_song == true;
				return;
			}
			catch(e:Dynamic)
			{
				trace('MatchRecords: supabase.json okunamadı -> ' + e);
			}
		}
		#end
	}

	public static function flush():Void
	{
		ensure();
		var d:Dynamic = _save.data;
		d.matches = _matches;
		d.claimed = _claimed;
		d.pending = _pending;
		d.threadDone = _threadDone;
		_save.flush();
	}

	// ------------------------------------------------------------------
	// Maç anahtarı / puan hakkı
	// ------------------------------------------------------------------
	public static function matchKey(song:String, difficulty:String):String
	{
		var songKey:String = Paths.formatToSongPath(song == null ? 'unknown' : song);
		var diffKey:String = Paths.formatToSongPath(difficulty == null ? 'normal' : difficulty);
		return songKey + '_' + diffKey;
	}

	public static function makeMatchId(song:String, difficulty:String):String
	{
		var key:String = matchKey(song, difficulty);
		if(oncePerSong) return key;
		return key + '_' + Date.now().getTime();
	}

	/** Bu maçtan daha önce puan alınmış mı? */
	public static function hasClaimed(matchId:String):Bool
	{
		ensure();
		if(matchId == null) return false;
		return _claimed.contains(matchId);
	}

	/** Puan verildiği anda çağrılır, aynı maçtan tekrar puan verilmesini engeller. */
	public static function markClaimed(matchId:String):Void
	{
		ensure();
		if(matchId == null || _claimed.contains(matchId)) return;
		_claimed.push(matchId);
		flush();
	}

	/** Puan alınabilir mi? Botplay / Sonsuz Mod / Antrenman / Chart modu kapalı olmalı. */
	public static function isEligible(botplay:Bool, infiniteMode:Bool, practice:Bool, charting:Bool):Bool
	{
		return !botplay && !infiniteMode && !practice && !charting;
	}

	// ------------------------------------------------------------------
	// Maç bitince çağrılır
	// ------------------------------------------------------------------
	public static function completeMatch(data:Dynamic):Void
	{
		ensure();
		if(data == null) return;

		var record:Dynamic = data;
		record.played_at = Date.now().toString();
		record.synced = false;

		// Aynı maç zaten kayıtlıysa üzerine yaz (mükerrer kayıt olmasın)
		var replaced:Bool = false;
		for (i in 0..._matches.length)
		{
			if(_matches[i] != null && _matches[i].match_id == record.match_id)
			{
				record.synced = _matches[i].synced == true;
				_matches[i] = record;
				replaced = true;
				break;
			}
		}
		if(!replaced) _matches.push(record);

		// Maç kayıtları Supabase kuyruğuna eklenir
		// (botplay/sonsuz mod maçları da gönderilir, "eligible" alanı ile işaretlenir)
		var alreadyQueued:Bool = false;
		for(rec in _pending)
			if(rec != null && rec.match_id == record.match_id) alreadyQueued = true;

		if(!alreadyQueued)
		{
			_pending.push(record);
			while(_pending.length > MAX_PENDING) _pending.shift();
		}

		flush();
		writeRenderFile();
		submitPending();
	}

	// ------------------------------------------------------------------
	// RENDER DOSYASI (oyun içi render)
	// ------------------------------------------------------------------
	public static function renderFilePath():String
	{
		var dir:String = null;
		#if sys
		dir = StorageUtil.getStorageDirectory();
		#end

		if(dir == null) dir = '';
		if(dir.length > 0 && dir.charAt(dir.length - 1) != '/') dir += '/';
		return dir + RENDER_FILE_NAME;
	}

	public static function getRenderData():Dynamic
	{
		ensure();
		return {
			engine: 'Dark Mio Engine',
			render_file: RENDER_FILE_NAME,
			updated_at: Date.now().toString(),
			total_matches: _matches.length,
			total_pending_sync: _pending.length,
			matches: _matches
		};
	}

	public static function writeRenderFile():Void
	{
		#if sys
		try
		{
			var content:String = Json.stringify(getRenderData(), null, '\t');
			sys.io.File.saveContent(renderFilePath(), content);
		}
		catch(e:Dynamic)
		{
			trace('MatchRecords: render dosyası yazılamadı -> ' + e);
		}
		#end
	}

	// ------------------------------------------------------------------
	// SUPABASE GÖNDERİMİ
	// ------------------------------------------------------------------
	public static function isSupabaseConfigured():Bool
	{
		if(SUPABASE_URL == null || SUPABASE_ANON_KEY == null) return false;
		if(SUPABASE_URL.length < 8 || SUPABASE_ANON_KEY.length < 8) return false;
		if(SUPABASE_URL.indexOf('YOUR_PROJECT') != -1) return false;
		return true;
	}

	public static function pendingCount():Int
	{
		ensure();
		return _pending.length;
	}

	/** Bekleyen kayıtları arka planda gönderir (oyunu dondurmaz). */
	public static function submitPending():Void
	{
		ensure();
		if(_sending || _pending.length < 1) return;
		if(!isSupabaseConfigured()) return;

		_sending = true;
		var queue:Array<Dynamic> = _pending.copy();

		Thread.create(function() {
			for(rec in queue)
			{
				if(rec == null || rec.match_id == null) continue;
				var ok:Bool = false;
				try
				{
					ok = postRecord(rec);
				}
				catch(e:Dynamic)
				{
					ok = false;
				}
				if(ok) _threadDone.push(rec.match_id);
			}
			_sending = false;
		});
	}

	static function toSupabasePayload(record:Dynamic):Dynamic
	{
		return {
			match_id: record.match_id,
			username: record.username,
			user_id: record.user_id,
			song: record.song,
			difficulty: record.difficulty,
			score: record.score,
			max_combo: record.max_combo,
			misses: record.misses,
			accuracy: record.accuracy,
			points: record.points,
			botplay: record.botplay == true,
			infinite_mode: record.infinite_mode == true,
			practice_mode: record.practice_mode == true,
			story_mode: record.story_mode == true,
			played_at: record.played_at
		};
	}

	static function postRecord(record:Dynamic):Bool
	{
		var statusCode:Int = 0;
		var failed:Bool = false;

		var http:Http = new Http(SUPABASE_URL + '/rest/v1/' + SUPABASE_TABLE);
		http.cnxTimeout = 15;
		http.setHeader('apikey', SUPABASE_ANON_KEY);
		http.setHeader('Authorization', 'Bearer ' + SUPABASE_ANON_KEY);
		http.setHeader('Content-Type', 'application/json');
		http.setHeader('Prefer', 'return=minimal');
		http.setPostData(Json.stringify(toSupabasePayload(record)));

		http.onStatus = function(st:Int) statusCode = st;
		http.onError = function(e:String) failed = true;
		http.onData = function(d:String) {};

		try
		{
			http.request(true);
		}
		catch(e:Dynamic)
		{
			failed = true;
		}

		if(failed) return false;
		// 409 = match_id zaten var, sorun değil
		return statusCode == 409 || (statusCode >= 200 && statusCode < 300);
	}

	/** Her frame çağrılabilir; gönderim sonuçlarını işler ve kuyruğu dener. */
	public static function tick():Void
	{
		ensure();

		if(_threadDone.length > 0)
		{
			var done:Array<String> = _threadDone.copy();
			_threadDone = [];

			var stillPending:Array<Dynamic> = [];
			for(rec in _pending)
			{
				if(rec != null && done.contains(rec.match_id))
				{
					rec.synced = true;
					for(m in _matches)
						if(m != null && m.match_id == rec.match_id) m.synced = true;
				}
				else stillPending.push(rec);
			}
			_pending = stillPending;

			flush();
			writeRenderFile();
		}

		submitPending();
	}

	public static function getMatches():Array<Dynamic>
	{
		ensure();
		return _matches;
	}

	/** Test / sıfırlama için */
	public static function resetAll():Void
	{
		ensure();
		_matches = [];
		_claimed = [];
		_pending = [];
		_threadDone = [];
		flush();
		writeRenderFile();
	}
}
