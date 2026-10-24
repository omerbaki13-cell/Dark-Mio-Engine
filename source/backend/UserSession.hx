package backend;

import flixel.util.FlxSave;

/**
 * KULLANICI OTURUMU
 * ------------------------------------------------------------------
 * Düzeltilen hata:
 *   Puanlar sadece `isLoggedIn == true` iken yükleniyordu. Giriş
 *   yapılmamışsa (veya oturum düştüyse) oyun her açılışta puanları
 *   0'dan başlatıyordu -> "çıkıp girince puanlar siliniyor".
 *   Ayrıca `logout()` puanları sıfırlıyordu.
 *
 *   Artık:
 *   - Puanlar giriş durumundan bağımsız olarak her zaman yükleniyor.
 *   - Çıkış yapınca puanlar SİLİNMİYOR.
 *   - Kayıt bozulsa bile MatchRecords'taki toplam puandan (ledger)
 *     geri toparlanıyor.
 * ------------------------------------------------------------------
 */
class UserSession
{
static var _save:FlxSave = null;
static var _loaded:Bool = false;
static var _isLoggedIn:Bool = false;
static var _username:String = null;
static var _userId:Int = -1;
static var _points:Int = 0;

public static var isLoggedIn(get, set):Bool;
public static var username(get, set):String;
public static var userId(get, set):Int;
public static var points(get, set):Int;

static function ensure():Void
{
if(_loaded) return;
_loaded = true;
_save = new FlxSave();
_save.bind("mio_login", "MioEngine");
var d:Dynamic = _save.data;

// Giriş bilgileri
_isLoggedIn = (d.isLoggedIn == true);
if(d.username != null) _username = d.username;
_userId = (d.userId != null) ? Std.int(d.userId) : -1;

// PUAN: giriş yapılmamış olsa bile her zaman yükle
_points = (d.points != null) ? Std.int(d.points) : 0;

// Maç kayıtlarındaki toplam puandan geri toparla (kayıt bozulursa)
var ledger:Int = 0;
try { ledger = backend.MatchRecords.awardedTotal(); } catch(e:Dynamic) {}
if(ledger > _points)
{
_points = ledger;
flush();
}
}

static function flush():Void
{
if(_save == null) return;
var d:Dynamic = _save.data;
d.isLoggedIn = _isLoggedIn;
d.username = _username;
d.userId = _userId;
d.points = _points;
_save.flush();
}

static function get_isLoggedIn():Bool { ensure(); return _isLoggedIn; }
static function set_isLoggedIn(v:Bool):Bool { ensure(); _isLoggedIn = v; flush(); return v; }
static function get_username():String { ensure(); return _username; }
static function set_username(v:String):String { ensure(); _username = v; flush(); return v; }
static function get_userId():Int { ensure(); return _userId; }
static function set_userId(v:Int):Int { ensure(); _userId = v; flush(); return v; }
static function get_points():Int { ensure(); return _points; }
static function set_points(v:Int):Int { ensure(); _points = v; flush(); return v; }

/** Puan ekle ve hemen kaydet. */
public static function addPoints(amount:Int):Int
{
ensure();
if(amount == 0) return _points;
_points += amount;
flush();
return _points;
}

public static function logout()
{
ensure();
// Puanlar SİLİNMEZ: bunlar oyuncunun kazandığı puanlar.
_isLoggedIn = false;
_username = null;
_userId = -1;
flush();
}
}
