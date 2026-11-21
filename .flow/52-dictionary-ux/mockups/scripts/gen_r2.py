import os
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..")+os.sep
BASE_CSS="""
:root{--accent:#2D6D4E;--warning:#F5A524;--text:#0B0F0D;--text2:#5C6C64;--bg:#FFFFFF;--surface:#F4F6F4;--line:#E2E6E3;--chrome:#ECEEEC;--sel:#DCEBE2;--destructive:#D70015;--blue:#0A6CFF}
*{box-sizing:border-box}
body{margin:0;background:#C9D1CC;font:13px -apple-system,"SF Pro Text",system-ui,sans-serif;color:var(--text);padding:24px}
.intro,.coverage{max-width:1500px;margin:0 auto 16px;background:var(--bg);border-radius:10px;padding:14px 24px}
.intro h1{font-size:17px;margin:0 0 8px}
.intro p{margin:4px 0;color:var(--text2);line-height:1.45}
.coverage{margin:16px auto 0;padding:12px 24px;color:var(--text2);font-size:12px;line-height:1.5}
.new{display:inline-block;background:#FFF1D6;color:#7A4C00;border-radius:4px;padding:0 6px;font-size:10px;font-weight:600;line-height:15px;vertical-align:middle;white-space:nowrap}
.row{max-width:1500px;margin:0 auto 16px;background:#E9EDEA;border-radius:10px;padding:14px 16px}
.label{font-weight:700;font-size:15px;margin:0 0 4px}
.diff{color:var(--text2);margin:0 0 4px;font-size:12px;line-height:1.45}
.diff b{color:var(--text)}
.win{background:var(--bg);border-radius:10px;box-shadow:0 12px 32px rgba(0,0,0,.25);overflow:hidden;display:flex;flex-direction:column;position:relative}
.titlebar{height:28px;background:var(--chrome);display:flex;align-items:center;padding:0 8px;gap:6px;border-bottom:1px solid var(--line);flex:none}
.dot{width:12px;height:12px;border-radius:50%}
.titlebar .t{flex:1;text-align:center;font-weight:600;font-size:12px;margin-right:50px}
.btn{border:1px solid #CDD3CF;background:#fff;border-radius:6px;padding:2px 8px;font-size:12px;white-space:nowrap;position:relative}
.btn.red{color:var(--destructive)}.btn.dis{color:#A8B0AB}
.sp{flex:1}
.seg{display:inline-flex;border:1px solid #CDD3CF;border-radius:6px;overflow:hidden;font-size:11px;background:#fff}
.seg span{padding:2px 8px;white-space:nowrap}.seg span.on{background:#E3E7E4;font-weight:600}
.chip{display:inline-flex;align-items:center;gap:4px;background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:0 4px 0 8px;margin:1px 4px 1px 0;font-size:12px;line-height:18px;white-space:nowrap}
.chip .x{color:var(--text2);font-size:10px;width:14px;text-align:center}
.chip.add{border-style:dashed;color:var(--accent);padding:0 8px}
mark{background:#FFE48A;color:inherit;border-radius:2px}
.caret{display:inline-block;width:1px;height:13px;background:#000;vertical-align:middle}
.mini{font-size:11px;color:var(--text2)}
"""
def dots(t): return '<div class="titlebar"><span class="dot" style="background:#FF5F57"></span><span class="dot" style="background:#FEBC2E"></span><span class="dot" style="background:#28C840"></span><span class="t">%s</span></div>'%t
CAR='<span class="caret"></span>'
NEW='<span class="new">NEW</span>'

# ======================= Board 1: pointer-r2 =======================
P_CSS="""
.frames{display:flex;align-items:flex-start;gap:8px;margin-top:10px}
.arrow{font-size:20px;color:#fff;flex:none;width:14px;text-align:center;text-shadow:0 1px 2px rgba(0,0,0,.3);align-self:center;margin-bottom:24px}
.cap{font-size:11px;color:var(--text2);margin:4px 2px 0;line-height:1.35;width:466px}
.scene{width:466px;height:410px;border-radius:8px;position:relative;overflow:hidden;background:linear-gradient(160deg,#5E9BB8 0%,#8DB8C4 35%,#B7C9B0 70%,#8B9B83 100%);box-shadow:0 2px 8px rgba(0,0,0,.25);flex:none}
.menubar{height:20px;background:rgba(240,244,246,.85);display:flex;align-items:center;gap:12px;padding:0 10px;font-size:11px;position:absolute;left:0;right:0;top:0;z-index:3}
.menubar .r{margin-left:auto}
.menubar .ic{display:inline-block;width:14px;height:12px;border-radius:3px;background:#222;vertical-align:middle}
.pop{position:absolute;right:58px;top:24px;width:350px;background:linear-gradient(#E6F0F7,#EEF2F5);border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.35);overflow:hidden;font-size:11px;z-index:2}
.pop .hd{padding:10px 14px 6px;display:flex;justify-content:space-between}.pop .hd b{font-size:12px}
.pop .modes{display:flex;margin:0 14px 8px;border-radius:6px;overflow:hidden;background:#DCE5EC}
.pop .modes span{flex:1;text-align:center;padding:3px 0}.pop .modes .on{background:var(--blue);color:#fff}
.pop .sec{padding:8px 12px;border-top:1px solid rgba(0,0,0,.08)}
.pop .tabs{display:flex;border-top:1px solid rgba(0,0,0,.1);background:rgba(255,255,255,.5)}
.pop .tabs>span{flex:1;text-align:center;padding:6px 0 5px;color:var(--text2);font-size:10px}.pop .tabs>.on{color:var(--blue)}
.pop .tabs i{display:block;font-style:normal;font-size:14px;line-height:15px}
.pop .btn{font-size:11px;padding:2px 8px;background:#F7F9FA;border-radius:5px}
.card{background:#fff;border:1.5px solid var(--blue);border-radius:8px;padding:8px 10px;box-shadow:0 0 0 3px rgba(10,108,255,.12)}
.card .ct{display:flex;align-items:center;gap:6px;margin-bottom:6px}
.card .ct b{font-size:11.5px}
.txt{font-size:12px;line-height:1.5}
.mk{background:#BCD4FF;border-radius:2px;box-shadow:0 0 0 1px #8DB3F5}
.hint{color:var(--text2);font-size:10px;margin-top:5px}
.inl{margin-top:8px;border-top:1px solid var(--line);padding-top:7px;position:relative}
.inl .r{display:flex;align-items:center;gap:8px;margin-bottom:5px}
.inl .k{width:92px;color:var(--text2);font-size:10.5px;flex:none}
.inl .hv{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:0 8px;line-height:18px}
.inl .in{flex:1;border:1px solid var(--blue);box-shadow:0 0 0 3px rgba(10,108,255,.25);border-radius:6px;padding:2px 8px;background:#fff;height:22px}
.conf{margin-top:8px;border-top:1px solid var(--line);padding-top:7px;color:#1E6B45;font-size:11px;line-height:1.4}
.conf a{color:var(--blue);margin-left:4px}
.fw{position:absolute;left:12px;top:30px;width:442px;height:360px;font-size:11px;z-index:1}
.fw .cols{display:flex;flex:1;min-height:0}
.fw .lst{width:140px;border-right:1px solid var(--line);background:#F7F8F7;flex:none;overflow:hidden}
.fw .lst .h{font-size:9.5px;letter-spacing:.04em;color:var(--text2);padding:7px 10px 3px}
.fw .li{padding:6px 10px;border-bottom:1px solid #EDF0ED;line-height:1.3}
.fw .li small{display:block;color:var(--text2);font-size:10px}
.fw .li.sel{background:var(--sel);box-shadow:inset 3px 0 0 var(--accent)}
.fw .main{flex:1;padding:12px 14px;overflow:hidden}
.fw .big{font-size:14px;line-height:1.55;margin:6px 0 4px}
.fw .ft{border-top:1px solid var(--line);padding:6px 12px;color:var(--text2);font-size:10px;display:flex;justify-content:space-between;background:#F7F8F7}
.pick{display:flex;align-items:center;justify-content:center;gap:8px;padding:8px;border-bottom:1px solid var(--line);background:#F7F8F7}
.pick .pp{border:1px solid #CDD3CF;background:#fff;border-radius:6px;padding:2px 10px;font-weight:600;font-size:11.5px}
.pick .ar{border:1px solid #CDD3CF;background:#fff;border-radius:6px;width:22px;text-align:center}
"""
def menubar(): return '<div class="menubar"><b>Dicticus</b><span>File</span><span>Edit</span><span>Window</span><span>Help</span><span class="r"><span class="ic"></span> &nbsp;Sat 21 Nov 12:40</span></div>'
def pop(body):
    return ('<div class="pop"><div class="hd"><b>Dicticus</b><span>⏻ &nbsp;⚙</span></div><div class="modes"><span class="on">Auto</span><span>Code</span><span>Prose</span><span>Default</span></div>'+body+
      '<div class="tabs"><span class="on"><i>◉</i>Home</span><span><i>▤</i>Dictionary</span><span><i>◷</i>History</span></div></div>')
def scene(inner): return '<div class="scene">'+menubar()+inner+'</div>'
def frame(sc,cap): return '<div>'+sc+'<div class="cap">'+cap+'</div></div>'
AR='<div class="arrow">▶</div>'
TEXT_P="Can you check whether mirror cove imports the timeline from the FlorDex export correctly?"
def marked(on, size=""):
    t=TEXT_P.replace("mirror cove",'<span class="mk">mirror cove</span>' if on else "mirror cove")
    return t
def fieldbox(typed):
    return ('<div class="inl"><span class="new" style="position:absolute;right:0;top:6px">NEW</span><div class="r"><span class="k">Heard as</span><span class="hv">“mirror cove”</span></div>'
      '<div class="r"><span class="k">Correct spelling</span><span class="in">'+('Miracove'+CAR if typed else CAR)+'</span></div><div class="hint" style="margin:0 0 0 100px">Return adds · Esc cancels</div></div>')
CONF='<div class="conf">✓ Added: “mirror cove” → <b>Miracove</b>. Applies from your next dictation.<a>Undo</a></div>'
HINT_A='<div class="hint">Select the words Dicticus got wrong '+NEW+'</div>'
def seq(frames, caps): return '<div class="frames">'+AR.join(frame(f,c) for f,c in zip(frames,caps))+'</div>'
STEP=["1 · Nothing marked yet","2 · Words marked, field open, “Miracove” typed","3 · After Return: confirmation line"]
def vrow(label,diff,cost,cons,frames,caps=STEP):
    return '<div class="row"><p class="label">'+label+'</p><p class="diff">'+diff+'</p><p class="diff">'+cost+'</p><p class="diff">'+cons+'</p>'+seq(frames,caps)+'</div>'
CONS="<b>Constraint:</b> the heard form comes from the polished text. The app’s post-cleanup dictionary pass applies user entries to the processed text, so an entry made from a polished word does work."

# A: popover
def a_body(step):
    txt=marked(step>=2)
    mid={1:HINT_A,2:fieldbox(True),3:CONF}[step]
    card=('<div class="card"><div class="ct"><b>Last dictation</b><span class="mini">· 12:14 · EN</span><span class="sp"></span><span class="btn" style="font-size:10px;padding:1px 6px">‹ earlier</span> '+NEW+'</div>'
          '<div class="txt">'+txt+'</div>'+mid+'<div style="margin-top:8px"><span class="btn">Copy</span></div></div>')
    return '<div class="sec" style="padding-top:4px"><span style="color:#2D8A4E">●</span> Ready · Press ⌃⇧S to dictate</div><div class="sec">'+card+'</div>'
A=vrow("A — In the popover","<b>Differs in:</b> the Home card is the place: titled “Last dictation · 12:14 · EN” with a blue outline so it is clear which dictation you are on. Its polished text can be marked in place, and a small “‹ earlier” control steps to older dictations. Revert to Raw is gone; Copy is the only button. No Add to Dictionary button, no sheet.",
 "<b>Cost:</b> medium (a markable text view in the popover that reports the marked range, an inline field, the step-back state). <b>Limit:</b> a 350 px wide popover, so long dictations get tall; no window. <b>Clicks:</b> 0 extra to reach it, then mark, type, Return.",CONS,
 [scene(pop(a_body(i))) for i in (1,2,3)])

# B: two columns
def lst(sel=0):
    items=[("12:14 · EN","Can you check whether mirror cove imports…"),("11:59 · EN","Send the Zornex logs to the dev channel…"),("09:19 · DE","Ich schicke dir die Rechnung von Vantelli…"),("Yesterday · EN","Quibbly is back in the build.")]
    return ''.join('<div class="li%s"><b>%s</b><small>%s</small></div>'%(" sel" if i==sel else "",t,s) for i,(t,s) in enumerate(items))
def b_win(step):
    txt=marked(step>=2)
    mid={1:'<div class="hint">Select the words Dicticus got wrong '+NEW+'</div>',2:fieldbox(True),3:CONF}[step]
    return ('<div class="win fw">'+dots("Fix a word")+'<div class="cols"><div class="lst"><div class="h">RECENT DICTATIONS</div>'+lst()+'</div>'
      '<div class="main"><div class="mini">Selected: 21 Nov 2026 · 12:14 · EN</div><div class="big">'+txt+'</div>'+mid+'</div></div>'
      '<div class="ft"><span>Esc closes</span><span><span class="btn" style="font-size:10px">Copy</span></span></div></div>')
B=vrow("B — Fix window, two columns","<b>Differs in:</b> one small window “Fix a word”. A list of recent dictations on the left, the last one preselected and highlighted; the chosen dictation large on the right, markable, with the field under it. Reached by one new item on the popover’s Home (“Fix a word…” beside Copy) or from the History tab.",
 "<b>Cost:</b> medium to large (new window, list, markable large text, inline field). <b>Room:</b> shows four dictations at once, so older ones are one click away. <b>Clicks:</b> 1 to open from the popover, then mark, type, Return.",CONS,
 [scene(b_win(i)) for i in (1,2,3)])

# C: picker header
def c_win(step):
    txt=marked(step>=2)
    mid={1:'<div class="hint" style="text-align:center">Select the words Dicticus got wrong '+NEW+'</div>',2:fieldbox(True),3:CONF}[step]
    return ('<div class="win fw" style="left:36px;width:394px;height:340px;top:36px">'+dots("Fix a word")+
      '<div class="pick"><span class="ar">‹</span><span class="pp">Last dictation · 12:14 · EN ▾</span><span class="ar">›</span></div>'
      '<div class="main" style="padding:16px 22px;flex:1"><div class="big" style="font-size:16px;line-height:1.6">'+txt+'</div>'+mid+'</div>'
      '<div class="ft"><span>Esc closes</span><span class="mini">1 of 12</span></div></div>')
C=vrow("C — Fix window, one column with a picker (my proposal)","<b>Differs in:</b> B without the list. The dictation fills the window; a picker in the header (‹ › and a menu with the recent ones, “Last dictation” on top) says which one you are on. Nothing competes with the text and the field, so it is the calmest of the three. Opened like B.",
 "<b>Cost:</b> medium (B’s window minus the list, plus a picker). <b>Trade-off:</b> older dictations are reached through the picker, not seen at once, but you only judge one dictation at a time anyway. <b>Clicks:</b> 1 to open, then mark, type, Return.",CONS,
 [scene(c_win(i)) for i in (1,2,3)])
html=('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Pointer round 2</title><style>'+BASE_CSS+P_CSS+'</style></head><body>'
'<div class="intro"><h1>Board 1 of 2, round 2: marking a word is the first half of the dictionary entry</h1>'
'<p><b>Question:</b> after a dictation with a misheard word, how should Dicticus lead you to the dictionary?</p>'
'<p><b>What changed since round 1:</b> the owner rejected all three variants. Asked for: “first of all see where I’m at, what’s the last transcription, which transcription did I just choose, and then I mark a word or a few words and just the marking starts the first half of the dictionary entry, and a text field will appear where I can add the corrected value.” So: no “Add to Dictionary…” button and no sheet; no Raw/Polished switch (you always judge the polished text) and no Revert to Raw; marking one word, or dragging or shift-clicking across a few, fills “Heard as” and opens an inline “Correct spelling” field under the text with the cursor in it. Return adds, Escape cancels, and a confirmation line with Undo follows.</p>'
'<p><b>Direction:</b> native macOS Sonoma/Tahoe window and popover, system font, dense list; signature element: the heard-as chips (here the “Heard as” chip in the inline field). Each variant is a 3-step sequence in its real frame. Anything the app does not have yet carries '+NEW+'. Invented names only; the confirmation never rewrites the past dictation text.</p></div>'
+A+B+C+
'<div class="coverage"><b>Covered:</b> three places for the pick, the inline field and the confirmation, each in three steps. <b>Left out:</b> dark mode, iOS, the History tab, empty state (no dictation yet), a very long dictation, keyboard-only marking, and what Escape does after the confirmation. The “Needs Permission” popover state is replaced by Ready. All three need a text view that reports the marked range, which plain SwiftUI text does not give today, so the build cost includes that.</div></body></html>')
open(OUT+"pointer-r2.html","w").write(html)

# ======================= Board 2: dictionary-window-r2 =======================
D_CSS="""
.pair{display:flex;gap:16px;margin-top:10px;align-items:flex-start}.pair>div{flex:none}
.dw{width:720px;height:520px}
.band{height:50px;display:flex;align-items:center;gap:12px;padding:0 14px;background:#F6F7F6;border-bottom:1px solid var(--line);flex:none}
.sf{display:flex;align-items:center;gap:7px;width:250px;height:30px;border-radius:15px;background:#fff;border:1px solid #CDD3CF;padding:0 8px 0 10px;font-size:13px;box-shadow:inset 0 1px 1px rgba(0,0,0,.04);flex:none}
.sf.q{border-color:var(--blue);box-shadow:0 0 0 3px rgba(10,108,255,.22)}
.sf svg{flex:none}.sf .ph{color:#9AA39E;flex:1}.sf .v{flex:1}
.sf .clr{width:15px;height:15px;border-radius:50%;background:#B9C0BC;color:#fff;font-size:9px;display:flex;align-items:center;justify-content:center}
.sf kbd{font:11px -apple-system,system-ui;color:#9AA39E}
.band .count{flex:1;text-align:right;color:var(--text2);font-size:12px;white-space:nowrap}
.expl{padding:4px 14px;font-size:11px;color:var(--text2);border-bottom:1px solid var(--line);flex:none}
.th{display:grid;grid-template-columns:150px 1fr;padding:3px 14px;font-size:11px;color:var(--text2);font-weight:600;border-bottom:1px solid var(--line);flex:none}
.body{flex:1;overflow:hidden;position:relative;min-height:0}
.tr{display:grid;grid-template-columns:150px 1fr;padding:5px 14px;align-items:start;border-bottom:1px solid #F0F2F0;height:34px;overflow:hidden}
.tr:nth-child(even){background:#FAFBFA}
.spell{font-weight:600}
.footer{height:44px;border-top:1px solid var(--line);display:flex;align-items:center;gap:6px;padding:0 14px;background:#F7F8F7;flex:none}
.footer .btn{padding:2px 7px;font-size:11.5px}
.empty{color:var(--text2);font-size:11px;padding:10px 14px;text-align:center}
.side{width:150px;background:#EEF1EF;border-right:1px solid var(--line);padding:8px 8px;flex:none;font-size:12.5px}
.side .h{font-size:10px;color:var(--text2);font-weight:600;padding:4px 8px}
.side .it{padding:4px 8px;border-radius:6px;display:flex;justify-content:space-between;align-items:center;gap:4px;margin-bottom:1px;white-space:nowrap}
.side .it.on{background:var(--accent);color:#fff}.side .it small{opacity:.7;font-size:10.5px}
.cols{display:flex;flex:1;min-height:0}.pane{flex:1;display:flex;flex-direction:column;min-width:0}
.ref{display:grid;grid-template-columns:1fr auto;gap:12px;white-space:nowrap;padding:3px 0;font-size:12px;border-bottom:1px solid #F0F2F0}
.ref span:first-child{overflow:hidden}.ref span:last-child{color:var(--text2)}
.rh{font-size:11px;font-weight:600;color:var(--text2);padding:7px 0 2px}
.refp{flex:1;overflow:hidden;padding:4px 18px;position:relative}
.reft{font-size:11px;color:var(--text2);padding:6px 0;line-height:1.4;white-space:normal}
.sb{position:absolute;right:3px;top:8px;width:5px;height:90px;border-radius:3px;background:#B9C0BC}
.tbtabs{height:46px;background:var(--chrome);display:flex;align-items:center;padding:0 8px;gap:6px;border-bottom:1px solid var(--line);flex:none}
.tbtabs .seg{margin:0 auto;font-size:12px}.tbtabs .seg span{padding:3px 12px}
.desk{width:720px;height:520px;border-radius:10px;position:relative;overflow:hidden;background:linear-gradient(160deg,#5E9BB8 0%,#8DB8C4 35%,#B7C9B0 70%,#8B9B83 100%);box-shadow:0 2px 8px rgba(0,0,0,.25);font-size:11px}
.mb{height:20px;background:rgba(240,244,246,.9);display:flex;gap:12px;align-items:center;padding:0 10px;position:absolute;left:0;right:0;top:0;z-index:3}
.stabs{background:var(--chrome);border-bottom:1px solid var(--line);display:flex;justify-content:center;gap:2px;padding:6px 8px 4px}
.stabs div{text-align:center;padding:3px 12px;border-radius:6px;font-size:10.5px;color:var(--text2);white-space:nowrap}
.stabs div i{display:block;font-style:normal;font-size:17px;line-height:20px}
.stabs div.on{background:#DADDDB;color:var(--text)}
.menu{position:absolute;background:#F3F5F6;border-radius:8px;box-shadow:0 8px 22px rgba(0,0,0,.35);padding:4px 0;font-size:12px;z-index:6;width:200px}
.menu div{padding:3px 12px;display:flex;justify-content:space-between}.menu .hl{background:var(--blue);color:#fff;border-radius:4px;margin:0 4px;padding:3px 8px}
.cap{font-size:11px;color:var(--text2);margin:4px 2px 0}
"""
MAG='<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="#7A8680" stroke-width="1.6" stroke-linecap="round"><circle cx="6" cy="6" r="4.2"/><path d="M9.3 9.3L12.5 12.5"/></svg>'
ROWS=[("Miracove",["mirra cove","mirror cove"]),("FlorDex",["flor dex","floor decks","FlorDecks"]),("Floravia",["flora via"]),("Zornex",["zor nex","zorn x"]),("Vantelli",["van telli","vantelly"]),("Quibbly",["quibly","quibbley"]),("Tarvilo",["tarvili"]),("Dexbra",["dexbra"]),("Pokavi",["pok avi","pokava"]),("Rulka",["rulka"])]
def hl(s,q):
    if q and q.lower() in s.lower():
        i=s.lower().index(q.lower()); return s[:i]+"<mark>"+s[i:i+len(q)]+"</mark>"+s[i+len(q):]
    return s
def rowhtml(sp,forms,q):
    ch=''.join('<span class="chip"><span>%s</span><span class="x">✕</span></span>'%hl(f,q) for f in forms)
    return '<div class="tr"><span class="spell">%s</span><span>%s<span class="chip add">+</span></span></div>'%(hl(sp,q),ch)
def rows(q):
    sel=[r for r in ROWS if (not q) or any(q.lower() in x.lower() for x in [r[0]]+r[1])]
    return ''.join(rowhtml(r[0],r[1],q) for r in sel)
def band(q,w=250):
    sf=('<div class="sf q" style="width:%dpx">'%w+MAG+'<span class="v">flor'+CAR+'</span><span class="clr">✕</span><kbd>⌘F</kbd></div>') if q else ('<div class="sf" style="width:%dpx">'%w+MAG+'<span class="ph">Search entries</span><kbd>⌘F</kbd></div>')
    cnt="2 of 183 words · 3 heard forms" if q else "183 words · 306 heard forms"
    return '<div class="band">'+sf+'<span class="count">'+cnt+'</span><span class="seg"><span class="on">Recent</span><span>A–Z</span></span></div>'
EXPL='<div class="expl">Dicticus replaces a heard form with its correct spelling in every dictation. '+NEW+'</div>'
TH='<div class="th"><span>Correct spelling</span><span>Heard as</span></div>'
def entries(q,footer,w=250):
    return band(q,w)+EXPL+TH+'<div class="body">'+rows(q)+('<div class="empty">No more matches</div>' if q else '')+'</div>'+footer
FOOT_A='<div class="footer"><span class="btn">＋ Add Entry</span><span class="btn">Edit</span><span class="sp"></span><span class="btn dis">Delete Selected</span><span class="btn red">Remove All</span><span class="btn">⇪ Export ▾</span><span class="btn">⇩ Import</span></div>'
FOOT_B='<div class="footer"><span class="btn" style="position:relative">＋ Add ▾<span class="new" style="position:absolute;top:-9px;right:-6px;font-size:9px;line-height:13px">NEW</span></span><span class="btn">Edit</span><span class="sp"></span><span class="btn dis">Delete Selected</span><span class="btn red">Remove All</span><span class="btn">⇪ Export ▾</span></div>'
FOOT_C=FOOT_B.replace('<span class="sp"></span>','<span style="color:var(--blue);font-size:11.5px;margin-left:6px">Spoken commands… '+NEW+'</span><span class="sp"></span>')
PUNCT=[("Always",None),("hyphen / Bindestrich","-"),("slash / Schrägstrich","/"),("backslash","\\"),("underscore / Unterstrich","_"),("asterisk / Sternchen","*"),("at sign / Klammeraffe","@"),("hash / Raute","#"),("caret","^"),("tilde","~"),("Between identifier words",None),("minus","-"),("dot","."),("colon",":"),("dollar","$"),("Punctuation commands",None),("open / close parenthesis · Klammer auf / zu","( )"),("open / close square bracket · eckige Klammer auf / zu","[ ]"),("dot dot dot · Punkt Punkt Punkt","..."),("question mark · Fragezeichen","?"),("exclamation mark · Ausrufezeichen","!"),("new line · neue Zeile / Zeilenumbruch","line break"),("semicolon",";")]
def refrows(items): return ''.join(('<div class="ref"><span>%s</span><span>%s</span></div>'%i) if i[1] is not None else '<div class="rh">%s</div>'%i[0] for i in items)
def refpane(title,h=None):
    return '<div style="padding:12px 18px 2px;font-size:15px;font-weight:700">'+title+'</div><div class="refp">'+refrows(PUNCT)+'<div class="sb"></div></div>'
def sidebar(on):
    its=[("Entries","183"),("Spoken Punctuation",""),("Voice Commands",""),("Starter Packs","")]
    return '<div class="side"><div class="h">DICTIONARY</div>'+''.join('<div class="it%s"><span>%s</span><small>%s</small></div>'%(" on" if n==on else "",n,c) for n,c in its)+'</div>'
def window(title,inner,w=720,h=520,extra="",tb=None):
    return '<div class="win" style="width:%dpx;height:%dpx">'%(w,h)+(tb if tb else dots(title))+inner+extra+'</div>'
# A
a_left=window("Custom Dictionary",'<div class="cols">'+sidebar("Entries")+'<div class="pane">'+entries("flor",FOOT_A,200)+'</div></div>')
a_right=window("Custom Dictionary",'<div class="cols">'+sidebar("Spoken Punctuation")+'<div class="pane">'+refpane("Spoken Punctuation")+'</div></div>')
# B
tb_b=lambda on:'<div class="tbtabs"><span class="dot" style="background:#FF5F57"></span><span class="dot" style="background:#FEBC2E"></span><span class="dot" style="background:#28C840"></span><span class="seg">'+''.join('<span class="%s">%s</span>'%("on" if n==on else "",n) for n in ("Entries","Spoken Punctuation","Voice Commands"))+'</span><span style="width:52px"></span></div>'
menu='<div class="menu" style="left:10px;bottom:48px"><div>Add Entry…</div><div>Import CSV…</div><div class="hl">Starter Packs <span>▸</span></div></div><div class="menu" style="left:206px;bottom:30px;width:150px"><div class="hl">Tech Terms</div><div>Brand Names</div><div>General Terms</div></div>'
b_left=window("",entries("flor",FOOT_B),tb=tb_b("Entries"))
b_right=window("",refpane("Spoken Punctuation"),tb=tb_b("Spoken Punctuation"))
# C
c_left=window("Custom Dictionary",entries("flor",FOOT_C))
sett='<div class="win" style="position:absolute;left:150px;top:78px;width:560px;height:368px;z-index:2">'+dots("Spoken Commands")+'<div class="stabs"><div><i>⌨</i>Hotkeys</div><div><i>✦</i>AI Cleanup</div><div><i>⚙</i>General</div><div class="on"><i>❝</i>Spoken Commands '+NEW+'</div><div><i>ⓘ</i>About</div></div><div class="refp" style="padding:4px 22px"><div class="rh" style="font-size:12px">SPOKEN PUNCTUATION</div>'+refrows(PUNCT[1:10])+'<div class="rh" style="font-size:12px;padding-top:12px">VOICE COMMANDS</div>'+refrows([("scratch that","deletes the last sentence"),("scratch the last word","deletes the last word"),("streich das","deletes the last sentence")])+'<div class="sb"></div></div></div>'
dict_behind='<div class="win" style="position:absolute;left:12px;top:34px;width:560px;height:470px;z-index:1">'+dots("Custom Dictionary")+entries("",FOOT_C.replace("Delete Selected","Delete").replace("＋ Add ▾"+'<span class="new" style="position:absolute;top:-9px;right:-6px;font-size:9px;line-height:13px">NEW</span>',"＋ Add ▾"),200)+'</div>'
c_right='<div class="desk"><div class="mb"><b>Dicticus</b><span>File</span><span>Edit</span><span>Window</span><span>Help</span><span style="margin-left:auto">Sat 21 Nov 12:40</span></div>'+dict_behind+sett+'</div>'
def vrow2(label,diff,cost,l,lc,r,rc):
    return '<div class="row"><p class="label">'+label+'</p><p class="diff">'+diff+'</p><p class="diff">'+cost+'</p><div class="pair"><div>'+l+'<div class="cap">'+lc+'</div></div><div>'+r+'<div class="cap">'+rc+'</div></div></div></div>'
rowA=vrow2("A — Sidebar","<b>Differs in:</b> a sidebar inside the dictionary window (Entries, Spoken Punctuation, Voice Commands, Starter Packs). Choosing an item swaps the whole content pane, so each page is fully visible and scrolls by itself; nothing floats and nothing splits the window.",
 "<b>Cost:</b> large (sidebar navigation container, four panes, the footer moves into the Entries pane). <b>Room for the list:</b> pane is 570 of 720 px wide but the full height, about 10 rows (34 px each). Entries show the search band and the footer; the other panes have neither.",
 a_left,"Entries pane, “flor” typed",a_right,"Spoken Punctuation pane (real rows); Voice Commands and Starter Packs are further items")
rowB=vrow2("B — Tabs in the title bar","<b>Differs in:</b> three tabs at the top of the window (Entries | Spoken Punctuation | Voice Commands) switch the whole window. Starter Packs move into an “Add ▾” menu in the footer next to Edit (Add Entry…, Import CSV…, Starter Packs ▸ Tech Terms / Brand Names / General Terms), and Import leaves the footer.",
 "<b>Cost:</b> small to medium (tab control, one menu, two reference panes). <b>Room for the list:</b> full width and about 10 rows; the title bar grows by about 16 px.",
 window("",entries("flor",FOOT_B),tb=tb_b("Entries"),extra=""),"Entries tab, “flor” typed",b_right,"Spoken Punctuation tab fills the window")
rowB=rowB.replace("<div class=\"cap\">Entries tab, “flor” typed</div>","<div class=\"cap\">Entries tab, “flor” typed</div>")
menu_win=window("",entries("",FOOT_B)+menu,tb=tb_b("Entries"))
rowC=vrow2("C — Spoken commands in Settings","<b>Differs in:</b> the dictionary window keeps only entries: search band, list, footer. Spoken Punctuation and Voice Commands become the tab “Spoken Commands” in the existing Settings window (Hotkeys, AI Cleanup, General, About), reached by a “Spoken commands…” link in the dictionary footer. Starter Packs sit in the “Add ▾” menu as in B.",
 "<b>Cost:</b> small to medium (one Settings tab, a footer link that opens it, the Add menu). <b>Room for the list:</b> full window, about 10 rows. Reference lives where other settings live, so it is not part of the list task at all.",
 c_left,"Dictionary window: entries only, “flor” typed",c_right,"Settings window with the new tab, opened from the footer link")
menurow='<div class="row"><p class="label">Add ▾ menu (used in B and C)</p><p class="diff">Starter Packs moved here, so the long Starter Packs paragraph is gone from the window. Import CSV sits in the same menu.</p><div class="pair"><div>'+menu_win+'</div></div></div>'
html2=('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Dictionary window round 2</title><style>'+BASE_CSS+D_CSS+'</style></head><body>'
'<div class="intro"><h1>Board 2 of 2, round 2: where do Spoken Punctuation, Voice Commands and Starter Packs live?</h1>'
'<p><b>Question:</b> where does the search field go, and where do the reference sections go so the list keeps its room?</p>'
'<p><b>What changed since round 1:</b> the owner liked the search row above the list but wanted it “more tidy and modern”, and rejected the bottom panel and the reference popover (“not a fan of half split screens or pop-ups that don’t seem to be able to be closed”). The Case Sensitive toggle is removed. So in every variant the search is a rounded field with a magnifier, a clear button once text is typed, and ⌘F, in one header band with the count and the Recent | A–Z control. The variants differ only in where the three reference areas live, each fully visible and never a split or a floating popup.</p>'
'<p><b>Direction:</b> native macOS Sonoma/Tahoe window, system font, dense list; signature element: the heard-as chips. Anything the app does not have yet carries '+NEW+'. Common to all: column headers “Correct spelling” and “Heard as”, one explanation line under the band. The Settings look in C follows the app’s own Settings window (icon tabs Hotkeys, AI Cleanup, General, About). Invented words only.</p></div>'
+rowA+rowB+rowC+menurow+
'<div class="coverage"><b>Covered:</b> the header band, the filtered state, and one reference page per variant. <b>Left out:</b> dark mode, iOS, the Voice Commands and Starter Packs pages (same shape as Spoken Punctuation), the explanation texts that sit under each reference list today, the empty-search state, the sidebar’s collapsed state and narrow widths. The sort control and count line stay as today; only the Case Sensitive toggle is gone.</div></body></html>')
open(OUT+"dictionary-window-r2.html","w").write(html2)
