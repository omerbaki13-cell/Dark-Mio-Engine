package backend;

import flixel.util.FlxSave;

/**
 * KULLANICI OTURUMU  (çok hesaplı)
 * ------------------------------------------------------------------
 * En fazla 4 hesap cihazda saklanır; aralarında şifre girmeden
 * geçiş yapılabilir. Her hesabın puanı AYRIDIR.
 *
 * Düzeltilen hatalar:
 *  1) Puan tek bir global alanda tutuluyordu -> hesap değiştirince
 *     puan da aynı kalıyordu ("hesabı değiştirdim puan aynı").
 *     Artık puan hesap başına saklanıyor.
 *  2) MatchRecords'taki toplam puan (ledger) da globaldi ve çıkış/giriş
 *     sonrası puanı geri yükseltiyordu. Artık ledger kullanıcı adına göre.
 *  3) Çıkış yapınca puan silinmiyor; hesap listede kalır, geri dönülebilir.
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

// [{ username:String, userId:Int, points:Int }, ...] — en fazla MAX_ACCOUNTS
static var _accounts:Array<Dynamic> = [];

public static var MAX_ACCOUNTS:Int = 4;

public static var isLoggedIn(get, set):Bool;
public static var username(get, set):String;
public static var userId(get, set):Int;
public static var points(get, set):Int;

// ------------------------------------------------------------------
// kayıt (save)
// ------------------------------------------------------------------
static function ensure():Void
{
if(_loaded) return;
_loaded = true;

_save = new FlxSave();
_save.bind("mio_login", "MioEngine");
var d:Dynamic = _save.data;

_isLoggedIn = (d.isLoggedIn == true);
if(d.username != null) _username = d.username;
_userId = (d.userId != null) ? Std.int(d.userId) : -1;
_points = (d.points != null) ? Std.int(d.points) : 0;

// Kayıtlı hesaplar
if(d.accounts != null)
{
var saved:Array<Dynamic> = d.accounts;
for(a in saved)
{
if(a == null || a.username == null) continue;
_accounts.push({
username: Std.string(a.username),
userId: (a.userId != null) ? Std.int(a.userId) : -1,
points: (a.points != null) ? Std.int(a.points) : 0
});
}
}

// Eski tek hesaplı kayıttan taşıma
if(_accounts.length == 0 && _username != null)
{
_accounts.push({username: _username, userId: _userId, points: _points});
}

// Aktif hesabı listeyle eşle (yüksek puan kazanır)
var idx:Int = indexOf(_username);
if(idx >= 0)
{
var stored:Int = Std.int(_accounts[idx].points);
if(_accounts[idx].userId == null || Std.int(_accounts[idx].userId) < 0) _accounts[idx].userId = _userId;
if(_points > stored) _accounts[idx].points = _points;
else _points = stored;
}
else if(_username != null)
{
_accounts.push({username: _username, userId: _userId, points: _points});
}

// Ledger (hesap başına) daha yüksekse toparla
var ledger:Int = 0;
try { ledger = backend.MatchRecords.awardedTotal(); } catch(e:Dynamic) {}
if(ledger > _points && _username != null)
{
_points = ledger;
syncActive();
}

trim();
flush();
}

static function flush():Void
{
if(_save == null) return;
var d:Dynamic = _save.data;
d.isLoggedIn = _isLoggedIn;
d.username = _username;
d.userId = _userId;
d.points = _points;
d.accounts = _accounts;
_save.flush();
}

// ------------------------------------------------------------------
// yardımcılar
// ------------------------------------------------------------------
static function indexOf(name:String):Int
{
if(name == null) return -1;
var low:String = name.toLowerCase();
for(i in 0..._accounts.length)
{
var a:Dynamic = _accounts[i];
if(a == null || a.username == null) continue;
if(Std.string(a.username).toLowerCase() == low) return i;
}
return -1;
}

/** Aktif hesabın puanını/kimliğini listeye yazar. */
static function syncActive():Void
{
var idx:Int = indexOf(_username);
if(idx < 0) return;
_accounts[idx].userId = _userId;
_accounts[idx].points = _points;
}

static function trim():Void
{
while(_accounts.length > MAX_ACCOUNTS)
{
var removed:Bool = false;
for(i in 0..._accounts.length)
{
var a:Dynamic = _accounts[i];
if(a == null) { _accounts.splice(i, 1); removed = true; break; }
if(_username == null || Std.string(a.username).toLowerCase() != _username.toLowerCase())
{
_accounts.splice(i, 1);
removed = true;
break;
}
}
if(!removed) break;
}
}

// ------------------------------------------------------------------
// property'ler
// ------------------------------------------------------------------
static function get_isLoggedIn():Bool { ensure(); return _isLoggedIn; }
static function set_isLoggedIn(v:Bool):Bool { ensure(); _isLoggedIn = v; flush(); return v; }

static function get_username():String { ensure(); return _username; }
static function set_username(v:String):String { ensure(); _username = v; flush(); return v; }

static function get_userId():Int { ensure(); return _userId; }
static function set_userId(v:Int):Int { ensure(); _userId = v; syncActive(); flush(); return v; }

static function get_points():Int { ensure(); return _points; }
static function set_points(v:Int):Int { ensure(); _points = v; syncActive(); flush(); return v; }

/** Puan ekle ve hemen kaydet (sadece aktif hesaba yazılır). */
public static function addPoints(amount:Int):Int
{
ensure();
if(amount == 0) return _points;
_points += amount;
syncActive();
flush();
return _points;
}

// ------------------------------------------------------------------
// çok hesaplı giriş
// ------------------------------------------------------------------

/** Cihazda saklı hesaplar: [{username, userId, points}] (kopya). */
public static function getAccounts():Array<Dynamic>
{
ensure();
var out:Array<Dynamic> = [];
for(a in _accounts)
{
if(a == null) continue;
out.push({
username: Std.string(a.username),
userId: (a.userId != null) ? Std.int(a.userId) : -1,
points: (a.points != null) ? Std.int(a.points) : 0
});
}
return out;
}

public static function accountCount():Int
{
ensure();
return _accounts.length;
}

public static function hasAccount(name:String):Bool
{
ensure();
return indexOf(name) >= 0;
}

/** Bu kullanıcı adına kayıtlı puan (cihazda). */
public static function pointsOf(name:String):Int
{
ensure();
var idx:Int = indexOf(name);
if(idx < 0) return 0;
return (idx == indexOf(_username)) ? _points : Std.int(_accounts[idx].points);
}

/**
 * Giriş / kayıt başarılı olduğunda çağrılır.
 * Hesap listede yoksa ekler (en fazla 4), varsa puanı yükseltir ve aktif yapar.
 */
public static function loginAccount(name:String, id:Int, serverPoints:Int = 0):Void
{
ensure();
if(name == null || name.length == 0) return;

// Eski aktif hesap var mı? (yoksa _points "girişsiz" kazanılmış puandır)
var hadActive:Bool = (_username != null && indexOf(_username) >= 0);
var guestPoints:Int = hadActive ? 0 : _points;

syncActive(); // eski aktif hesabın puanını kaydet

var idx:Int = indexOf(name);
if(idx < 0)
{
// yer yoksa: aktif olmayan en eski hesabı çıkar
if(_accounts.length >= MAX_ACCOUNTS)
{
for(i in 0..._accounts.length)
{
var a:Dynamic = _accounts[i];
if(a == null || _username == null || Std.string(a.username).toLowerCase() != _username.toLowerCase())
{
_accounts.splice(i, 1);
break;
}
}
}
_accounts.push({username: name, userId: id, points: Math.max(0, Math.max(serverPoints, guestPoints))});
idx = _accounts.length - 1;
}
else
{
_accounts[idx].userId = id;
var local:Int = Std.int(_accounts[idx].points);
if(serverPoints > local) _accounts[idx].points = serverPoints;
if(guestPoints > Std.int(_accounts[idx].points)) _accounts[idx].points = guestPoints;
}

_username = Std.string(_accounts[idx].username);
_userId = id;
_points = Std.int(_accounts[idx].points);
_isLoggedIn = true;
flush();
}

/** Saklı hesaplardan birine geç. Puan o hesabın kendi puanıdır. */
public static function switchAccount(name:String):Bool
{
ensure();
var idx:Int = indexOf(name);
if(idx < 0) return false;
if(_username != null && Std.string(_accounts[idx].username).toLowerCase() == _username.toLowerCase() && _isLoggedIn)
{
return true; // zaten aktif
}

syncActive();
_username = Std.string(_accounts[idx].username);
_userId = (_accounts[idx].userId != null) ? Std.int(_accounts[idx].userId) : -1;
_points = (_accounts[idx].points != null) ? Std.int(_accounts[idx].points) : 0;
_isLoggedIn = true;
flush();
return true;
}

/**
 * Hesabı cihazdan çıkarır (puanı silmez: sunucuda durur, giriş yapınca geri gelir).
 * Aktif hesap çıkarılırsa kalan ilk hesaba geçilir; hiç hesap kalmazsa oturum kapanır.
 */
public static function removeAccount(name:String):Void
{
ensure();
var idx:Int = indexOf(name);
if(idx < 0) return;

var wasActive:Bool = (_username != null && Std.string(_accounts[idx].username).toLowerCase() == _username.toLowerCase());
_accounts.splice(idx, 1);

if(wasActive)
{
if(_accounts.length > 0)
{
_username = Std.string(_accounts[0].username);
_userId = (_accounts[0].userId != null) ? Std.int(_accounts[0].userId) : -1;
_points = (_accounts[0].points != null) ? Std.int(_accounts[0].points) : 0;
_isLoggedIn = true;
}
else
{
_username = null;
_userId = -1;
_points = 0;
_isLoggedIn = false;
}
}
flush();
}

/**
 * Oturumu kapatır ama hesabı listede TUTAR (puanıyla birlikte).
 * Tekrar giriş yapmadan geri dönülebilir.
 */
public static function logout()
{
ensure();
syncActive();
_isLoggedIn = false;
_username = null;
_userId = -1;
_points = 0;
flush();
}
}
