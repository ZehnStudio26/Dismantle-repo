// Serves the installed @quenty packages to Studio (no Rojo): GET /manifest lists every instance to build,
// GET /file?p=<relative path> returns one source file. Mapping follows each package's default.project.json
// ($path: src) and Rojo's file rules: a folder with init.lua becomes that ModuleScript, X.lua a ModuleScript,
// X.server.lua a Script, X.client.lua a LocalScript. Test-only files (*.spec.lua, jest.config.lua) and
// project json files are skipped. Run: node nevermore/serve-packages.js  (port 8124). Node only, no packages.
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.join(__dirname, "node_modules");
const PORT = 8124;

function skip(name) {
  return name.endsWith(".spec.lua") || name === "jest.config.lua" || name.endsWith(".json") || name.startsWith(".");
}
function classOf(file) {
  if (file.endsWith(".server.lua") || file.endsWith(".server.luau")) return "Script";
  if (file.endsWith(".client.lua") || file.endsWith(".client.luau")) return "LocalScript";
  return "ModuleScript";
}
function baseName(file) {
  return file.replace(/\.(server|client)?\.?(lua|luau)$/, "").replace(/\.(lua|luau)$/, "");
}

// entries: { path: [names...], className, file? }
function walk(dir, instPath, out) {
  const names = fs.readdirSync(dir).filter(n => !skip(n));
  const init = names.find(n => n === "init.lua" || n === "init.luau");
  out.push({ path: instPath, className: init ? "ModuleScript" : "Folder", file: init ? path.relative(ROOT, path.join(dir, init)).split(path.sep).join("/") : undefined });
  for (const n of names) {
    if (n === init) continue;
    const full = path.join(dir, n);
    if (fs.statSync(full).isDirectory()) walk(full, instPath.concat(n), out);
    else if (/\.(lua|luau)$/.test(n)) out.push({ path: instPath.concat(baseName(n)), className: classOf(n), file: path.relative(ROOT, full).split(path.sep).join("/") });
  }
}

function manifest() {
  const out = [{ path: ["node_modules"], className: "Folder" }];
  for (const scope of fs.readdirSync(ROOT).filter(n => n.startsWith("@"))) {
    out.push({ path: ["node_modules", scope], className: "Folder" });
    for (const pkg of fs.readdirSync(path.join(ROOT, scope))) {
      const src = path.join(ROOT, scope, pkg, "src");
      if (fs.existsSync(src)) walk(src, ["node_modules", scope, pkg], out);
    }
  }
  return out;
}

http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname === "/manifest") { res.setHeader("Content-Type", "application/json"); return res.end(JSON.stringify(manifest())); }
  if (url.pathname === "/file") {
    const rel = url.searchParams.get("p") || "";
    const full = path.resolve(ROOT, rel);
    if (!full.startsWith(ROOT)) { res.statusCode = 403; return res.end(); }
    try { return res.end(fs.readFileSync(full, "utf8")); } catch { res.statusCode = 404; return res.end(); }
  }
  res.statusCode = 404; res.end();
}).listen(PORT, "127.0.0.1", () => console.log(`serving ${ROOT} on 127.0.0.1:${PORT}`));
