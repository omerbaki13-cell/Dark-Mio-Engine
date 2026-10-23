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
static var SERVER_URL:String = "https://psych-nm.onrender.com";

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

logoutYesText = new FlxText(cardX, cardY + 320, cardW, "Cikis Yap", 26);
logoutYesText.setFormat(Paths.font("vcr.ttf"), 26, FlxColor.RED, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
add(logoutYesText);
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

if(isLoading) return;

if(logoutMode)
{
if(isTouched(logoutYesText))
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
statusText.text = "Baglanti hatasi: " + err;
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
statusText.text = "Yukleniyor...";

var endpoint:String = isRegisterMode ? "/register" : "/login";
Thread.create(function()
{
var http:Http = new Http(SERVER_URL + endpoint);
http.setHeader("Content-Type", "application/json");
http.setPostData(Json.stringify({username: username, password: password}));

var resultText:String = null;
var resultOk:Bool = false;
var resultErr:String = null;

var statusCode:Int = 0;
http.onStatus = function(status:Int)
{
statusCode = status;
}
http.onData = function(data:String)
{
resultOk = true;
resultText = data;
}
http.onError = function(error:String)
{
if(statusCode == 401 || statusCode == 404)
resultErr = "AUTH_FAIL";
else if(statusCode == 409)
resultErr = "USER_EXISTS";
else
resultErr = error;
}

try
{
http.request(false);
}
catch(e:Dynamic)
{
resultErr = Std.string(e);
}

pendingResultOk = resultOk;
pendingResultText = resultText;
pendingResultErr = resultErr;
hasPendingResult = true;
});
}
}
