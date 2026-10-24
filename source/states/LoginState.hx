package states;

import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import haxe.Http;
import haxe.Json;
import backend.UserSession;
import sys.thread.Thread;
import flixel.FlxObject;

class LoginState extends MusicBeatState
{
// Hesap sunucusu (puan / liderlik / yonetim). PlayState'teki skor gonderimi de
// bu adresi kullanir; tek yerden degistirmek icin public.
public static var SERVER_URL:String = "https://dark-mio-engine.onrender.com";

var usernameInput:TextField;
var passwordInput:TextField;
var statusText:FlxText;
var isRegisterMode:Bool = false;
var isLoading:Bool = false;
var hasPendingResult:Bool = false;
var pendingResultOk:Bool = false;
var pendingResultText:String = null;
var pendingResultErr:String = null;
		var logoutMode:Bool = false;
		var logoutYesText:FlxText;
		var logoutNoText:FlxText;

		// "PUANI YENILE": sunucudaki puanla yerel puanı eşitler
		var pointsText:FlxText;
		var refreshText:FlxText;
		var hasRefreshResult:Bool = false;
		var refreshResultOk:Bool = false;
		var refreshResultPoints:Int = 0;
		var refreshResultPushed:Int = 0;
		var refreshResultErr:String = null;
		var refreshWasAuto:Bool = false;
		var isRefreshing:Bool = false;

var loginButton:FlxText;
var loginBtnBg:FlxSprite;
var switchModeText:FlxText;
var skipText:FlxText;
var titleText:FlxText;
var subText:FlxText;
var userLabel:FlxText;
var passLabel:FlxText;

override function create()
{
super.create();
persistentUpdate = persistentDraw = true;

var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
add(bg);

var cardW:Int = 600;
var cardH:Int = 620;
var cardX:Float = (FlxG.width - cardW) / 2;
var cardY:Float = (FlxG.height - cardH) / 2;

var card:FlxSprite = new FlxSprite(cardX, cardY).makeGraphic(cardW, cardH, FlxColor.fromRGB(30, 20, 45));
add(card);

titleText = new FlxText(cardX, cardY + 30, cardW, "GIRIS YAPIN", 40);
titleText.setFormat(Paths.font("vcr.ttf"), 40, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
add(titleText);

subText = new FlxText(cardX, cardY + 85, cardW, "Hesabina baglan", 20);
subText.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.GRAY, CENTER);
add(subText);

userLabel = new FlxText(cardX + 50, cardY + 140, 500, "KULLANICI ADI", 16);
userLabel.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT);
add(userLabel);

usernameInput = new TextField();
usernameInput.type = TextFieldType.INPUT;
		usernameInput.x = ((openfl.Lib.current.stage.stageWidth - 1280 * (openfl.Lib.current.stage.stageHeight / 720)) / 2) + (cardX + 50) * (openfl.Lib.current.stage.stageHeight / 720);
		usernameInput.scaleX = (openfl.Lib.current.stage.stageHeight / 720);
		usernameInput.scaleY = (openfl.Lib.current.stage.stageHeight / 720);
		usernameInput.y = 0.0 + (cardY + 165) * (openfl.Lib.current.stage.stageHeight / 720);
usernameInput.width = 500;
usernameInput.height = 40;
usernameInput.background = true;
usernameInput.backgroundColor = 0x323041;
usernameInput.textColor = 0xFFFFFF;
usernameInput.defaultTextFormat = new TextFormat(null, 20, 0xFFFFFF);
FlxG.stage.addChild(usernameInput);

passLabel = new FlxText(cardX + 50, cardY + 220, 500, "SIFRE", 16);
passLabel.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT);
add(passLabel);


loginButton = new FlxText(cardX + 50, cardY + 328, 500, "GIRIS YAP", 28);
loginButton.setFormat(Paths.font("vcr.ttf"), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
add(loginButton);

statusText = new FlxText(cardX, cardY + 390, cardW, "", 18);
statusText.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.RED, CENTER);
add(statusText);

switchModeText = new FlxText(cardX, cardY + 440, cardW, "Hesabin yok mu? Kayit ol", 20);
switchModeText.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.fromRGB(180, 130, 255), CENTER);
add(switchModeText);

skipText = new FlxText(cardX, cardY + 490, cardW, "Atla", 20);
skipText.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.GRAY, CENTER);
add(skipText);


passwordInput = new TextField();
passwordInput.type = TextFieldType.INPUT;
passwordInput.displayAsPassword = true;
		passwordInput.x = ((openfl.Lib.current.stage.stageWidth - 1280 * (openfl.Lib.current.stage.stageHeight / 720)) / 2) + (cardX + 50) * (openfl.Lib.current.stage.stageHeight / 720);
		passwordInput.scaleX = (openfl.Lib.current.stage.stageHeight / 720);
		passwordInput.scaleY = (openfl.Lib.current.stage.stageHeight / 720);
		passwordInput.y = 0.0 + (cardY + 245) * (openfl.Lib.current.stage.stageHeight / 720);
passwordInput.width = 500;
passwordInput.height = 40;
passwordInput.background = true;
passwordInput.backgroundColor = 0x323041;
passwordInput.textColor = 0xFFFFFF;
passwordInput.defaultTextFormat = new TextFormat(null, 20, 0xFFFFFF);
FlxG.stage.addChild(passwordInput);

loginBtnBg = new FlxSprite(cardX + 50, cardY + 310).makeGraphic(500, 60, FlxColor.fromRGB(120, 80, 200));
add(loginBtnBg);

if(backend.UserSession.isLoggedIn)
{
logoutMode = true;
titleText.text = "HESABIN";
subText.text = backend.UserSession.username;
usernameInput.visible = false;
passwordInput.visible = false;
userLabel.visible = false;
passLabel.visible = false;
loginBtnBg.visible = false;
loginButton.visible = false;
switchModeText.visible = false;
skipText.text = "Geri Don";
skipText.y = cardY + 470;

// Toplam puan (sunucu ile esitlenince burada guncellenir)
pointsText = new FlxText(cardX, cardY + 140, cardW, "", 30);
pointsText.setFormat(Paths.font("vcr.ttf"), 30, 0xFFFFD34D, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
add(pointsText);
updatePointsLabel();

// Cikis Yap yerine once puan yenileme
refreshText = new FlxText(cardX, cardY + 230, cardW, "PUANI YENILE", 26);
refreshText.setFormat(Paths.font("vcr.ttf"), 26, 0xFF9B6DFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
add(refreshText);

logoutYesText = new FlxText(cardX, cardY + 320, cardW, "Cikis Yap", 26);
logoutYesText.setFormat(Paths.font("vcr.ttf"), 26, FlxColor.RED, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
add(logoutYesText);

// Ekran acilirken bir kez sessizce esitle; dugme ile istenirse tekrar denenir.
doRefreshPoints(true);
}

}

override function destroy()
{
if(usernameInput != null && usernameInput.parent != null) usernameInput.parent.removeChild(usernameInput);
if(passwordInput != null && passwordInput.parent != null) passwordInput.parent.removeChild(passwordInput);
super.destroy();
}

function isTouched(obj:FlxObject):Bool
{
if(FlxG.mouse.justPressed && FlxG.mouse.overlaps(obj))
return true;
for (touch in FlxG.touches.list)
if(touch.justPressed && touch.overlaps(obj))
return true;
return false;
}

override function update(elapsed:Float)
{
super.update(elapsed);

if(hasPendingResult)
{
hasPendingResult = false;
isLoading = false;
handleResult(pendingResultOk, pendingResultText, pendingResultErr);
}

if(hasRefreshResult)
{
hasRefreshResult = false;
isRefreshing = false;
handleRefreshResult(refreshResultOk, refreshResultPoints, refreshResultPushed, refreshResultErr);
}

if(isLoading) return;

if(logoutMode)
{
if(refreshText != null && isTouched(refreshText))
{
doRefreshPoints();
}
else if(isTouched(logoutYesText))
{
backend.UserSession.logout();
FlxG.sound.play(Paths.sound("cancelMenu"));
MusicBeatState.switchState(new LoginState());
}
else if(isTouched(skipText) || controls.BACK)
{
FlxG.sound.play(Paths.sound("cancelMenu"));
MusicBeatState.switchState(new MainMenuState());
}
return;
}

if(isTouched(loginBtnBg) || isTouched(loginButton))
{
doSubmit();
}
else if(isTouched(switchModeText))
{
isRegisterMode = !isRegisterMode;
loginButton.text = isRegisterMode ? "KAYIT OL" : "GIRIS YAP";
switchModeText.text = isRegisterMode ? "Hesabin var mi? Giris yap" : "Hesabin yok mu? Kayit ol";
statusText.text = "";
FlxG.sound.play(Paths.sound("scrollMenu"));
}
else if(isTouched(skipText) || controls.BACK)
{
FlxG.sound.play(Paths.sound("cancelMenu"));
MusicBeatState.switchState(new MainMenuState());
}
}

function handleResult(ok:Bool, data:String, err:String)
{
if(err != null)
{
statusText.color = FlxColor.RED;
if(err == "AUTH_FAIL")
statusText.text = isRegisterMode ? "Kayit basarisiz" : "Kullanici Adi Veya Sifre Yanlis";
else if(err == "USER_EXISTS")
statusText.text = "Bu kullanici adi zaten alinmis";
else
statusText.text = turkceHata(err);
return;
}

try
{
var res:Dynamic = Json.parse(data);
if(res.success == true)
{
UserSession.isLoggedIn = true;
UserSession.username = res.username;
UserSession.userId = res.user_id;

// Sunucuda daha yüksek bir puan varsa onu al (yerel puanı ASLA düşürme)
var serverPoints:Int = 0;
if(res.points != null) serverPoints = Std.int(res.points);
else if(res.score != null) serverPoints = Std.int(res.score);
if(serverPoints > UserSession.points) UserSession.points = serverPoints;

FlxG.sound.play(Paths.sound("confirmMenu"));
MusicBeatState.switchState(new MainMenuState());
}
else
{
statusText.color = FlxColor.RED;
statusText.text = (res.error != null) ? Std.string(res.error) : "Bir hata olustu";
}
}
catch(e:Dynamic)
{
statusText.color = FlxColor.RED;
statusText.text = "Sunucu hatasi";
}
}

function updatePointsLabel():Void
{
if(pointsText == null) return;
pointsText.text = "PUAN: " + backend.UserSession.points;
}

/**
 * "PUANI YENILE"
 * 1) Sunucudaki puani okur (kullanici adiyla; user_id degismis olabilir).
 * 2) Sunucu daha yuksekse yerel puani yukseltir.
 * 3) Yerel puan daha yuksekse aradaki farki /sync ile sunucuya tasir.
 *    Puan asla azalmaz, iki taraf esitlenir.
 */
function doRefreshPoints(auto:Bool = false):Void
{
if(isRefreshing) return; // zaten devam eden bir istek var
isRefreshing = true;
refreshWasAuto = auto;
if(refreshText != null) refreshText.color = FlxColor.GRAY;
statusText.color = FlxColor.WHITE;
statusText.text = "Puanlar sunucudan aliniyor...";

var uname:String = backend.UserSession.username;
var uid:Int = backend.UserSession.userId;
var localPoints:Int = backend.UserSession.points;

Thread.create(function()
{
var ok:Bool = false;
var serverPoints:Int = 0;
var pushed:Int = 0;
var err:String = null;

try
{
var url:String = SERVER_URL + "/profile?username=" + StringTools.urlEncode(uname == null ? "" : uname);
var http:Http = new Http(url);
http.cnxTimeout = 30;
var body:String = null;
http.onData = function(d:String) body = d;
http.onError = function(e:String) err = e;
http.request(false);

if(body != null)
{
var res:Dynamic = Json.parse(body);
if(res != null && res.success == true)
{
ok = true;
serverPoints = Std.int(res.points);
if(res.user_id != null) uid = Std.int(res.user_id);
}
else if(res != null && res.error != null) err = Std.string(res.error);
}
}
catch(e:Dynamic) { err = Std.string(e); }

// Yerel puan daha yuksekse farki gonder
if(ok && localPoints > serverPoints && uid >= 0)
{
try
{
var up:Http = new Http(SERVER_URL + "/sync");
up.cnxTimeout = 30;
up.setHeader("Content-Type", "application/json");
up.setPostData(Json.stringify({user_id: uid, points: localPoints, username: uname}));
var upBody:String = null;
up.onData = function(d:String) upBody = d;
up.request(false);
if(upBody != null)
{
var r:Dynamic = Json.parse(upBody);
if(r != null && r.success == true)
{
serverPoints = Std.int(r.points);
pushed = Std.int(r.added);
}
}
}
catch(e:Dynamic) {}
}

refreshResultOk = ok;
refreshResultPoints = serverPoints;
refreshResultPushed = pushed;
refreshResultErr = err;
hasRefreshResult = true;
});
}

function handleRefreshResult(ok:Bool, serverPoints:Int, pushed:Int, err:String):Void
{
if(refreshText != null) refreshText.color = 0xFF9B6DFF;

if(!ok)
{
if(refreshWasAuto)
{
// Ekran acilirken yapilan deneme: kullaniciyi kirmizi hata ile korkutma
statusText.color = FlxColor.GRAY;
statusText.text = "Cevrimdisi - puanlar cihazda sakli";
}
else
{
statusText.color = FlxColor.RED;
statusText.text = turkceHata(err == null ? "Baglanti hatasi" : err);
}
updatePointsLabel();
return;
}

var local:Int = backend.UserSession.points;
if(serverPoints > local)
{
backend.UserSession.points = serverPoints;
statusText.color = FlxColor.GREEN;
statusText.text = "+" + (serverPoints - local) + " puan guncellendi";
}
else if(pushed > 0)
{
statusText.color = FlxColor.GREEN;
statusText.text = pushed + " puan sunucuya gonderildi";
}
else
{
statusText.color = FlxColor.GRAY;
statusText.text = "Puanlar guncel (" + local + ")";
}
updatePointsLabel();
}

function turkceHata(err:String):String
{
if(err == "Blocked" || err == "Timeout" || err == "Eof")
return "Sunucu yanit vermedi. Biraz bekleyip tekrar dene";
if(err.indexOf("Http Error #5") == 0)
return "Sunucu hatasi, biraz sonra tekrar dene";
if(err.indexOf("Http Error #400") == 0)
return "Gecersiz istek";
if(err.indexOf("SSL") != -1 || err.indexOf("ertificate") != -1)
return "Guvenli baglanti kurulamadi";
if(err.indexOf("Failed") != -1 || err.indexOf("resolve") != -1)
return "Internet baglantisi yok";
return "Baglanti hatasi: " + err;
}

function doSubmit()
{
var username:String = usernameInput.text.trim();
var password:String = passwordInput.text.trim();

if(username.length < 1 || password.length < 1)
{
statusText.text = "Kullanici adi ve sifre gerekli!";
return;
}

isLoading = true;
statusText.color = FlxColor.WHITE;
statusText.text = "Sunucu uyaniyor, 1 dk surebilir...";

var endpoint:String = isRegisterMode ? "/register" : "/login";
Thread.create(function()
{
var resultText:String = null;
var resultOk:Bool = false;
var resultErr:String = null;
var tries:Int = 0;

while(tries < 2)
{
tries++;
resultText = null; resultOk = false; resultErr = null;
var statusCode:Int = 0;

var http:Http = new Http(SERVER_URL + endpoint);
http.cnxTimeout = 90;
http.setHeader("Content-Type", "application/json");
http.setPostData(Json.stringify({username: username, password: password}));

http.onStatus = function(st:Int) { statusCode = st; }
http.onData = function(d:String) { resultOk = true; resultText = d; }
http.onError = function(e:String)
{
if(statusCode == 401 || statusCode == 404) resultErr = "AUTH_FAIL";
else if(statusCode == 409) resultErr = "USER_EXISTS";
else resultErr = e;
}

try { http.request(true); }
catch(e:Dynamic) { resultErr = Std.string(e); }

if(resultErr != "Blocked") break;
}

pendingResultOk = resultOk;
pendingResultText = resultText;
pendingResultErr = resultErr;
hasPendingResult = true;
});
}
}
