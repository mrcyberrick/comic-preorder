import fs from 'node:fs';
const rand = process.argv[2], out = process.argv[3], Z = 'pulllist.app';
const q = [
  [Z,'A'],[Z,'AAAA'],[Z,'MX'],[Z,'TXT'],[Z,'NS'],[Z,'CAA'],
  ['www.'+Z,'A'],['www.'+Z,'CNAME'],
  ['rjbookstop.'+Z,'A'],['rjbookstop.'+Z,'AAAA'],['rjbookstop.'+Z,'CNAME'],
  ['comicstore.'+Z,'A'],['comicstore.'+Z,'AAAA'],['comicstore.'+Z,'CNAME'],
  ['staging.'+Z,'A'],['send.'+Z,'MX'],['send.'+Z,'TXT'],['mta.'+Z,'CNAME'],
  ['rjbookstop.'+Z,'TXT'],['comicstore.'+Z,'TXT'],['rjbookstop.'+Z,'MX'],
  ['brevo1._domainkey.rjbookstop.'+Z,'CNAME'],['brevo2._domainkey.rjbookstop.'+Z,'CNAME'],
  ['_domainkey.rjbookstop.'+Z,'TXT'],['brevo3._domainkey.rjbookstop.'+Z,'CNAME'],['_dmarc.rjbookstop.'+Z,'TXT'],
  ['resend._domainkey.'+Z,'TXT'],['ms1._domainkey.'+Z,'CNAME'],['ms2._domainkey.'+Z,'CNAME'],
  ['_dmarc.'+Z,'TXT'],['_dmarc.'+rand+'.'+Z,'TXT'],
  [rand+'.'+Z,'A'],[rand+'.'+Z,'AAAA'],[rand+'.'+Z,'CNAME'],[rand+'.'+Z,'TXT'],[rand+'.'+Z,'MX'],
  ['spike-'+rand+'.'+Z,'A'],['*.'+Z,'A'],
];
const lines = [];
for (const [name, type] of q) {
  const j = await (await fetch(`https://dns.google/resolve?name=${encodeURIComponent(name)}&type=${type}`)).json();
  const ans = (j.Answer || []).map(a => `${a.type}:${a.data}`).sort();
  lines.push(`${name} ${type} -> Status ${j.Status}${ans.length ? ' | ' + ans.join(' ; ') : ''}`);
}
const text = lines.join('\n') + '\n';
if (out) fs.writeFileSync(out, text);
process.stdout.write(text);
