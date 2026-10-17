/* Aperçu d'un classeur Excel — node build/_xlsx.js <fichier> [feuille] [lignes] */
'use strict';
const path = require('path');
const XLSX = require('xlsx');

const file = path.resolve(process.argv[2]);
const feuilleDemandee = process.argv[3];
const maxLignes = Number(process.argv[4] || 40);

const wb = XLSX.readFile(file, { cellDates: true });
console.log('FICHIER  : ' + path.basename(file));
console.log('FEUILLES : ' + wb.SheetNames.join(' | '));
console.log('─'.repeat(78));

const feuilles = feuilleDemandee ? [feuilleDemandee] : wb.SheetNames;
for (const nom of feuilles) {
  const ws = wb.Sheets[nom];
  if (!ws) { console.log('\n(feuille « ' + nom + ' » introuvable)'); continue; }
  const lignes = XLSX.utils.sheet_to_json(ws, { header: 1, blankrows: false, defval: '' });
  console.log(`\n════ FEUILLE « ${nom} » — ${lignes.length} ligne(s) ════`);
  lignes.slice(0, maxLignes).forEach((l, i) => {
    const cells = l.map((c) => (c instanceof Date ? c.toISOString().slice(0, 10) : String(c)))
      .map((c) => c.length > 28 ? c.slice(0, 27) + '…' : c);
    if (cells.some((c) => c.trim())) console.log(String(i + 1).padStart(4) + ' | ' + cells.join(' | '));
  });
  if (lignes.length > maxLignes) console.log(`     … ${lignes.length - maxLignes} ligne(s) supplémentaire(s)`);
}
