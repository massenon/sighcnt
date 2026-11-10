const { ouvrirMaquette } = require('./extraire');
(async () => {
  const m = await ouvrirMaquette();
  try {
    const r = await m.page.evaluate(() => {
      const RG = SIGH.reglagesAib, S = SIGH.store;
      const out = {};
      out.charge = RG.charge('2026-11-09'); out.br = RG.branchement('2026-11-09');
      out.achats0 = 1;
      out.achats = RG.achatsAEcrire({}); out.achatsSample = out.achats.lignes.slice(0, 4); out.aEcrire=out.achats.aEcrire;
      out.ecrire = RG.ecrireAchats({}).code;
      out.sem = SIGH.semerAchats(true); out.fact = [S.collection("facturesFournisseurs").all().length, S.collection("facturesFournisseurs").all().slice(0,2), S.collection("fournisseurs").all().length];
      out.four = S.collection('fournisseurs').all().slice(0, 2).map((f) => ({ code: f.code, ifu: f.ifu }));
      out.comptes = S.collection('comptes').active().filter((c) => /^(4|5)/.test(c.num)).slice(0, 5).map((c) => c.num + c.libelle);
      return out;
    });
    console.log(JSON.stringify(r, null, 1).slice(0, 5000));
    console.log(m.erreurs);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
