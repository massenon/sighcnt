'use strict';
/* Scénario L0 (décision de la Direction du 09/11/2026) : les PARAMÈTRES se règlent au poste, voyagent par le journal (famille R) vers le relais, qui ne les stocke que CHIFFRÉS,
   et un second poste les reçoit et les applique. Versionnés par date : une valeur déjà utilisée par une pièce ne se réécrit jamais. Un téléphone ne reçoit que la liste blanche.
   Règle de référence : banc/parametres.js. Le « poste » qui règle est la mère (elle seule écrit une collection R) ; le second poste est un fileul. */
const { dechiffrer } = require('./crypto');
const P = require('./parametres');

/* Définitions DU BANC (fixtures : aucune n'est une donnée de la clinique). */
const SECRET = 'VALEUR-SECRETE-L0-Zébulon';
const DEF = {
  circuit: { cle: 'planning.circuit', famille: 'planning', type: 'choix', choix: ['surveillant', 'daf', 'surveillant_puis_daf'], defaut: 'surveillant', source: 'fixture du banc' },
  note: { cle: 'accueil.note', famille: 'accueil', type: 'texte', defaut: 'rien', source: 'fixture du banc' },
  affichage: { cle: 'accueil.affichage', famille: 'accueil', type: 'booleen', defaut: false, mobile: true, source: 'fixture du banc' },
  paie: { cle: 'paie.exemple', famille: 'paie', type: 'booleen', defaut: true, mobile: true, source: 'fixture du banc (famille réservée)' },
};
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async L0() {
    titre('PARAMÈTRES-L0 · le poste règle, le relais ne stocke que du chiffré, un second poste applique ; versionné par date ; liste blanche du téléphone');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1');
    const emettre = (fiche, id) => m.mere.admin('POST', '/admin/referentiel', { collection: 'parametres', fiche: id, champs: fiche }).then((r) => r.json);
    const etatMere = () => m.mere.admin('GET', '/admin/etat').then((r) => r.json);
    const liste = async (poste) => (await poste.liste('parametres')).map((x) => x.data);
    const quand = async (poste, nom, date) => P.resoudre(nom, await liste(poste), date, Object.values(DEF).find((d) => d.cle === nom));

    /* 1. le défaut est SEMÉ (version 0), puis une valeur secrète est réglée */
    for (const d of [DEF.circuit, DEF.note, DEF.affichage]) { const s = P.semer(d); const r = await emettre(s.fiche, s.id); if (r.statut !== 'acceptee') verifier('le défaut semé est accepté', false, r); }
    const vNote = P.proposer({ definition: DEF.note, versions: [P.semer(DEF.note).fiche], usages: [], valeur: SECRET, dateEffet: '2026-11-09', auteur: 'admin', creeLe: '2026-11-09T08:00:00Z', motif: 'banc' });
    const rNote = await emettre(vNote.fiche, vNote.id);
    verifier('une nouvelle valeur datée est acceptée par la mère, avec un seq', rNote.statut === 'acceptee' && rNote.seq > 0, rNote);

    /* 2. le second poste la reçoit et l'applique */
    verifier('le fileul reçoit les versions (trois défauts semés + la valeur réglée)', await attendre(async () => (await liste(f1)).length === 4, 15000), (await liste(f1)).length);
    const surF1 = await quand(f1, 'accueil.note', '2026-11-09');
    verifier('le fileul APPLIQUE : à la date d\'effet la valeur réglée, la veille le défaut semé', surF1.ok && surF1.valeur === SECRET && (await quand(f1, 'accueil.note', '2026-11-08')).valeur === 'rien', [surF1, await quand(f1, 'accueil.note', '2026-11-08')]);

    /* 3. le relais ne voit que du chiffré : on DÉCODE chaque enveloppe et on mesure l'entropie, on ne cherche pas seulement du texte */
    await attendre(async () => { const e = await etatMere(); return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const journal = brut.lignes.filter((l) => l.dir === 'journal');
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = journal.map((l) => Buffer.from(l.ct, 'base64'));
    verifier('le relais détient le journal de la mère en enveloppes', journal.length >= 1, journal.length);
    verifier('ni la valeur, ni la clé du paramètre, ni le nom de la collection ne sont lisibles au relais, même après décodage des octets',
      !/Zébulon|VALEUR-SECRETE|accueil\.note|planning\.circuit|parametres/.test(tout) && octets.every((b) => !/Z\xc3\xa9bulon|VALEUR-SECRETE|accueil\.note|planning\.circuit|parametres/.test(b.toString('latin1'))));
    const gros = octets.filter((b) => b.length >= 250);
    verifier('chaque enveloppe porteuse a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((b) => entropie(b) > 7.0), octets.map((b) => [b.length, +entropie(b).toFixed(2)]));
    const claires = journal.map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien le paramètre : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'parametres' && o.champs && o.champs.valeur === SECRET), claires.length);
    verifier('la clé de clinique n\'est nulle part au relais', !tout.includes(m.mere.opts.cle) && !tout.includes(m.clePair));

    /* 4. versionné par date : la valeur en vigueur dépend de la date de la pièce */
    const vDaf = P.proposer({ definition: DEF.circuit, versions: [P.semer(DEF.circuit).fiche], usages: [], valeur: 'daf', dateEffet: '2026-12-01', auteur: 'admin', creeLe: '2026-11-09T09:00:00Z', motif: 'banc' });
    await emettre(vDaf.fiche, vDaf.id);
    await attendre(async () => (await liste(f1)).length === 5, 15000);
    verifier('avant la date d\'effet l\'ancienne valeur, à la date la nouvelle (sur le poste récepteur)',
      (await quand(f1, 'planning.circuit', '2026-11-30')).valeur === 'surveillant' && (await quand(f1, 'planning.circuit', '2026-12-01')).valeur === 'daf');

    /* 5. une pièce émise sur le fileul a utilisé la valeur du 20/11 : on ne réécrit pas ce qu'elle a utilisé */
    await f1.ecrire({ type: 'creer', collection: 'usagesParametres', fiche: 'planning.circuit@F-1', champs: { cle: 'planning.circuit', date: '2026-11-20', piece: 'F-1' } });
    verifier('l\'usage relevé sur le fileul arrive à la mère', await attendre(async () => (await m.mere.admin('GET', '/admin/compte?collection=usagesParametres')).json.n === 1, 15000));
    const tous = await liste(f1);
    const retro = P.proposer({ definition: DEF.circuit, versions: tous, usages: [], valeur: 'surveillant_puis_daf', dateEffet: '2026-11-15', auteur: 'admin', creeLe: '2026-11-09T10:00:00Z' });
    const rRetro = await emettre(retro.fiche, retro.id);
    verifier('la mère REFUSE une version qui réécrirait la valeur déjà utilisée, refus nommé avec son geste',
      rRetro.statut === 'refusee' && rRetro.code === 'parametre_deja_utilise' && /2026-11-20/.test(rRetro.motif) && /postérieure au 2026-11-20/.test(rRetro.geste), rRetro);
    verifier('rien n\'a changé : la valeur du 20/11 reste « surveillant » sur la mère comme sur le fileul',
      (await liste(f1)).length === 5 && (await quand(f1, 'planning.circuit', '2026-11-20')).valeur === 'surveillant');
    const ok = P.proposer({ definition: DEF.circuit, versions: tous, usages: [], valeur: 'surveillant_puis_daf', dateEffet: '2026-11-21', auteur: 'admin', creeLe: '2026-11-09T10:00:00Z' });
    verifier('une date d\'effet postérieure à l\'usage est acceptée', (await emettre(ok.fiche, ok.id)).statut === 'acceptee');
    const dup = await emettre({ ...vDaf.fiche, valeur: 'surveillant' }, vDaf.id);
    verifier('une version déjà écrite ne se modifie jamais (refus nommé)', dup.statut === 'refusee' && dup.code === 'version_immuable', dup);

    /* 6. un fileul n'écrit jamais un paramètre : la mère seule */
    await f1.ecrire({ type: 'creer', collection: 'parametres', fiche: 'intrus', champs: { ...P.semer(DEF.note).fiche, cle: 'intrus.cle' } });
    verifier('un fileul qui tente d\'écrire un paramètre est refusé, nommé (droit_refuse)', await attendre(async () => (await f1.etat()).a_traiter.some((r) => r.code === 'droit_refuse'), 15000));

    /* 6 bis. l'ORDRE d'arrivée ne compte pas : le poste publie du plus récent au plus ancien, la mère accepte v(n+2) puis v(n+1) */
    const base = await liste(f1);
    const p1 = P.proposer({ definition: DEF.note, versions: base, usages: [], valeur: 'ancienne', dateEffet: '2026-12-10', auteur: 'admin', creeLe: '2026-11-09T10:30:00Z' });
    const p2 = P.proposer({ definition: DEF.note, versions: [...base, p1.fiche], usages: [], valeur: 'recente', dateEffet: '2026-12-20', auteur: 'admin', creeLe: '2026-11-09T10:31:00Z' });
    const r2 = await emettre(p2.fiche, p2.id); const r1 = await emettre(p1.fiche, p1.id);
    verifier('une version plus récente arrivée AVANT la précédente est acceptée (v' + p2.fiche.version + ' puis v' + p1.fiche.version + ')', r2.statut === 'acceptee' && r1.statut === 'acceptee', [r2, r1]);
    verifier('le numéro d\'une version déjà prise par une autre fiche est refusé, nommé', (await emettre({ ...p1.fiche, dateEffet: '2026-12-11' }, p1.id + '-bis')).code === 'version_deja_prise');
    verifier('le fileul voit les deux, la valeur en vigueur suit la date', await attendre(async () => (await quand(f1, 'accueil.note', '2026-12-25')).valeur === 'recente' && (await quand(f1, 'accueil.note', '2026-12-12')).valeur === 'ancienne', 15000));

    /* 7. le téléphone : liste blanche. Les fiches sont créées APRÈS l'appairage (sinon rien ne descendrait de toute façon) */
    const mob = await m.mobile('M1');
    const avant = (await mob.liste('parametres')).length;
    const connues = await liste(f1);
    const v2 = (d, valeur) => P.proposer({ definition: d, versions: connues, usages: [], valeur, dateEffet: '2026-12-15', auteur: 'admin', creeLe: '2026-11-09T11:00:00Z' });
    const interdit = v2(DEF.paie, false);
    verifier('un paramètre de famille réservée ne peut pas être déclaré « mobile » (refus à l\'émission du poste)', interdit.ok === false && interdit.code === 'mobile_interdit', interdit);
    const forcee = await emettre({ ...P.semer(DEF.paie).fiche }, P.semer(DEF.paie).id);
    verifier('la mère le refuse AUSSI à la réception (même règle, jamais fiée au poste)', forcee.statut === 'refusee' && forcee.code === 'mobile_interdit', forcee);
    const nonListe = v2(DEF.circuit, 'daf'); const secret = v2(DEF.note, SECRET + '-bis'); const blanc = v2(DEF.affichage, true);
    const accepte = [];
    for (const v of [nonListe, secret, blanc]) accepte.push((await emettre(v.fiche, v.id)).statut);
    verifier('la mère accepte les trois versions (sinon « le téléphone ne les reçoit pas » ne prouverait rien)', accepte.every((x) => x === 'acceptee'), accepte);
    verifier('le téléphone reçoit le paramètre de la liste blanche', await attendre(async () => (await mob.liste('parametres')).some((x) => x.id === blanc.id), 15000));
    verifier('le fileul, lui, reçoit la valeur secrète', await attendre(async () => (await liste(f1)).some((x) => x.cle === 'accueil.note' && x.valeur === SECRET + '-bis'), 15000));
    const recus = (await mob.liste('parametres')).map((x) => x.id);
    verifier('le téléphone ne reçoit AUCUN autre paramètre (ni non déclaré mobile, ni valeur secrète)',
      recus.length === avant + 1 && !recus.includes(nonListe.id) && !recus.includes(secret.id), [avant, recus]);
    await m.fermer();
  },
});
