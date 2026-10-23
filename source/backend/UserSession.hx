package backend;

import flixel.util.FlxSave;

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
if(d.isLoggedIn == true)
{
_isLoggedIn = true;
_username = d.username;
_userId = d.userId != null ? d.userId : -1;
_points = d.points != null ? d.points : 0;
}
}

static function flush():Void
{
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

public static function logout()
{
isLoggedIn = false;
username = null;
userId = -1;
points = 0;
}
}
