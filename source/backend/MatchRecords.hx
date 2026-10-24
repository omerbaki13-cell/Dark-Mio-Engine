package backend;

import flixel.util.FlxSave;
import haxe.Http;
import haxe.Json;
import haxe.io.Path as HxPath;
import sys.thread.Thread;

/**
 * MAÇ KAYIT SİSTEMİ  (v2)
 * ------------------------------------------------------------------
 * Düzeltilen hatalar:
 *  1) URL hatası: supabase.json içine "https://xxx.supabase.co/rest/v1/"
 *     yazılınca kod tekrar "/rest/v1/" ekliyordu ->
 *     ".../rest/v1//rest/v1/match_records" => 404 => kayıt hep "BEKLİYOR".
 *     Artık URL normalize ediliyor (sondaki /, /rest/v1, /rest/v1/ kırpılır).
 *  2) Ayar dosyası artık birden fazla yerde aranıyor:
 *     supabase.json, mods/supabase.json, example_mods/supabase.json
 *     ve mods/ + example_mods/ alt klasörleri.
 *  3) Her denemenin HTTP kodu + hata mesajı kaydedilip ekranda gösteriliyor.
 *  4) Aynı kayıt tekrar gönderilirken çakışma hatası vermiyor
 *     (on_conflict=match_id + resolution=merge-duplicates).
 *  5) Kuyruk her frame denenmiyor; 8 saniyede bir yeniden deneniyor.
 *  6) Puan kaydı: kazanılan toplam puan ayrıca tutuluyor (ledger),
 *     UserSession kaydı bozulsa bile puan kaybolmuyor.
 * ------------------------------------------------------------------
 */
class MatchRecords
{
	// ---------------- SUPABASE AYARLARI ----------------
	public static var SUPABASE_URL:String = 'https://YOUR_PROJECT.supabase.co';
	public static var SUPABASE_ANON_KEY:String = '';
	public static var SUPABASE_TABLE:String = 'match_records';

	// true  -> aynı şarkı + zorluk için ömür boyu tek puan
	// false -> her oynayış ayrı maç sayılır
	public static var oncePerSong:Bool = true;

	public static var RENDER_FILE_NAME:String = 'render-ingame.json';
	public static var MAX_PENDING:Int = 50;
	public static var RETRY_SECONDS:Float = 8.0;

	// ---- Teşhis (ekranda gösterilir) ----
	public static var configPath:String = null; // ayarın okunduğu dosya
	public static var configError:String = null; // ayar okuma hatası
	public static var lastSyncStatus:Int = 0; // son HTTP kodu (0 = istek yok)
	public static var lastSyncError:String = null; // son hata mesajı
	public static var lastSyncUrl:String = null; // son istek adresi
	public static var lastSyncTime:String = null;

	static var _save:FlxSave = null;
	static var _loaded:Bool = false;

	static var _matches:Array<Dynamic> = []; // tamamlanmış maç kayıtları
	static var _claimed:Array<String> = []; // puanı alınmış maç anahtarları
	static var _pending:Array<Dynamic> = []; // Supabase'e gönderilecek kayıtlar
	static var _threadResults:Array<Dynamic> = []; // arka plandan dönen sonuçlar
	static var _awardedTotal:Int = 0; // toplam kazanılmış puan (ledger)
	static var _sending:Bool = false;
	static var _nextRetry:Float = 0;
	static var _wroteOnce:Bool = false;

	#if sys
	static var _mutex = new sys.thread.Mutex();
	static function lock() _mutex.acquire();
	static function unlock() _mutex.release();
	#else
	static function lock() {}
	static function unlock() {}
	#end

	static function timerMs():Float
	{
		var t:Float = 0;
		#if !js
		try
		{
			t = openfl.Lib.getTimer();
		}
		catch(e:Dynamic)
		{
			t = 0;
		}
		#end
		return t;
	}

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
		if(d.awardedTotal != null) _awardedTotal = Std.int(d.awardedTotal);

		// Ledger yoksa eski kayıtlardan hesapla
		if(_awardedTotal <= 0)
		{
			var sum:Int = 0;
			for(m in _matches)
				if(m != null && m.points != null) sum += Std.int(m.points);
			_awardedTotal = sum;
		}

		if(d.threadResults != null && d.threadResults.length > 0)
		{
			// Oyun kapanmadan önce gönderilmiş ama işlenememiş sonuçlar
			var saved:Array<Dynamic> = d.threadResults;
			for(r in saved) _threadResults.push(r);
			d.threadResults = null;
		}

		loadConfig();
	}

	public static function flush():Void
	{
		ensure();
		var d:Dynamic = _save.data;
		d.matches = _matches;
		d.claimed = _claimed;
		d.pending = _pending;
		d.awardedTotal = _awardedTotal;
		d.threadResults = _threadResults;
		_save.flush();
	}

	// ------------------------------------------------------------------
	// AYAR DOSYASI (supabase.json)
	// ------------------------------------------------------------------
	static function candidateDirs():Array<String>
	{
		var dirs:Array<String> = [];

		#if sys
		try dirs.push(Sys.getCwd()); catch(e:Dynamic) {}
		try
		{
			var prog:String = Sys.programPath();
			if(prog != null)
			{
				var dir:String = HxPath.directory(prog);
				if(dir != null && dir.length > 0) dirs.push(dir);
			}
		}
		catch(e:Dynamic) {}
		#end

		#if sys
		try dirs.push(StorageUtil.getStorageDirectory()); catch(e:Dynamic) {}
		#end

		// Tekrarları temizle + sonuna / ekle
		var result:Array<String> = [];
		for(dir in dirs)
		{
			if(dir == null || dir.length < 1) continue;
			if(dir.charAt(dir.length - 1) != '/' && dir.charAt(dir.length - 1) != '\\') dir += '/';
			if(!result.contains(dir)) result.push(dir);
		}
		return result;
	}

	/** supabase.json içindeki URL'yi düzeltir: /rest/v1 ve sondaki / kırpılır. */
	public static function normalizeUrl(url:String):String
	{
		if(url == null) return '';
		var u:String = url.trim();
		if(u.length < 1) return '';

		while(u.length > 0 && (u.charAt(u.length - 1) == '/' || u.charAt(u.length - 1) == '\\'))
			u = u.substr(0, u.length - 1);

		var lower:String = u.toLowerCase();
		var idx:Int = lower.indexOf('/rest/v1');
		// "https://" kısmını yanlışlıkla kesmemek için idx > 8 şartı
		if(idx > 8) u = u.substr(0, idx);

		while(u.length > 0 && u.charAt(u.length - 1) == '/')
			u = u.substr(0, u.length - 1);

		return u;
	}

	static function normalizeTable(table:String):String
	{
		if(table == null) return 'match_records';
		var t:String = table.trim();
		while(t.length > 0 && t.charAt(0) == '/') t = t.substr(1);
		while(t.length > 0 && t.charAt(t.length - 1) == '/') t = t.substr(0, t.length - 1);
		if(t.length < 1) t = 'match_records';
		return t;
	}

	static function loadConfig():Void
	{
		#if sys
		var files:Array<String> = [];

		for(dir in candidateDirs())
		{
			files.push(dir + 'supabase.json');
			files.push(dir + 'mods/supabase.json');
			files.push(dir + 'example_mods/supabase.json');

			// mods/ ve example_mods/ alt klasörleri
			for(sub in ['mods/', 'example_mods/'])
			{
				var folder:String = dir + sub;
				try
				{
					if(!sys.FileSystem.exists(folder) || !sys.FileSystem.isDirectory(folder)) continue;
					for(entry in sys.FileSystem.readDirectory(folder))
					{
						var subFolder:String = folder + entry + '/';
						if(sys.FileSystem.isDirectory(subFolder))
							files.push(subFolder + 'supabase.json');
					}
				}
				catch(e:Dynamic) {}
			}
		}

		for(file in files)
		{
			try
			{
				if(file == null || !sys.FileSystem.exists(file)) continue;
				var raw:String = sys.io.File.getContent(file);
				if(raw == null || raw.length < 2) continue;
				var cfg:Dynamic = Json.parse(raw);
				if(cfg == null) continue;

				var readUrl:String = null;
				var readKey:String = null;
				var readTable:String = null;

				if(cfg.url != null) readUrl = Std.string(cfg.url);
				else if(cfg.rest_url != null) readUrl = Std.string(cfg.rest_url);
				else if(cfg.SUPABASE_URL != null) readUrl = Std.string(cfg.SUPABASE_URL);
				else if(cfg.supabase_url != null) readUrl = Std.string(cfg.supabase_url);

				if(cfg.anon_key != null) readKey = Std.string(cfg.anon_key);
				else if(cfg.anonKey != null) readKey = Std.string(cfg.anonKey);
				else if(cfg.key != null) readKey = Std.string(cfg.key);
				else if(cfg.SUPABASE_ANON_KEY != null) readKey = Std.string(cfg.SUPABASE_ANON_KEY);

				if(cfg.table != null) readTable = Std.string(cfg.table);

				if(readUrl == null || readKey == null)
				{
					configError = 'Ayar eksik: ' + file + ' (url / anon_key gerekli)';
					continue;
				}

				SUPABASE_URL = normalizeUrl(readUrl);
				SUPABASE_ANON_KEY = readKey.trim();
				SUPABASE_TABLE = normalizeTable(readTable);
				if(cfg.once_per_song != null) oncePerSong = cfg.once_per_song == true;

				configPath = file;
				configError = null;
				trace('MatchRecords: ayar okundu -> ' + file + ' (' + SUPABASE_URL + ')');
				return;
			}
			catch(e:Dynamic)
			{
				configError = 'Ayar okunamadı: ' + file + ' -> ' + e;
				trace(configError);
			}
		}

		if(configError == null)
			configError = 'supabase.json bulunamadı (oyun klasörü / mods / example_mods)';
		#end
	}

	/** Ekranda göstermek için kısa teşhis metni */
	public static function configSummary():String
	{
		ensure();
		if(!isSupabaseConfigured())
			return 'SUPABASE: AYAR YOK - ' + (configError != null ? configError : '?');

		var text:String = 'SUPABASE: ' + SUPABASE_URL + ' / ' + SUPABASE_TABLE;
		if(configPath != null && configPath.length > 0)
		{
			// Uzun yolu kısalt: son 2 parça yeter (hangi dosya okundu?)
			var parts:Array<String> = configPath.split('/');
			var tail:String = parts[parts.length - 1];
			if(parts.length > 1) tail = parts[parts.length - 2] + '/' + tail;
			text += ' | dosya: ' + tail;
		}
		if(lastSyncStatus != 0)
		{
			text += ' | son: ' + lastSyncStatus;
			if(lastSyncError != null && lastSyncError.length > 0)
			{
				var err:String = lastSyncError;
				if(err.length > 40) err = err.substr(0, 38) + '..';
				text += ' (' + err + ')';
			}
		}
		return text;
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

	public static function hasClaimed(matchId:String):Bool
	{
		ensure();
		if(matchId == null) return false;
		return _claimed.contains(matchId);
	}

	/**
	 * Puan verildiği anda çağrılır.
	 * Aynı maçtan ikinci kez puan verilmesini engeller ve toplam puanı (ledger) günceller.
	 */
	public static function markClaimed(matchId:String, points:Int = 0):Void
	{
		ensure();
		if(matchId == null) return;
		if(!_claimed.contains(matchId)) _claimed.push(matchId);
		if(points > 0) _awardedTotal += points;
		flush();
	}

	/** Bugüne kadar kazanılmış toplam puan (ledger). */
	public static function awardedTotal():Int
	{
		ensure();
		return _awardedTotal;
	}

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
		if(record.played_at == null) record.played_at = Date.now().toString();
		record.synced = false;
		record.sync_status = 'pending';
		record.sync_error = null;

		// Aynı maç zaten kayıtlıysa üzerine yaz (mükerrer kayıt olmasın)
		var replaced:Bool = false;
		for (i in 0..._matches.length)
		{
			if(_matches[i] != null && _matches[i].match_id == record.match_id)
			{
				var old:Dynamic = _matches[i];

				// Aynı şarkı tekrar oynandığında eski kayıt SIFIRLANMASIN:
				// en yüksek skor / kombo ve kazanılmış puan korunur.
				if(old.score != null && record.score != null && Std.int(old.score) > Std.int(record.score))
					record.score = old.score;
				if(old.max_combo != null && record.max_combo != null && Std.int(old.max_combo) > Std.int(record.max_combo))
					record.max_combo = old.max_combo;
				if(old.points != null && record.points != null && Std.int(old.points) > Std.int(record.points))
				{
					record.points = old.points;
					record.points_reason = old.points_reason;
					record.milestones = old.milestones;
					record.points_log = old.points_log;
				}
				if(record.played_at == null && old.played_at != null) record.played_at = old.played_at;

				_matches[i] = record;
				replaced = true;
				break;
			}
		}
		if(!replaced) _matches.push(record);

		// Kuyruğa ekle (varsa güncel kayıtla değiştir, mükerrer olmasın)
		var queueIndex:Int = -1;
		for (i in 0..._pending.length)
			if(_pending[i] != null && _pending[i].match_id == record.match_id) queueIndex = i;

		if(queueIndex >= 0)
			_pending[queueIndex] = record;
		else
		{
			_pending.push(record);
			while(_pending.length > MAX_PENDING) _pending.shift();
		}

		flush();
		writeRenderFile();

		_nextRetry = 0; // hemen dene
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
			supabase_url: isSupabaseConfigured() ? SUPABASE_URL : null,
			supabase_table: isSupabaseConfigured() ? SUPABASE_TABLE : null,
			config_file: configPath,
			config_error: configError,
			last_sync_status: lastSyncStatus,
			last_sync_error: lastSyncError,
			last_sync_url: lastSyncUrl,
			total_matches: _matches.length,
			total_pending_sync: _pending.length,
			awarded_points_total: _awardedTotal,
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

	public static function endpointUrl():String
	{
		return SUPABASE_URL + '/rest/v1/' + SUPABASE_TABLE;
	}

	/** Bekleyen kayıtları arka planda gönderir (oyunu dondurmaz). */
	public static function submitPending():Void
	{
		ensure();
		if(_sending || _pending.length < 1) return;
		if(!isSupabaseConfigured()) return;
		if(_nextRetry > 0 && timerMs() < _nextRetry) return;

		_sending = true;
		var queue:Array<Dynamic> = _pending.copy();

		Thread.create(function() {
			try
			{
				for(rec in queue)
				{
					if(rec == null || rec.match_id == null) continue;
					var result:Dynamic = null;
					try
					{
						result = postRecord(rec);
					}
					catch(e:Dynamic)
					{
						result = cast {id: rec.match_id, ok: false, status: 0, error: Std.string(e), url: endpointUrl()};
					}
					lock();
					_threadResults.push(result);
					unlock();
				}
			}
			catch(e:Dynamic)
			{
				trace('MatchRecords: gönderim hatası -> ' + e);
			}
			_sending = false;
		});
	}

	/** Bekleyen kuyruğu hemen tekrar dene (ekrandaki "tekrar gönder"). */
	public static function retryNow():Void
	{
		ensure();
		_sending = false;
		_nextRetry = 0;
		lastSyncError = null;
		lastSyncStatus = 0;
		loadConfig(); // ayar dosyası yeni eklendiyse okunsun
		submitPending();
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

	/** Supabase tablosunda olmayan sütunlar varsa kullanılan yedek (küçük) payload. */
	static function toMinimalPayload(record:Dynamic):Dynamic
	{
		return {
			match_id: record.match_id,
			username: record.username,
			song: record.song,
			difficulty: record.difficulty,
			score: record.score,
			max_combo: record.max_combo,
			misses: record.misses,
			points: record.points,
			played_at: record.played_at
		};
	}

	static function request(body:String, ?onConflict:Bool = true):Dynamic
	{
		var statusCode:Int = 0;
		var errorMsg:String = null;
		var responseBody:String = '';
		var url:String = endpointUrl() + (onConflict ? '?on_conflict=match_id' : '');

		var http:Http = new Http(url);
		http.cnxTimeout = 15;
		http.setHeader('apikey', SUPABASE_ANON_KEY);
		http.setHeader('Authorization', 'Bearer ' + SUPABASE_ANON_KEY);
		http.setHeader('Content-Type', 'application/json');
		http.setHeader('Prefer', 'resolution=merge-duplicates,return=minimal');
		http.setPostData(body);

		http.onStatus = function(st:Int) { statusCode = st; };
		http.onData = function(d:String) { responseBody = d; };
		http.onError = function(e:String) { errorMsg = e; };

		try
		{
			http.request(true);
		}
		catch(e:Dynamic)
		{
			errorMsg = Std.string(e);
		}

		return {
			status: statusCode,
			error: errorMsg,
			body: responseBody,
			url: url
		};
	}

	static function postRecord(record:Dynamic):Dynamic
	{
		var res:Dynamic = request(Json.stringify(toSupabasePayload(record)), true);
		var status:Int = Std.int(res.status);

		// 400/404 -> tabloda olmayan sütun olabilir; küçük payload ile tekrar dene
		if(status == 400 || status == 404)
		{
			var retry:Dynamic = request(Json.stringify(toMinimalPayload(record)), false);
			if(Std.int(retry.status) >= 200 && Std.int(retry.status) < 300)
			{
				retry.error = 'küçük payload ile gönderildi (tabloda eksik sütunlar var)';
				return cast {id: record.match_id, ok: true, status: Std.int(retry.status), error: retry.error, url: retry.url};
			}
			res = retry;
			status = Std.int(res.status);
		}

		var ok:Bool = (status >= 200 && status < 300) || status == 409;
		var err:String = null;
		if(!ok)
		{
			var body:String = res.body != null ? Std.string(res.body) : '';
			if(body.length > 200) body = body.substr(0, 200);
			err = (res.error != null ? Std.string(res.error) : 'HTTP ' + status) + (body.length > 0 ? ' | ' + body : '');
		}

		return cast {id: record.match_id, ok: ok, status: status, error: err, url: res.url};
	}

	/** Her frame çağrılabilir; gönderim sonuçlarını işler, kuyruğu zamanı gelince dener. */
	public static function tick():Void
	{
		ensure();

		// Oturumda ilk kez: teşhis dosyasını yaz (ayar hatası olsa bile)
		if(!_wroteOnce)
		{
			_wroteOnce = true;
			writeRenderFile();
		}

		var results:Array<Dynamic> = [];
		lock();
		if(_threadResults.length > 0)
		{
			results = _threadResults.copy();
			_threadResults = [];
		}
		unlock();

		if(results.length > 0)
		{
			var changed:Bool = false;
			for(res in results)
			{
				if(res == null || res.id == null) continue;

				lastSyncStatus = Std.int(res.status);
				lastSyncError = res.error;
				lastSyncUrl = res.url;
				lastSyncTime = Date.now().toString();

				if(res.ok == true)
				{
					var stillPending:Array<Dynamic> = [];
					for(rec in _pending)
					{
						if(rec != null && rec.match_id == res.id)
						{
							rec.synced = true;
							rec.sync_status = 'synced';
							rec.sync_error = null;
						}
						else stillPending.push(rec);
					}
					_pending = stillPending;

					for(m in _matches)
					{
						if(m != null && m.match_id == res.id)
						{
							m.synced = true;
							m.sync_status = 'synced';
							m.sync_error = null;
						}
					}
					_nextRetry = 0;
				}
				else
				{
					for(m in _matches)
					{
						if(m != null && m.match_id == res.id)
						{
							m.sync_status = 'error';
							m.sync_error = res.error;
						}
					}
					_nextRetry = timerMs() + RETRY_SECONDS * 1000;
				}
				changed = true;
			}

			if(changed)
			{
				flush();
				writeRenderFile();
			}
		}

		submitPending();
	}

	public static function getMatches():Array<Dynamic>
	{
		ensure();
		return _matches;
	}

	/** En son oynanan maç (played_at'e göre) */
	public static function lastMatch():Dynamic
	{
		ensure();
		var best:Dynamic = null;
		for(m in _matches)
		{
			if(m == null || m.played_at == null) continue;
			if(best == null || Std.string(m.played_at) >= Std.string(best.played_at)) best = m;
		}
		return best;
	}

	public static function getMatch(matchId:String):Dynamic
	{
		ensure();
		for(m in _matches)
			if(m != null && m.match_id == matchId) return m;
		return null;
	}

	/**
	 * Sadece "puan alındı" işaretlerini temizler (maç kayıtları kalır).
	 * Test ederken aynı şarkıdan tekrar puan alabilmek için kullanılır.
	 */
	public static function resetClaimed():Int
	{
		ensure();
		var count:Int = _claimed.length;
		_claimed = [];
		flush();
		writeRenderFile();
		return count;
	}

	/** Puan hakkı verilmiş maç sayısı */
	public static function claimedCount():Int
	{
		ensure();
		return _claimed.length;
	}

	/** Test / sıfırlama için */
	public static function resetAll():Void
	{
		ensure();
		_matches = [];
		_claimed = [];
		_pending = [];
		_threadResults = [];
		_awardedTotal = 0;
		flush();
		writeRenderFile();
	}
}
