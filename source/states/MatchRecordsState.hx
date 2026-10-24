package states;

/**
 * MAÇ KAYITLARI EKRANI (v2)
 * ------------------------------------------------------------------
 * - Her maçın puanı ve NE ZAMAN / NEDEN alındığı görünür.
 * - Senkron durumu + Supabase hata kodu (404 / 401 / RLS vb.) gösterilir.
 * - ONlar: tekrar gönder / yenile.
 * ------------------------------------------------------------------
 */
class MatchRecordsState extends MusicBeatState
{
	var grpRows:FlxTypedGroup<FlxText>;
	var rows:Array<FlxText> = [];
	var data:Array<Dynamic> = [];

	var summaryTxt:FlxText;
	var configTxt:FlxText;
	var detailTxt:FlxText;
	var emptyTxt:FlxText;
	var hintTxt:FlxText;

	var curSelected:Int = 0;
	var rowHeight:Float = 42;
	var topY:Float = 228;
	var maxVisible:Int = 6;
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

		var title:FlxText = new FlxText(0, 30, FlxG.width, Language.getPhrase('match_records_title', 'MAÇ KAYITLARI'), 44);
		title.setFormat(Paths.font('vcr.ttf'), 44, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set();
		add(title);

		summaryTxt = new FlxText(0, 86, FlxG.width, '', 22);
		summaryTxt.setFormat(Paths.font('vcr.ttf'), 22, 0xFFFFD34D, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		summaryTxt.scrollFactor.set();
		add(summaryTxt);

		configTxt = new FlxText(0, 116, FlxG.width, '', 15);
		configTxt.setFormat(Paths.font('vcr.ttf'), 15, 0xFFB0B0B0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		configTxt.scrollFactor.set();
		add(configTxt);

		// Sütun başlıkları
		var bgBar:FlxSprite = new FlxSprite(50, 168).makeGraphic(FlxG.width - 100, 34, 0xFF000000);
		bgBar.alpha = 0.5;
		bgBar.scrollFactor.set();
		add(bgBar);

		var header:FlxText = new FlxText(60, 176, FlxG.width - 120, '', 19);
		header.setFormat(Paths.font('vcr.ttf'), 19, 0xFF8CFF8C, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		header.scrollFactor.set();
		header.text = buildHeader();
		add(header);

		grpRows = new FlxTypedGroup<FlxText>();
		add(grpRows);

		// Seçili maç detayı (puan dökümü + senkron hatası)
		var detailBg:FlxSprite = new FlxSprite(50, FlxG.height - 118).makeGraphic(FlxG.width - 100, 66, 0xFF000000);
		detailBg.alpha = 0.55;
		detailBg.scrollFactor.set();
		add(detailBg);

		detailTxt = new FlxText(60, FlxG.height - 112, FlxG.width - 120, '', 16);
		detailTxt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		detailTxt.scrollFactor.set();
		add(detailTxt);

		emptyTxt = new FlxText(0, 300, FlxG.width, Language.getPhrase('match_records_empty', 'Henüz kayıtlı maç yok.\nBir şarkı bitir, burada görünsün!'), 26);
		emptyTxt.setFormat(Paths.font('vcr.ttf'), 26, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyTxt.scrollFactor.set();
		emptyTxt.visible = false;
		add(emptyTxt);

		hintTxt = new FlxText(0, FlxG.height - 34, FlxG.width, Language.getPhrase('match_records_hint', 'GERİ: Menü   |   ONAY: Tekrar gönder   |   SIFIRLA: Yenile'), 15);
		hintTxt.setFormat(Paths.font('vcr.ttf'), 15, FlxColor.GRAY, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
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
		return '#   '
			+ Language.getPhrase('match_records_song', 'ŞARKI').rpad(' ', 25).substr(0, 25)
			+ Language.getPhrase('match_records_score', 'SKOR').lpad(' ', 8)
			+ Language.getPhrase('match_records_combo', 'KOMBO').lpad(' ', 7)
			+ Language.getPhrase('match_records_points', 'PUAN').lpad(' ', 6)
			+ '   ' + Language.getPhrase('match_records_status', 'DURUM');
	}

	function statusText(rec:Dynamic):String
	{
		if(rec == null) return '';

		if(rec.synced == true) return Language.getPhrase('match_records_synced', 'SENKRON');
		if(rec.sync_status == 'error')
		{
			var code:String = (rec.sync_error != null) ? ' ' + Std.string(rec.sync_error) : '';
			if(code.length > 26) code = code.substr(0, 26);
			return Language.getPhrase('match_records_error', 'HATA') + code;
		}
		return Language.getPhrase('match_records_pending', 'BEKLİYOR');
	}

	function buildRow(index:Int, rec:Dynamic):String
	{
		if(rec == null) return '';

		var idx:String = Std.string(index + 1).lpad('0', 2);
		var song:String = Std.string(rec.song) + ' (' + Std.string(rec.difficulty) + ')';
		if(song.length > 25) song = song.substr(0, 24) + '~';
		song = song.rpad(' ', 25);

		var score:String = Std.string(rec.score).lpad(' ', 8);
		var combo:String = Std.string(rec.max_combo).lpad(' ', 7);
		var points:String = ('+' + Std.string(rec.points)).lpad(' ', 6);

		return idx + '   ' + song + score + combo + points + '   ' + statusText(rec);
	}

	function rowColor(rec:Dynamic):Int
	{
		if(rec == null) return FlxColor.WHITE;
		if(rec.points != null && rec.points > 0) return 0xFFFFD34D;
		if(rec.eligible != true) return 0xFFB0B0B0;
		return FlxColor.WHITE;
	}

	function pointsReasonText(rec:Dynamic):String
	{
		var reason:String = (rec.points_reason != null) ? Std.string(rec.points_reason) : '';
		if(reason == 'OK' || reason == '')
		{
			if(rec.points != null && rec.points > 0) return Language.getPhrase('match_records_reason_ok', 'Puan verildi');
			return Language.getPhrase('match_records_reason_none', 'Puan yok');
		}
		return reason;
	}

	function buildDetail(rec:Dynamic):String
	{
		if(rec == null) return '';

		var lines:Array<String> = [];

		lines.push(Language.getPhrase('match_records_detail_points', 'PUAN: +{1}   |   SEBEP: {2}   |   EŞİK: {3}',
			[Std.string(rec.points), pointsReasonText(rec), Std.string(rec.milestones)]));

		// Hangi komboda kaç puan alındı
		var logText:String = '';
		if(rec.points_log != null && rec.points_log.length > 0)
		{
			var parts:Array<String> = [];
			for(entry in rec.points_log)
			{
				if(entry == null) continue;
				parts.push(Std.string(entry.combo) + 'x @' + Std.string(entry.at) + ' = +' + Std.string(entry.points));
			}
			logText = parts.join(', ');
			if(logText.length > 150) logText = logText.substr(0, 148) + '...';
		}
		if(logText.length > 0)
			lines.push(Language.getPhrase('match_records_detail_log', 'PUAN ALINAN ANLAR: {1}', [logText]));

		var syncLine:String = Language.getPhrase('match_records_detail_sync', 'SUPABASE: {1}', [statusText(rec)]);
		if(rec.sync_error != null && Std.string(rec.sync_error).length > 0)
			syncLine += ' -> ' + Std.string(rec.sync_error);
		lines.push(syncLine);

		return lines.join('\n');
	}

	function reloadData():Void
	{
		data = backend.MatchRecords.getMatches().copy();
		data.reverse(); // en yeni üstte

		for(row in rows)
		{
			grpRows.remove(row, true);
			row.destroy();
		}
		rows = [];

		if(curSelected >= data.length) curSelected = Math.max(0, data.length - 1);

		for (i in 0...data.length)
		{
			var row:FlxText = new FlxText(60, topY, FlxG.width - 120, buildRow(i, data[i]), 19);
			row.setFormat(Paths.font('vcr.ttf'), 19, rowColor(data[i]), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.scrollFactor.set();
			row.ID = i;
			rows.push(row);
			grpRows.add(row);
		}

		emptyTxt.visible = (data.length < 1);

		var pending:Int = backend.MatchRecords.pendingCount();
		summaryTxt.text = Language.getPhrase('match_records_summary', 'MAÇ: {1}   |   PUAN: {2}   |   BEKLEYEN: {3}',
			[data.length, backend.UserSession.points, pending]);

		configTxt.text = backend.MatchRecords.configSummary();
		var configured:Bool = backend.MatchRecords.isSupabaseConfigured();
		configTxt.color = configured ? 0xFF8CFF8C : 0xFFFF6B6B;

		updateRowPositions();
	}

	function updateRowPositions():Void
	{
		for (i in 0...rows.length)
		{
			var row:FlxText = rows[i];
			var diff:Int = i - curSelected;
			row.y = topY + diff * rowHeight;
			row.alpha = (diff == 0) ? 1 : 0.7;
			row.visible = (diff >= 0 && diff <= maxVisible);
		}

		detailTxt.text = (data.length > 0) ? buildDetail(data[curSelected]) : '';
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

		// Arka plandaki gönderim sonuçlarını işle
		backend.MatchRecords.tick();

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (FlxG.mouse.wheel != 0)
			changeSelection(-FlxG.mouse.wheel);

		// Tekrar gönder (senkronize et)
		if (controls.ACCEPT || touchPad.buttonA.justPressed)
		{
			backend.MatchRecords.retryNow();
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
			reloadData();
		}

		// Kayıtları yenile  (SHIFT + SIFIRLA -> puan haklarını sıfırla)
		if (controls.RESET || touchPad.buttonB.justPressed)
		{
			if (FlxG.keys.pressed.SHIFT && controls.RESET)
			{
				var cleared:Int = backend.MatchRecords.resetClaimed();
				FlxG.sound.play(Paths.sound('cancelMenu'), 0.7);
				trace('MatchRecords: ' + cleared + ' puan hakkı sıfırlandı');
			}
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
