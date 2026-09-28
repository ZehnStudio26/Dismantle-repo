// Tiny static server for src/. Studio's Restore.luau fetches the manifest and each source file
// through HttpService (same mechanism Rojo uses). Run:  node src/serve.js   then run Restore.luau
// in the Studio command bar. Node only, no packages.
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = __dirname;
const PORT = Number(process.env.PORT || 8123);

// Map a mirror file to its DataModel path. Main.server.luau -> Script, *.client.luau -> LocalScript,
// Health.server.luau under StarterCharacterScripts -> Script, everything else -> ModuleScript.
function manifest() {
	const out = [];
	const walk = dir => {
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			const full = path.join(dir, e.name);
			if (e.isDirectory()) walk(full);
			else if (e.name.endsWith('.luau') && !['Setup.luau', 'Restore.luau'].includes(e.name)) {
				const rel = path.relative(ROOT, full).split(path.sep).join('/');
				const name = e.name.replace(/\.(server|client)?\.?luau$/, '').replace(/\.luau$/, '');
				const instancePath = 'game.' + rel.replace(/\.luau$/, '').replace(/\.(server|client)$/, '').split('/').join('.');
				out.push({ file: rel, instancePath: instancePath.replace(/\.[^.]+$/, '.' + name), className: e.name.endsWith('.server.luau') ? 'Script' : e.name.endsWith('.client.luau') ? 'LocalScript' : 'ModuleScript' });
			}
		}
	};
	walk(ROOT);
	return out;
}

http.createServer((req, res) => {
	const url = decodeURIComponent(req.url.split('?')[0]);
	if (url === '/manifest') { res.setHeader('Content-Type', 'application/json'); return res.end(JSON.stringify(manifest())); }
	const file = path.join(ROOT, url);
	if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.statusCode = 404; return res.end('not found'); }
	res.setHeader('Content-Type', 'text/plain; charset=utf-8');
	res.end(fs.readFileSync(file, 'utf8'));
}).listen(PORT, '127.0.0.1', () => console.log(`src server on http://127.0.0.1:${PORT}  (${manifest().length} scripts)`));
