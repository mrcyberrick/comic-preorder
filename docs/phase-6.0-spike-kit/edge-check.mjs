// G1 edge check. Usage (from the comic-preorder repo root): node edge-check.mjs <label>
// spike-<label>: expect 200 + X-Spike once the Worker is live (before: no answer).
// <label> (not spike-): records what an unregistered name returns through the wildcard (Q2).
// rjbookstop / comicstore: MUST show no X-Spike / X-Spike-Passthrough and serve origin/main's index.html (Q3).
import { execSync } from 'node:child_process';
import crypto from 'node:crypto';
import tls from 'node:tls';
const label = process.argv[2]; if (!label) throw new Error('label required');
const norm = s => s
  .replace(/<a [^>]*href="\/cdn-cgi\/l\/email-protection[^>]*>[\s\S]*?<\/a>/g, '')
  .replace(/<a [^>]*href="mailto:[^"]*"[^>]*>[\s\S]*?<\/a>/g, '')
  .replace(/<script[^>]*email-decode\.min\.js[^>]*><\/script>/g, '');
const h = s => crypto.createHash('sha256').update(norm(s)).digest('hex').slice(0, 12);
const mainIndex = execSync('git show origin/main:index.html', { encoding: 'utf8', maxBuffer: 1e7 });
const san = host => new Promise(r => { const s = tls.connect(443, host, { servername: host }, () => {
  const c = s.getPeerCertificate(); s.end(); r(c.subjectaltname || '(none)'); });
  s.on('error', e => r('TLS error: ' + e.code)); s.setTimeout(8000, () => { s.destroy(); r('TLS timeout'); }); });
let bad = false;
for (const host of [`spike-${label}.pulllist.app`, `${label}.pulllist.app`, 'rjbookstop.pulllist.app', 'comicstore.pulllist.app', 'www.pulllist.app', 'staging.pulllist.app']) {
  let line;
  try {
    const res = await fetch(`https://${host}/`, { redirect: 'follow' });
    const body = await res.text();
    const xs = res.headers.get('x-spike'), xp = res.headers.get('x-spike-passthrough');
    line = `${host}: ${res.status} x-spike=${xs ?? '-'} passthrough=${xp ?? '-'} cf-ray=${res.headers.get('cf-ray') ? 'yes' : 'no'} body=${JSON.stringify(body.slice(0, 50))}`;
    if (host.startsWith('rjbookstop') || host.startsWith('comicstore')) {
      const same = h(body) === h(mainIndex);
      line += ` index==main:${same}`;
      if (xs || xp || !same) { bad = true; line += '  <<< HALT: production hostname changed'; }
    }
  } catch (e) { line = `${host}: no answer (${e.cause?.code || e.message})`; }
  console.log(line + `\n   SAN: ${await san(host)}`);
}
console.log(bad ? '\nRESULT: HALT - tear down first' : '\nRESULT: production hostnames unchanged');
