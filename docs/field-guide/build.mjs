// Builds "Claude-Viper's Visual Field Guides Present: You and Your Pod!" from pages/*.html.
//
//   node docs/field-guide/build.mjs                 HTML + PDF + overflow check
//   node docs/field-guide/build.mjs --shots 1,5,9   also screenshots of those pages (scratch/)
//   node docs/field-guide/build.mjs --html          HTML only (no browser)
//   ONLY=00,10-gate OUT_DIR=/tmp/x node ...          build just the page files starting with those prefixes,
//                                                    into another folder (for working on a few chapters)
//
// Each pages/*.html file holds one or more <section class="page theme-x" data-zone="GATE ZONE"
// data-toc="Title|Subtitle" data-tocgroup="gate|stream|bonus">...</section>. The build adds the
// top strip, the footer with the page number, inline pixel sprites and the contents page.
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { SPRITES, PALETTE } from "./sprites.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const htmlOnly = args.includes("--html");
const shotsArg = args.indexOf("--shots") >= 0 ? args[args.indexOf("--shots") + 1] : "";

// ---------- pixel sprites ----------
function spriteSvg(grid, px, pal) {
  const rows = grid.replace(/^\n+|\s+$/g, "").split("\n").map((r) => r.trimEnd());
  const indent = Math.min(...rows.filter((r) => r.trim()).map((r) => r.match(/^ */)[0].length));
  const lines = rows.map((r) => r.slice(indent));
  const w = Math.max(...lines.map((r) => r.length));
  const h = lines.length;
  let rects = "";
  lines.forEach((row, y) => {
    for (let x = 0; x < row.length; ) {
      const ch = row[x];
      if (ch === "." || ch === " ") { x++; continue; }
      let run = 1;
      while (row[x + run] === ch) run++;
      const fill = pal[ch];
      if (!fill) throw new Error(`sprite colour '${ch}' has no palette entry`);
      rects += `<rect x="${x}" y="${y}" width="${run}" height="1" fill="${fill}"/>`;
      x += run;
    }
  });
  return `<svg class="sprite" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w * px}" height="${h * px}">${rects}</svg>`;
}

function renderSprites(html) {
  return html.replace(/<pre class="sprite"([^>]*)>([\s\S]*?)<\/pre>/g, (_, attrs, body) => {
    const get = (k) => (attrs.match(new RegExp(`data-${k}="([^"]*)"`)) || [])[1];
    const px = Number(get("px") || 6);
    const pal = { ...PALETTE };
    (get("pal") || "").split(",").filter(Boolean).forEach((kv) => { const [k, v] = kv.split(":"); pal[k.trim()] = v.trim(); });
    const name = get("name");
    const grid = name ? SPRITES[name] : body;
    if (!grid) throw new Error(`unknown sprite '${name}'`);
    return spriteSvg(grid, px, pal);
  });
}

// ---------- pages ----------
const pageDir = join(here, "pages");
const only = (process.env.ONLY || "").split(",").filter(Boolean);
const outDir = process.env.OUT_DIR || here;
mkdirSync(outDir, { recursive: true });
const files = readdirSync(pageDir).filter((f) => f.endsWith(".html") && (!only.length || only.some((p) => f.startsWith(p)))).sort();
const sections = [];
for (const f of files) {
  const src = readFileSync(join(pageDir, f), "utf8");
  const re = /<section\s+class="page([^"]*)"([^>]*)>([\s\S]*?)<\/section>/g;
  let m, n = 0;
  while ((m = re.exec(src))) { sections.push({ file: f, cls: m[1], attrs: m[2], inner: m[3] }); n++; }
  if (!n) console.warn(`warning: ${f} has no <section class="page">`);
}

const toc = [];
const out = sections.map((s, i) => {
  const no = i + 1;
  const attr = (k) => (s.attrs.match(new RegExp(`data-${k}="([^"]*)"`)) || [])[1];
  const zone = attr("zone") || "FIELD GUIDE";
  const t = attr("toc");
  const id = `p${no}`;
  if (t) { const [title, sub] = t.split("|"); toc.push({ no, id, title, sub: sub || "", group: attr("tocgroup") || "" }); }
  return `<section class="page${s.cls}" id="${id}" data-file="${s.file}">
<div class="strip"><span class="zone">${zone}</span><span class="mag">VIPER VISION</span><span>YOU AND YOUR POD!</span></div>
<div class="body">${s.inner}</div>
<footer><span>CLAUDE-VIPER'S VISUAL FIELD GUIDES</span><span>COBRA ISLAND EDITION</span><span class="pgno">${String(no).padStart(2, "0")}</span></footer>
</section>`;
});

let tocHtml = "";
let lastGroup = null;
const groupName = { gate: "WORLD 1: THE GATE (cobra-gate 10.6.9.10)", stream: "WORLD 2: THE STREAM (cobra-stream 10.6.9.20)", bonus: "BONUS STAGES", front: "START", back: "EXTRAS" };
let k = 0;
for (const e of toc) {
  if (e.group !== lastGroup) { tocHtml += `<div class="zonehead ${e.group}">${groupName[e.group] || e.group.toUpperCase()}</div>`; lastGroup = e.group; }
  k++;
  tocHtml += `<a href="#${e.id}"><span class="n">${String(k).padStart(2, "0")}</span><span class="t">${e.title}${e.sub ? `<small>${e.sub}</small>` : ""}</span><span class="p">P.${e.no}</span></a>`;
}

let body = out.join("\n").replace('<div class="toc" id="toc"></div>', `<div class="toc" id="toc">${tocHtml}</div>`);
body = body.replace(/\{\{pages\}\}/g, String(sections.length)).replace(/\{\{chapters\}\}/g, String(toc.filter((e) => e.group === "gate" || e.group === "stream").length));
body = renderSprites(body);

// ---------- one self-contained file: CSS and fonts inline ----------
let css = readFileSync(join(here, "style.css"), "utf8");
css = css.replace(/url\("fonts\/([^"]+)"\)/g, (_, f) => `url("data:font/woff2;base64,${readFileSync(join(here, "fonts", f)).toString("base64")}")`);
const html = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Claude-Viper's Visual Field Guides Present: You and Your Pod!</title>
<style>${css}</style></head>
<body>
${body}
</body></html>`;
const htmlPath = join(outDir, "you-and-your-pod.html");
writeFileSync(htmlPath, html);
console.log(`wrote ${htmlPath} (${sections.length} pages, ${toc.length} contents entries)`);
if (htmlOnly) process.exit(0);

// ---------- check every page and print the PDF ----------
const { chromium } = createRequire(import.meta.url)("playwright"); // global or local install
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 816, height: 1056 } });
await page.goto("file://" + htmlPath);
await page.evaluate(() => document.fonts.ready);
const problems = await page.evaluate(() => {
  const res = [];
  document.querySelectorAll(".page").forEach((p, i) => {
    const b = p.querySelector(".body");
    if (b.scrollHeight > b.clientHeight + 2) res.push(`page ${i + 1} (${p.dataset.file}): content is ${b.scrollHeight - b.clientHeight}px too tall`);
    const pr = b.getBoundingClientRect();
    b.querySelectorAll("*").forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.width && r.right > pr.right + 4 && getComputedStyle(el).position !== "absolute") {
        res.push(`page ${i + 1} (${p.dataset.file}): <${el.tagName.toLowerCase()} class="${el.className}"> sticks out ${Math.round(r.right - pr.right)}px on the right`);
      }
    });
    // box title tabs are absolutely positioned, so check them against their own box
    b.querySelectorAll(".panel>h3,.tip>h3,.trap>h3,.codes>h3,.stats>h3,.intel>h3").forEach((h) => {
      const hr = h.getBoundingClientRect(), br = h.parentElement.getBoundingClientRect();
      if (hr.right > br.right + 2) res.push(`page ${i + 1} (${p.dataset.file}): box title "${h.textContent.trim()}" is wider than its box; shorten it`);
    });
  });
  return [...new Set(res)].slice(0, 80);
});
if (problems.length) { console.log("LAYOUT PROBLEMS:"); problems.forEach((p) => console.log("  " + p)); }
else console.log("layout check: every page fits");

const pdfPath = join(outDir, "you-and-your-pod.pdf");
await page.pdf({ path: pdfPath, width: "8.5in", height: "11in", printBackground: true, preferCSSPageSize: true });
console.log(`wrote ${pdfPath}`);

if (shotsArg) {
  const dir = process.env.SHOTS_DIR || join(here, "..", "..", ".shots");
  mkdirSync(dir, { recursive: true });
  const list = shotsArg === "all" ? sections.map((_, i) => i + 1) : shotsArg.split(",").flatMap((r) => { const [a, b] = r.split("-").map(Number); return b ? Array.from({ length: b - a + 1 }, (_, i) => a + i) : [a]; });
  for (const n of list) {
    const el = await page.$(`#p${n}`);
    if (el) { await el.screenshot({ path: join(dir, `page-${String(n).padStart(2, "0")}.png`) }); }
  }
  console.log(`screenshots in ${dir}`);
}
await browser.close();
process.exit(problems.length ? 1 : 0);
