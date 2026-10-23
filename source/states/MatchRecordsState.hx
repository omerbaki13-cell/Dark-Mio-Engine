package states;

/**
 * MAÇ KAYITLARI EKRANI
 * Oynanan maçların listesini gösterir (render-ingame.json içeriği ile aynı veri).
 * MainMenu'den TAB / tıklama ile açılır.
 */
class MatchRecordsState extends MusicBeatState
{
	var grpRows:FlxTypedGroup<FlxText>;
	var rows:Array<FlxText> = [];
	var data:Array<Dynamic> = [];

	var summaryTxt:FlxText;
	var emptyTxt:FlxText;
	var hintTxt:FlxText;

	var curSelected:Int = 0;
	var rowHeight:Float = 48;
	var topY:Float = 215;
	var maxVisible:Int = 8;
	var canLeave:Bool = false;

	override function create()
	{
		super.create();
		persistentUpdate = persistentDraw = true;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Match Records", null);
		#end

		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.scrollFactor.set(0, 0.25);
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		bg.color = 0xFF5F5F5F;
		add(bg);

		var title:FlxText = new FlxText(0, 40, FlxG.width, Language.getPhrase('match_records_title', 'MAÇ KAYITLARI'), 48);
		title.setFormat(Paths.font('vcr.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set();
		add(title);

		summaryTxt = new FlxText(0, 100, FlxG.width, '', 24);
		summaryTxt.setFormat(Paths.font('vcr.ttf'), 24, 0xFFFFD34D, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		summaryTxt.scrollFactor.set();
		add(summaryTxt);

		// Sütun başlıkları
		var bgBar:FlxSprite = new FlxSprite(60, 152).makeGraphic(FlxG.width - 120, 34, 0xFF000000);
		bgBar.alpha = 0.45;
		bgBar.scrollFactor.set();
		add(bgBar);

		var header:FlxText = new FlxText(70, 160, FlxG.width - 140, '', 20);
		header.setFormat(Paths.font('vcr.ttf'), 20, 0xFF8CFF8C, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		header.scrollFactor.set();
		header.text = buildHeader();
		add(header);

		grpRows = new FlxTypedGroup<FlxText>();
		add(grpRows);

		emptyTxt = new FlxText(0, 300, FlxG.width, Language.getPhrase('match_records_empty', 'Henüz kayıtlı maç yok.\nBir şarkı bitir, burada görünsün!'), 28);
		emptyTxt.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyTxt.scrollFactor.set();
		emptyTxt.visible = false;
		add(emptyTxt);

		hintTxt = new FlxText(0, FlxG.height - 40, FlxG.width, Language.getPhrase('match_records_hint', 'GERİ: Menü   |   ONAY: Tekrar gönder'), 16);
		hintTxt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.GRAY, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintTxt.scrollFactor.set();
		add(hintTxt);

		reloadData();

		addTouchPad('UP_DOWN', 'A_B');
		addTouchPadCamera();

		canLeave = false;
		new FlxTimer().start(0.4, function(_) canLeave = true);
	}

	function buildHeader():String
	{
		return '#   ' + Language.getPhrase('match_records_song', 'ŞARKI').rpad(' ', 26).substr(0, 26)
			+ Language.getPhrase('match_records_score', 'SKOR').lpad(' ', 9)
			+ Language.getPhrase('match_records_combo', 'KOMBO').lpad(' ', 7)
			+ Language.getPhrase('match_records_points', 'PUAN').lpad(' ', 7)
			+ '   ' + Language.getPhrase('match_records_status', 'DURUM');
	}

	function buildRow(index:Int, rec:Dynamic):String
	{
		if(rec == null) return '';

		var idx:String = Std.string(index + 1).lpad('0', 2);
		var song:String = Std.string(rec.song) + ' (' + Std.string(rec.difficulty) + ')';
		if(song.length > 26) song = song.substr(0, 25) + '~';
		song = song.rpad(' ', 26);

		var score:String = Std.string(rec.score).lpad(' ', 9);
		var combo:String = Std.string(rec.max_combo).lpad(' ', 7);
		var points:String = ('+' + Std.string(rec.points)).lpad(' ', 7);

		var status:String = '';
		if(rec.synced == true) status = Language.getPhrase('match_records_synced', 'SENKRON');
		else status = Language.getPhrase('match_records_pending', 'BEKLIYOR');

		if(rec.eligible != true)
			status = Language.getPhrase('match_records_no_points', 'PUANSIZ');

		return idx + '   ' + song + score + combo + points + '   ' + status;
	}

	function rowColor(rec:Dynamic):Int
	{
		if(rec == null) return FlxColor.WHITE;
		if(rec.eligible != true) return 0xFFB0B0B0;
		if(rec.points != null && rec.points > 0) return 0xFFFFD34D;
		return FlxColor.WHITE;
	}

	function reloadData():Void
	{
		data = backend.MatchRecords.getMatches().copy();
		// En yeni maç en üstte
		data.reverse();

		for(row in rows)
		{
			grpRows.remove(row, true);
			row.destroy();
		}
		rows = [];

		if(curSelected >= data.length) curSelected = Std.int(Math.max(0, data.length - 1));

		for (i in 0...data.length)
		{
			var row:FlxText = new FlxText(70, topY, FlxG.width - 140, buildRow(i, data[i]), 20);
			row.setFormat(Paths.font('vcr.ttf'), 20, rowColor(data[i]), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.scrollFactor.set();
			row.ID = i;
			rows.push(row);
			grpRows.add(row);
		}

		emptyTxt.visible = (data.length < 1);

		var pending:Int = backend.MatchRecords.pendingCount();
		summaryTxt.text = Language.getPhrase('match_records_summary', 'MAÇ: {1}   |   PUAN: {2}   |   BEKLEYEN: {3}',
			[data.length, backend.UserSession.points, pending]);

		updateRowPositions();
	}

	function updateRowPositions():Void
	{
		for (i in 0...rows.length)
		{
			var row:FlxText = rows[i];
			var diff:Int = i - curSelected;
			row.y = topY + diff * rowHeight;
			row.alpha = 1;
			if(diff != 0) row.alpha = 0.7;
			row.visible = (diff >= 0 && diff <= maxVisible);
		}
	}

	function changeSelection(change:Int):Void
	{
		if(data.length < 1) return;
		var old:Int = curSelected;
		curSelected = Std.int(FlxMath.wrap(curSelected + change, 0, data.length - 1));
		if(old != curSelected)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			updateRowPositions();
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (FlxG.mouse.wheel != 0)
			changeSelection(-FlxG.mouse.wheel);

		// Tekrar gönder (senkronize et)
		if (controls.ACCEPT || touchPad.buttonA.justPressed)
		{
			backend.MatchRecords.submitPending();
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		}

		// Kayıtları yenile
		if (controls.RESET || touchPad.buttonB.justPressed)
		{
			reloadData();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}

		if (canLeave && controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}
	}
}
