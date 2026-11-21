import os
import os
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") + "/"
BASE_CSS="""
:root{--accent:#2D6D4E;--accent-soft:rgba(45,109,78,.12);--warning:#F5A524;--text:#0B0F0D;--text2:#5C6C64;--bg:#FFFFFF;--surface:#F4F6F4;--line:#E2E6E3;--chrome:#ECEEEC;--sel:#DCEBE2;--destructive:#D70015;--blue:#0A6CFF}
*{box-sizing:border-box}
body{margin:0;background:#C9D1CC;font:13px -apple-system,"SF Pro Text",system-ui,sans-serif;color:var(--text);padding:24px}
.intro,.coverage,.common{max-width:1500px;margin:0 auto 16px;background:var(--bg);border-radius:10px;padding:14px 24px}
.intro h1{font-size:17px;margin:0 0 8px}
.intro p,.common p{margin:4px 0;color:var(--text2);line-height:1.45}
.coverage{margin:16px auto 0;padding:12px 24px;color:var(--text2);font-size:12px;line-height:1.5}
.new{display:inline-block;background:#FFF1D6;color:#7A4C00;border-radius:4px;padding:0 6px;font-size:10px;font-weight:600;line-height:15px;vertical-align:middle;white-space:nowrap}
.label{font-weight:700;font-size:15px;margin:0 0 4px}
.diff{color:var(--text2);margin:0 0 4px;font-size:12px;line-height:1.45}
.diff b{color:var(--text)}
.win{background:var(--bg);border-radius:10px;box-shadow:0 12px 32px rgba(0,0,0,.25);overflow:hidden;display:flex;flex-direction:column;position:relative}
.titlebar{height:28px;background:var(--chrome);display:flex;align-items:center;padding:0 8px;gap:6px;border-bottom:1px solid var(--line);flex:none}
.dot{width:12px;height:12px;border-radius:50%}
.titlebar .t{flex:1;text-align:center;font-weight:600;font-size:12px;margin-right:50px}
.btn{border:1px solid #CDD3CF;background:#fff;border-radius:6px;padding:2px 9px;font-size:12px;white-space:nowrap;position:relative}
.btn.prim{background:var(--accent);color:#fff;border-color:var(--accent)}
.btn.red{color:var(--destructive)}
.btn.dis{color:#A8B0AB}
.sp{flex:1}
.seg{display:inline-flex;border:1px solid #CDD3CF;border-radius:6px;overflow:hidden;font-size:11px;background:#fff}
.seg span{padding:2px 8px}.seg span.on{background:#E3E7E4;font-weight:600}
.switch{width:26px;height:15px;border-radius:8px;background:#CDD3CF;position:relative;display:inline-block}
.switch:after{content:"";position:absolute;left:2px;top:2px;width:11px;height:11px;border-radius:50%;background:#fff}
.chip{display:inline-flex;align-items:center;gap:4px;background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:0 4px 0 8px;margin:1px 4px 1px 0;font-size:12px;line-height:18px;white-space:nowrap}
.chip .x{color:var(--text2);font-size:10px;width:14px;text-align:center}
.chip.add{border-style:dashed;color:var(--accent);padding:0 8px}
.chip.warn{border-color:var(--warning);background:#FFF7E8}
mark{background:#FFE48A;color:inherit;border-radius:2px}
.clk{position:absolute;right:-9px;top:-10px;width:18px;height:18px;border-radius:50%;background:#E5322D;color:#fff;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;box-shadow:0 1px 3px rgba(0,0,0,.4);z-index:9}
.clk.l{right:auto;left:-9px}
.mini{font-size:11px;color:var(--text2)}
"""
def win_dots(title):
    return '<div class="titlebar"><span class="dot" style="background:#FF5F57"></span><span class="dot" style="background:#FEBC2E"></span><span class="dot" style="background:#28C840"></span><span class="t">%s</span></div>'%title

# ---------------- Board 1: pointer ----------------
P_CSS="""
.row{max-width:1500px;margin:0 auto 16px;background:#E9EDEA;border-radius:10px;padding:14px 16px}
.frames{display:flex;align-items:center;gap:10px;margin-top:10px}
.arrow{font-size:22px;color:#fff;flex:none;width:14px;text-align:center;text-shadow:0 1px 2px rgba(0,0,0,.3)}
.fr{flex:none}
.cap{font-size:11px;color:var(--text2);margin:4px 2px 0;line-height:1.35;width:470px}
.scene{width:470px;height:375px;border-radius:8px;position:relative;overflow:hidden;background:linear-gradient(160deg,#5E9BB8 0%,#8DB8C4 35%,#B7C9B0 70%,#8B9B83 100%);box-shadow:0 2px 8px rgba(0,0,0,.25)}
.menubar{height:20px;background:rgba(240,244,246,.85);display:flex;align-items:center;gap:12px;padding:0 10px;font-size:11px;position:absolute;left:0;right:0;top:0;z-index:3}
.menubar .r{margin-left:auto;color:var(--text)}
.menubar .ic{display:inline-block;width:14px;height:12px;border-radius:3px;background:#222;position:relative}
.pop{position:absolute;right:10px;top:24px;width:350px;background:linear-gradient(#E6F0F7,#EEF2F5);border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.35);overflow:hidden;font-size:11px;z-index:2}
.pop .hd{padding:10px 14px 6px;display:flex;align-items:center;justify-content:space-between}
.pop .hd b{font-size:12px}
.pop .modes{display:flex;gap:0;margin:0 14px 8px;border-radius:6px;overflow:hidden;background:#DCE5EC;font-size:11px}
.pop .modes span{flex:1;text-align:center;padding:3px 0}.pop .modes .on{background:var(--blue);color:#fff}
.pop .sec{padding:8px 14px;border-top:1px solid rgba(0,0,0,.08)}
.pop .k{font-size:9.5px;letter-spacing:.04em;color:var(--text2);margin-bottom:5px}
.pop .tabs{display:flex;border-top:1px solid rgba(0,0,0,.1);background:rgba(255,255,255,.5)}
.pop .tabs>span{flex:1;text-align:center;padding:6px 0 5px;color:var(--text2);font-size:10px;position:relative}
.pop .tabs>.on{color:var(--blue)}
.pop .tabs i{display:block;font-style:normal;font-size:14px;line-height:15px}
.pop .btn{font-size:11px;padding:2px 7px;background:#F7F9FA;border-radius:5px}
.pop .btn.on{background:#fff}
.txt{font-size:11.5px;line-height:1.45;margin:0 0 7px}
.w{border-radius:3px;padding:0 1px}
.w.hov{background:#CFE0FF;outline:1px solid var(--blue)}
.tip{position:absolute;background:#2B2F2D;color:#fff;font-size:10px;padding:2px 6px;border-radius:4px;z-index:5;white-space:nowrap}
.hrow{display:flex;align-items:center;gap:8px;padding:5px 0;border-bottom:1px solid rgba(0,0,0,.07);font-size:11px}
.hrow .t{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#333}
.hw{position:absolute;left:18px;top:50px;width:430px;font-size:11px;z-index:1}
.hw .bd{padding:0 10px}
.hw .srch{margin:8px 10px;background:var(--surface);border-radius:6px;padding:4px 8px;color:var(--text2)}
.hw .ent{padding:6px 10px;border-bottom:1px solid var(--line)}
.hw .ent .d{color:var(--text2);font-size:10px}
.hw .raw{margin:6px 0 4px;line-height:1.5}
.hw .pick{background:#CFE0FF;border-radius:3px;outline:1px solid var(--blue)}
.hw .hint{color:var(--text2);font-size:10px}
.hw .ft{padding:5px 10px;color:var(--text2);font-size:10px;border-top:1px solid var(--line);display:flex}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.22);z-index:6}
.sheet{position:absolute;left:85px;top:70px;width:300px;background:#fff;border-radius:12px;box-shadow:0 10px 30px rgba(0,0,0,.4);padding:14px 16px;z-index:7;font-size:11px}
.sheet b{font-size:12px}
.sheet .lb{color:var(--text2);font-size:10px;margin:8px 0 3px}
.sheet .in{border:1px solid #CDD3CF;border-radius:6px;padding:4px 8px;background:#fff;height:24px}
.sheet .in.focus{border-color:var(--blue);box-shadow:0 0 0 3px rgba(10,108,255,.3)}
.sheet .act{display:flex;justify-content:flex-end;gap:8px;margin-top:14px}
.caret{display:inline-block;width:1px;height:13px;background:#000;vertical-align:middle}
.toast{position:absolute;left:18px;right:18px;bottom:16px;background:#fff;border-radius:8px;padding:7px 10px;font-size:11px;box-shadow:0 4px 14px rgba(0,0,0,.3);z-index:4}
.toast a{color:var(--blue);margin-left:6px}
"""
RAW_WORDS="can you check whether mirror cove imports the timeline from the flor dex export correctly?"
POLISHED="Can you check whether mirror cove imports the timeline from the FlorDex export correctly?"
def menubar(): return '<div class="menubar"><b>Dicticus</b><span>File</span><span>Edit</span><span>Window</span><span>Help</span><span class="r"><span class="ic"></span> &nbsp;Sat 21 Nov 12:40</span></div>'
def tabs(on):
    t=[("Home","◉"),("Dictionary","▤"),("History","◷")]
    return '<div class="tabs">'+''.join('<span class="%s" %s><i>%s</i>%s%s</span>'%("on" if n==on else "", 'style="position:relative"', g, n, CLK.get(n,"")) for n,g in t)+'</div>'
CLK={}
def pop(on,body):
    return ('<div class="pop"><div class="hd"><b>Dicticus</b><span>⏻ &nbsp;⚙</span></div><div class="modes"><span class="on">Auto</span><span>Code</span><span>Prose</span><span>Default</span></div>'+body+tabs(on)+'</div>')
def scene(inner,extra=""): return '<div class="scene">'+menubar()+inner+'</div>'
def sec_last(text_html,buttons,extra=""):
    return '<div class="sec"><div class="k">LAST TRANSCRIPTION</div>'+extra+'<p class="txt">'+text_html+'</p><div style="display:flex;gap:6px;flex-wrap:wrap">'+buttons+'</div></div>'
def hist_win(hint,pickword="mirror cove",new_hint=False):
    rawh=RAW_WORDS.replace("mirror cove",'<span class="pick">mirror cove</span>')
    hn='<span class="new">NEW</span> ' if new_hint else ''
    return ('<div class="win hw">'+win_dots("Transcription History")+'<div class="srch">Search history…</div>'
      '<div class="ent"><div class="d">21/11/2026, 12:14:22 PM &nbsp; <span style="color:#2B6CB0">EN</span> <span style="color:#A03BB0">Cleanup</span></div><div>'+POLISHED[:70]+'…</div>'
      '<div style="margin-top:5px"><span class="seg"><span class="on">Raw</span><span>Polished</span></span></div>'
      '<div class="raw">'+rawh+'</div><div style="display:flex;gap:8px;align-items:center"><span class="btn" style="font-size:10px;padding:1px 7px">Add to Dictionary…</span><span class="hint">“mirror cove”</span></div>'
      '<div class="hint" style="margin-top:4px">'+hn+hint+'</div></div>'
      '<div class="ent"><div class="d">21/11/2026, 11:59:22 AM</div><div>Send the Zornex logs to the dev channel before lunch.</div></div>'
      '<div class="ent"><div class="d">21/11/2026, 9:19:22 AM</div><div>Ich schicke dir die Rechnung von Vantelli heute Abend noch.</div></div>'
      '<div class="ft">3 entries</div></div>')
def sheet_frame(back,typed=False,clk=""):
    return scene(back+'<div class="dim"></div><div class="sheet"><b>Add to Dictionary</b><div class="lb">Heard as</div><div class="in">mirror cove</div><div class="lb">Correct spelling</div><div class="in focus">'+('Miracove' if typed else '<span class="caret"></span> <span style="color:#9AA39E">Type how it should be written</span>')+'</div><div class="act"><span class="btn">Cancel</span><span class="btn %s">Add</span></div></div>'%("prim" if typed else "dis"))
def frame(sc,cap): return '<div class="fr">'+sc+'<div class="cap">'+cap+'</div></div>'
ARROW='<div class="arrow">▶</div>'
CP='<span class="btn">Copy to Clipboard</span>'
RV='<span class="btn">↩ Revert to Raw</span>'
def variant(label,diff,cost,frames):
    return '<div class="row"><p class="label">'+label+'</p><p class="diff">'+diff+'</p><p class="diff">'+cost+'</p><div class="frames">'+ARROW.join(frames)+'</div></div>'

# Variant A
CLK.clear()
fixbtn='<span class="btn" style="border-color:#E0B96A;background:#FFF9EC">Fix a word… <span class="new">NEW</span><span class="clk">1</span></span>'
a1=scene(pop("Home",'<div class="sec" style="padding-top:4px"><span style="color:#2D8A4E">●</span> Ready · Press ⌃⇧S to dictate</div>'+sec_last(POLISHED,CP+RV+fixbtn)))
a2=scene(hist_win("Click the word Dicticus got wrong",new_hint=True).replace('<span class="pick">mirror cove</span>','<span class="pick" style="position:relative">mirror cove<span class="clk">2</span></span>'))
a3=sheet_frame('')
A=variant("A — “Fix a word…” button on Home","<b>Differs in:</b> the Home card gets a third button; it opens the History window with that dictation already expanded, Raw selected and a hint above the words.",
 "<b>Cost:</b> small (a button plus one call that opens History with an entry preselected). <b>Limit:</b> only the last dictation. <b>Clicks:</b> 2 from the open popover to the pick (Fix a word…, then the word).",
 [frame(a1,"1 · Popover, Home tab"),frame(a2,"2 · History window opens on that dictation, Raw selected"),frame(a3,"Add to Dictionary sheet (common to all)")])

# Variant B
CLK.clear()
rawtog='<div style="margin-bottom:6px"><span class="seg" style="position:relative"><span>Polished</span><span class="on">Raw</span><span class="new" style="margin:1px 4px">NEW</span><span class="clk" style="right:-14px">1</span></span></div>'
poli_toggle='<div style="margin-bottom:6px;position:relative;display:inline-block"><span class="seg" style="overflow:visible"><span class="on">Polished</span><span style="position:relative">Raw<span class="clk">1</span></span></span><span class="new" style="margin-left:4px">NEW</span></div>'
b1=scene(pop("Home",'<div class="sec" style="padding-top:4px"><span style="color:#2D8A4E">●</span> Ready · Press ⌃⇧S to dictate</div>'+sec_last(POLISHED,CP+RV,poli_toggle)))
words=RAW_WORDS.split(" ")
wh=[]
for i,w in enumerate(words):
    if w=="mirror": wh.append('<span class="w hov" style="position:relative">mirror<span class="clk">2</span><span class="tip" style="left:-4px;top:17px">Add to Dictionary…</span></span>')
    else: wh.append('<span class="w">%s</span>'%w)
b2=scene(pop("Home",'<div class="sec" style="padding-top:4px"><span style="color:#2D8A4E">●</span> Ready · Press ⌃⇧S to dictate</div>'+sec_last(' '.join(wh),CP+RV,'<div style="margin-bottom:6px"><span class="seg"><span>Polished</span><span class="on">Raw</span></span> <span class="mini">&nbsp;<span class="new">NEW</span> words light up on hover</span></div>')))
b3=sheet_frame(pop("Home",'<div class="sec">'+POLISHED[:40]+'…</div>'))
B=variant("B — pick the word on the Home card itself","<b>Differs in:</b> no second window. A Polished | Raw switch on the card shows the raw words; each word lights up on hover and a click opens the Add to Dictionary sheet with “Heard as” filled in.",
 "<b>Cost:</b> medium (a new word-pick control inside the popover: wrapping words, hover state, selection). <b>Limit:</b> only the last dictation. <b>Clicks:</b> 2 (Raw, then the word); 1 if the card opened on Raw by default.",
 [frame(b1,"1 · Popover, Home tab"),frame(b2,"2 · Raw view, hovered word"),frame(b3,"Add to Dictionary sheet, “Heard as” filled")])

# Variant C
CLK.clear(); CLK["History"]='<span class="clk" style="right:18px;top:0">1</span>'
def hrow(t,fix,clk=""):
    return '<div class="hrow"><span class="t">'+t+'</span><span class="btn" style="position:relative">Fix <span class="new">NEW</span>'+clk+'</span><span class="btn">Copy</span></div>' if fix else ''
hist_body='<div class="sec"><div class="k">RECENT</div>'+hrow("Can you check whether mirror cove imports the…",1,'<span class="clk">2</span>')+hrow("Send the Zornex logs to the dev channel before…",1)+hrow("Ich schicke dir die Rechnung von Vantelli heute…",1)+'<div class="hrow" style="border:0"><span class="t">🔍 &nbsp;Open Full History…</span><span>›</span></div></div>'
c1=scene(pop("History",hist_body))
CLK.clear()
c2=scene(hist_win("Click a word; shift-click to extend the pick.").replace('<span class="pick">mirror cove</span>','<span class="pick" style="position:relative">mirror cove<span class="clk">3</span></span>'))
c3=sheet_frame('')
C=variant("C — “Fix” button on every History row","<b>Differs in:</b> each row of the popover’s History tab gets a small Fix button beside Copy; it opens the History window with that row expanded on Raw.",
 "<b>Cost:</b> small (one button per row, same call as A). <b>Limit:</b> needs the History tab first, so one click more than A. <b>Clicks:</b> 3 (History tab, Fix, the word). <b>Gain:</b> reaches older dictations, not just the last one.",
 [frame(c1,"1 · Popover, History tab"),frame(c2,"2 · History window, that row expanded on Raw"),frame(c3,"Add to Dictionary sheet (common to all)")])

common_sheet=sheet_frame('',typed=False)
toast=scene('<div class="win hw" style="top:50px">'+win_dots("Transcription History")+'<div class="ent" style="padding:10px"><div class="d">21/11/2026, 12:14:22 PM</div><div>Can you check whether mirror cove imports the timeline…</div></div><div class="ent"><div class="d">21/11/2026, 11:59:22 AM</div><div>Send the Zornex logs to the dev channel before lunch.</div></div><div style="height:90px"></div></div><div class="toast"><span class="new">NEW</span> &nbsp;Added: “mirror cove” → <b>Miracove</b>. Applies from your next dictation.<a>Undo</a></div>')
html='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Pointer to the dictionary</title><style>'''+BASE_CSS+P_CSS+'''</style></head><body>
<div class="intro"><h1>Board 1 of 2: after a misheard word, how should Dicticus lead you to the dictionary?</h1>
<p><b>Question:</b> after a dictation with a misheard word, how should Dicticus lead you to the dictionary? Today the only route is popover, History tab, Open Full History…, expand the row by its unlabelled chevron, click the word, Add to Dictionary… (about 7 clicks).</p>
<p><b>Direction:</b> native macOS Sonoma/Tahoe window and popover, system font, dense list; signature element: the heard-as chips. Each variant is drawn in its real frame (popover open under the menu bar on the desktop) as a short sequence. Red numbers are clicks, counted from the open popover. Anything the app does not have yet carries <span class="new">NEW</span>.</p>
<p><b>Example:</b> the last dictation heard “mirror cove” where you meant Miracove (invented names only). The same dictation is used in all three rows.</p></div>
'''+A+B+C+'''
<div class="common"><p class="label">Common to all</p><p class="diff">The Add to Dictionary sheet opens with the cursor already in “Correct spelling” (today the cursor starts in “Heard as”). After Add, a line confirms the entry and offers Undo.</p>
<div class="frames">'''+frame(common_sheet,"Sheet: cursor in Correct spelling, Add disabled until typed")+ARROW+frame(toast,"After Add: “Added: … Applies from your next dictation. Undo”")+'''</div></div>
<div class="coverage"><b>Covered:</b> three ways to reach the pick from the popover, the sheet, and the confirmation line. <b>Left out:</b> dark mode, the Dictionary tab, iOS, the exact popover for the Needs Permission state (Ready shown instead), keyboard routes, and what happens when the last dictation has no raw text (the button would be disabled). Click counts exclude opening the popover from the menu bar. Option B assumes the card starts on Polished; starting on Raw would remove one click but hides the cleaned text.</div>
</body></html>'''
open(OUT+"pointer.html","w").write(html)

# ---------------- Board 2: dictionary window ----------------
D_CSS="""
.row{max-width:1500px;margin:0 auto 16px;background:#E9EDEA;border-radius:10px;padding:14px 16px}
.pair{display:flex;gap:16px;margin-top:10px;align-items:flex-start}
.pair>div{flex:none}
.dw{width:720px;height:520px}
.toolbar{height:40px;display:flex;align-items:center;padding:0 14px;gap:8px;border-bottom:1px solid var(--line);background:#F7F8F7;flex:none;font-size:12px}
.toolbar .count{flex:1;text-align:center;color:var(--text2)}
.search{border:1px solid #CDD3CF;border-radius:6px;background:#fff;padding:2px 8px;width:150px;font-size:12px;color:var(--text);display:flex;justify-content:space-between;position:relative}
.search i{font-style:normal;color:var(--text2);font-size:10px;padding-top:2px}
.searchrow{padding:6px 14px;background:#F7F8F7;border-bottom:1px solid var(--line);flex:none}
.searchrow .search{width:100%}
.expl{padding:4px 14px;font-size:11px;color:var(--text2);border-bottom:1px solid var(--line);flex:none;background:#fff}
.th{display:grid;grid-template-columns:150px 1fr;padding:3px 14px;font-size:11px;color:var(--text2);font-weight:600;border-bottom:1px solid var(--line);flex:none}
.body{flex:1;overflow:hidden;position:relative;min-height:0}
.tr{display:grid;grid-template-columns:150px 1fr;padding:5px 14px;align-items:start;border-bottom:1px solid #F0F2F0;height:34px;overflow:hidden}
.tr:nth-child(even){background:#FAFBFA}
.spell{font-weight:600}
.footer{height:44px;border-top:1px solid var(--line);display:flex;align-items:center;gap:7px;padding:0 14px;background:#F7F8F7;flex:none}
.empty{color:var(--text2);font-size:11px;padding:10px 14px;text-align:center}
.bpanel{flex:none;border-top:1px solid var(--line);background:#F7F8F7}
.bpanel .bar{height:28px;display:flex;align-items:center;justify-content:center;gap:0;padding:0 14px}
.bpanel .scroll{max-height:152px;height:152px;overflow:hidden;background:#fff;border-top:1px solid var(--line);padding:4px 14px;position:relative}
.ref{display:grid;grid-template-columns:1fr auto;gap:12px;white-space:nowrap;padding:3px 0;font-size:11.5px;border-bottom:1px solid #F0F2F0}
.ref span:first-child{color:var(--text);overflow:hidden}.ref span:last-child{color:var(--text2)}
.sb{position:absolute;right:3px;top:8px;width:5px;height:60px;border-radius:3px;background:#B9C0BC}
.popref{position:absolute;right:20px;bottom:50px;width:330px;height:260px;background:#fff;border-radius:10px;box-shadow:0 10px 30px rgba(0,0,0,.35);border:1px solid #CDD3CF;z-index:5;overflow:hidden;font-size:12px}
.popref:after{content:"";position:absolute;right:62px;bottom:-6px;width:12px;height:12px;background:#fff;transform:rotate(45deg);border-right:1px solid #CDD3CF;border-bottom:1px solid #CDD3CF}
.popref .ph{padding:8px 12px;border-bottom:1px solid var(--line);display:flex;justify-content:center}
.popref .pb{padding:2px 12px;height:200px;overflow:hidden;position:relative}
.desk{width:720px;height:520px;border-radius:10px;position:relative;overflow:hidden;background:linear-gradient(160deg,#5E9BB8 0%,#8DB8C4 35%,#B7C9B0 70%,#8B9B83 100%);box-shadow:0 2px 8px rgba(0,0,0,.25);font-size:11px}
.mb{height:20px;background:rgba(240,244,246,.9);display:flex;gap:12px;align-items:center;padding:0 10px;position:absolute;left:0;right:0;top:0;z-index:3}
.dd{position:absolute;left:176px;top:20px;width:190px;background:#F3F5F6;border-radius:6px;box-shadow:0 6px 18px rgba(0,0,0,.35);padding:4px 0;z-index:4}
.dd div{padding:3px 12px}.dd .hl{background:var(--blue);color:#fff}
.pp{position:absolute;right:10px;top:26px;width:330px;background:linear-gradient(#E6F0F7,#EEF2F5);border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.35);overflow:hidden;z-index:2}
.pp .sec{padding:8px 14px;border-top:1px solid rgba(0,0,0,.08)}
.pp .tabs{display:flex;border-top:1px solid rgba(0,0,0,.1);background:rgba(255,255,255,.5)}
.pp .tabs span{flex:1;text-align:center;padding:5px 0;color:var(--text2);font-size:10px}.pp .tabs .on{color:var(--blue)}
.pp .btn{font-size:11px;padding:2px 8px;background:#F7F9FA;border-radius:5px;position:relative}
.cap{font-size:11px;color:var(--text2);margin:4px 2px 0}
.nb{position:absolute;top:-9px;right:-6px;font-size:9px;line-height:13px}
.footer .btn{padding:2px 7px;font-size:11.5px}.footer{gap:6px}
"""
ROWS=[("Miracove",["mirra cove","mirror cove"],0),("FlorDex",["flor dex","floor decks","FlorDecks"],0),("Floravia",["flora via"],0),("Zornex",["zor nex","zorn x"],0),("Vantelli",["van telli","vantelly"],0),("Quibbly",["quibly","quibbley"],0),("Tarvilo",["tarvili"],0),("Dexbra",["dexbra"],0),("Pokavi",["pok avi","pokava"],0),("Rulka",["rulka"],0)]
def hl(s,q):
    if q and q.lower() in s.lower():
        i=s.lower().index(q.lower()); return s[:i]+"<mark>"+s[i:i+len(q)]+"</mark>"+s[i+len(q):]
    return s
def rowhtml(sp,forms,q=""):
    ch=''.join('<span class="chip"><span>%s</span><span class="x">✕</span></span>'%hl(f,q) for f in forms)
    return '<div class="tr"><span class="spell">%s</span><span>%s<span class="chip add">+</span></span></div>'%(hl(sp,q),ch)
def rows(q="",limit=10):
    sel=[r for r in ROWS if (not q) or any(q.lower() in x.lower() for x in [r[0]]+r[1])]
    out=''.join(rowhtml(r[0],r[1],q) for r in sel[:limit])
    return out
def count(q): return "2 of 183 words · 3 heard forms" if q else "183 words · 306 heard forms"
def toolbar(q,search):
    s=('<span class="search">%s<i>⌘F</i></span>'%('<span>flor<span style="display:inline-block;width:1px;height:12px;background:#000;vertical-align:middle"></span></span>' if q else '<span style="color:#9AA39E">Search</span>')) if search else ''
    s+=''
    return '<div class="toolbar"><span>Case Sensitive</span><span class="switch"></span><span class="count">'+count(q)+'</span><span class="seg"><span class="on">Recent</span><span>A–Z</span></span>'+(s.replace('class="search"','class="search"')+'<span class="new">NEW</span>' if search else '')+'</div>'
EXPL='<div class="expl">Dicticus replaces a heard form with its correct spelling in every dictation. <span class="new">NEW</span></div>'
TH='<div class="th"><span>Correct spelling</span><span>Heard as</span></div>'
def foot(kind):
    base='<span class="btn prim" style="background:#fff;color:var(--text);border-color:#CDD3CF">＋ Add Entry</span><span class="btn">Edit</span>'
    if kind=="A": base+='<span class="btn">Starter Packs ▾<span class="new nb">NEW</span></span><span class="btn">Reference<span class="new nb">NEW</span></span>'
    return '<div class="footer">'+base+'<span class="sp"></span><span class="btn dis">Delete Selected</span><span class="btn red">Remove All</span><span class="btn">⇪ Export ▾</span><span class="btn">⇩ Import</span></div>'
def window(kind,q,extra_list="",bottom="",searchrow="",overlay=""):
    search = kind in("A","C")
    return ('<div class="win dw">'+win_dots("Custom Dictionary")+toolbar(q,search)+EXPL+searchrow+TH+'<div class="body">'+rows(q)+(('<div class="empty">No more matches</div>') if q else '')+overlay+'</div>'+bottom+foot(kind)+'</div>')
def refrows(items): return ''.join(('<div class="ref"><span>%s</span><span>%s</span></div>'%i) if i[1] is not None else '<div style="font-size:11px;font-weight:600;color:var(--text2);padding:5px 0 2px">%s</div>'%i[0] for i in items)
PUNCT=[("Always",None),("hyphen / Bindestrich","-"),("slash / Schrägstrich","/"),("backslash","\\"),("underscore / Unterstrich","_"),("asterisk / Sternchen","*"),("at sign / Klammeraffe","@"),("hash / Raute","#"),("caret","^"),("tilde","~"),("Between identifier words",None),("minus","-"),("dot","."),("colon",":"),("dollar","$"),("Punctuation commands",None),("open / close parenthesis · Klammer auf / zu","( )"),("open / close square bracket · eckige Klammer auf / zu","[ ]"),("dot dot dot · Punkt Punkt Punkt","..."),("question mark · Fragezeichen","?"),("exclamation mark · Ausrufezeichen","!"),("new line · neue Zeile / Zeilenumbruch","line break"),("semicolon",";")]
VOICE=[("scratch that","deletes the last sentence"),("new line","line break"),("select all","selects the field text")]
def segbar(on):
    names=["Starter Packs","Spoken Punctuation","Voice Commands"]
    return '<span class="seg">'+''.join('<span class="%s">%s</span>'%("on" if n==on else "",n) for n in names)+'</span>'

# Variant A
a_left=window("A","flor")
pop_ref='<div class="popref"><div class="ph"><span class="seg"><span class="on">Spoken Punctuation</span><span>Voice Commands</span></span></div><div class="pb">'+refrows(PUNCT)+'<div class="sb"></div></div></div>'
a_right=window("A","",overlay=pop_ref)
# Variant B
sr='<div class="searchrow"><span class="search"><span><span style="color:#9AA39E">Search dictionary…</span></span><i>⌘F</i></span></div>'
sr_q='<div class="searchrow"><span class="search"><span>flor<span style="display:inline-block;width:1px;height:12px;background:#000;vertical-align:middle"></span></span><i>⌘F</i></span></div>'
bp_closed='<div class="bpanel"><div class="bar">'+segbar(None)+'<span class="new" style="margin-left:8px">NEW</span><span class="mini" style="margin-left:8px">click a tab to open, click again to close</span></div></div>'
bp_open='<div class="bpanel"><div class="bar">'+segbar("Spoken Punctuation")+'</div><div class="scroll">'+refrows(PUNCT)+'<div class="sb"></div></div></div>'
b_left=window("B","flor",searchrow=sr_q,bottom=bp_closed)
b_right=window("B","",searchrow=sr,bottom=bp_open)
# Variant C
c_left=window("C","flor")
ddmenu='<div class="dd"><div>Dicticus Help</div><div class="hl">Dictation Reference… <span class="new">NEW</span></div><div>Release Notes</div></div>'
c_right=('<div class="desk"><div class="mb"><b>Dicticus</b><span>File</span><span>Edit</span><span>Window</span><span style="background:var(--blue);color:#fff;padding:0 6px;border-radius:3px">Help</span><span style="margin-left:auto">Sat 21 Nov 12:40</span></div>'+ddmenu+
 '<div class="pp"><div class="sec" style="border:0;padding-top:10px"><b>Dicticus</b></div><div class="sec"><div style="font-size:9.5px;color:var(--text2);display:flex;justify-content:space-between"><span>CUSTOM DICTIONARY</span><span>250 entries</span></div><div style="text-align:center;margin:8px 0"><span class="btn">+ Add Entry</span></div><div style="text-align:center;margin:6px 0"><span class="btn">Manage Full Dictionary…</span> </div><div style="text-align:center;margin:6px 0"><span class="btn">Dictation Reference… </span> <span class="new">NEW</span></div></div><div class="tabs"><span>Home</span><span class="on">Dictionary</span><span>History</span></div></div>'
 '<div class="win" style="position:absolute;left:18px;top:200px;width:330px;height:300px;z-index:1">'+win_dots("Dictation Reference")+'<div style="padding:8px;text-align:center;border-bottom:1px solid var(--line)">'+segbar("Spoken Punctuation").replace('<span class="">Starter Packs</span>','')+'</div><div style="padding:2px 12px;overflow:hidden;flex:1;position:relative">'+refrows(PUNCT)+'<div class="sb"></div></div></div></div>')
def vrow(label,diff,cost,l,lcap,r,rcap):
    return '<div class="row"><p class="label">'+label+'</p><p class="diff">'+diff+'</p><p class="diff">'+cost+'</p><div class="pair"><div>'+l+'<div class="cap">'+lcap+'</div></div><div>'+r+'<div class="cap">'+rcap+'</div></div></div></div>'
rowA=vrow("A — search in the toolbar, reference in a footer popover","<b>Differs in:</b> search sits top right in the toolbar (⌘F focuses it); Starter Packs become a menu button in the footer; Spoken Punctuation and Voice Commands move into a Reference button that opens a popover with its own scroll. The list takes everything that is left. The footer is tight at 720 pt: Export and Import stay, with slightly smaller buttons, so everything fits without a new menu.",
 "<b>Room for the list:</b> full, about 10 rows. <b>Cost:</b> medium (footer buttons, popover, search). Nothing is squeezed, because the reference content never lives in the window.",a_left,"Query “flor” typed: FlorDex and Floravia match",a_right,"No query: about 10 rows; Reference popover open")
rowB=vrow("B — search row above the list, collapsed reference panel below it","<b>Differs in:</b> search is a full-width row above the list (like History’s “Search history…”); under the list a bottom panel with three tabs (Starter Packs | Spoken Punctuation | Voice Commands), collapsed by default, at most 180 px tall, scrolling inside.",
 "<b>Room for the list:</b> about 8 rows closed, about 4 with a panel open (the panel is capped, so the window never stops responding, but the list does shrink). <b>Cost:</b> medium (tabbed panel with capped height).",b_left,"Query “flor” typed, panel collapsed",b_right,"No query, Spoken Punctuation open: the panel stops at 180 px")
rowC=vrow("C — search in the toolbar, reference in its own window","<b>Differs in:</b> search as in A; Starter Packs and the reference sections leave the dictionary window for a separate “Dictation Reference” window, opened from a button on the popover’s Dictionary tab and from the Help menu. The dictionary window holds only list and footer. Starter Packs go with it, so importing a pack is one window away.",
 "<b>Room for the list:</b> full, about 10 rows. <b>Cost:</b> larger (new window, a Help menu item, a popover button). Reference stays open next to the list for reading while you edit.",c_left,"Query “flor” typed: the window is just list and footer",c_right,"Where the Dictation Reference window opens from")
html2='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Dictionary window layout</title><style>'''+BASE_CSS+D_CSS+'''.caret{}</style></head><body>
<div class="intro"><h1>Board 2 of 2: where does the search field go, and where do the reference sections go so the list keeps its room?</h1>
<p><b>Today:</b> the window stacks list, footer buttons, Starter Packs with a long paragraph, and two collapsible sections (Spoken Punctuation, Voice Commands) that do not scroll. Opening Spoken Punctuation squeezes the list, and the owner reported that the window stops responding.</p>
<p><b>Direction:</b> native macOS Sonoma/Tahoe window and popover, system font, dense list; signature element: the heard-as chips. Each variant shows the full window with the query “flor” typed (left) and a second state (right) that shows the room the list keeps. Anything the app does not have yet carries <span class="new">NEW</span>.</p>
<p><b>Common to all three:</b> column headers “Correct spelling” and “Heard as”, footer button “Add Entry”, and one explanation line under the toolbar. The count line follows the filter (“2 of 183 words”). Invented words only.</p></div>
'''+rowA+rowB+rowC+'''<div class="coverage"><b>Covered:</b> search placement, where Starter Packs, Spoken Punctuation and Voice Commands live, and the effect on list height. <b>Left out:</b> dark mode, iOS, the open Starter Packs menu in A, the Voice Commands tab content, the History window’s own layout, narrow window widths (the footer in A is the tightest at about 700 pt), and the behaviour when a search matches nothing. The unfiltered rows beyond ten scroll as they do today.</div></body></html>'''
open(OUT+"dictionary-window.html","w").write(html2)
