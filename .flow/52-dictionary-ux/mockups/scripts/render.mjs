// Renders the 52 boards headless, drives the History prototype, saves screenshots, exits 1 on overflow.
// Run: PW=<path to playwright/index.js> node render.mjs
import path from "node:path";
const pw = (await import("file://" + process.env.PW)).default;
const dir = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const b = await pw.chromium.launch({ headless: true });
const p = await b.newPage({ viewport: { width: 1548, height: 900 } });
let fail = 0;
const check = async (name) => {
  const bad = await p.evaluate(() => {
    const out = [];
    if (document.documentElement.scrollWidth > document.documentElement.clientWidth) out.push("page h-scroll");
    document.querySelectorAll(".tr,.li,.dr,.form,.sheet,.raw,.toolbar,.footer").forEach(e => {
      if (e.scrollWidth > e.clientWidth + 1) out.push(e.className + ": " + e.textContent.slice(0, 40));
    });
    return out;
  });
  if (bad.length) { fail = 1; console.log(name, "OVERFLOW", bad); } else console.log(name, "ok");
};
await p.goto("file://" + dir + "/dictionary-rows.html");
await check("dictionary-rows");
await p.screenshot({ path: dir + "/dictionary-rows.png", fullPage: true });

await p.goto("file://" + dir + "/history-pick.html");
await check("history-pick initial");
await p.screenshot({ path: dir + "/history-pick-1-start.png", fullPage: true });
// A: pick "Molly do", add as Moleido
const A = p.locator("#winA");
await A.locator('.row[data-i="0"] .w', { hasText: /^Molly$/ }).click();
await A.locator('.row[data-i="0"] .w', { hasText: /^do$/ }).click({ modifiers: ["Shift"] });
await A.locator('.row[data-i="0"] .add').click();
await A.locator(".correct").fill("Moleido");
await check("history-pick A sheet");
await p.screenshot({ path: dir + "/history-pick-2-sheet-join.png", fullPage: true });
await A.locator(".save").click();
// B: select "cloud" and right-click
await p.evaluate(() => {
  const raw = document.querySelector('#winB .row[data-i="1"] .raw');
  const t = raw.firstChild, i = t.textContent.indexOf("cloud");
  const r = document.createRange(); r.setStart(t, i); r.setEnd(t, i + 5);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
const box = await p.locator('#winB .row[data-i="1"] .raw').boundingBox();
await p.mouse.click(box.x + 70, box.y + 14, { button: "right" });
await p.screenshot({ path: dir + "/history-pick-3-contextmenu.png", fullPage: true });
await p.locator("#winB .addctx").click();
await p.locator("#winB .correct").fill("Claude Code");
await check("history-pick B sheet");
await p.screenshot({ path: dir + "/history-pick-4-warnings.png", fullPage: true });
const txt = await p.locator("#winA .done").first().textContent();
console.log("A confirmation:", txt.trim());
await b.close();
process.exit(fail);
