'use strict';
/* Scénarios SYN1 et SYN2 (lot RLS-SYNC) : l'écran « Synchronisation » du panneau du relais.

   Décision de la Direction du 13/11/2026 : le relais gagne un écran des synchronisations des fileuls, de la mère et des mobiles. Les fileuls ne parlent PAS au relais (réseau local) : c'est la MÈRE qui
   publie leur état dans ses indicateurs de battement, en COMPTEURS ET HORODATAGES seulement. Jamais un identifiant de patient, un nom, un libellé de pièce ni un motif.

     SYN1 (protocole, relais de référence Node OU relais Laravel, mère Node OU Dart) :
       1. la mère publie un tableau `fileuls` : un poste par fileul actif, son nom technique, des clés ET des types de la liste blanche, jamais une autre clé ;
       2. un conflit réel entre deux fileuls est compté chez le poste concerné (compteur) ;
       3. le relais REFUSE en nommant une clé inconnue (nom, identifiant de patient, motif, libellé), un nom de poste qui ressemble à un dossier, un compteur non numérique : 422, rien d'enregistré ;
       4. le relais ne détient AUCUN nom de patient ni code de dossier (ses lignes comme ses indicateurs) alors qu'un patient vient d'être créé ;
       5. un téléphone ne lit rien de cette publication : ni l'état du relais, ni les indicateurs, ni une boîte autre que la sienne, et ce qu'il a reçu ne porte aucun des champs.

     SYN2 (relais LARAVEL seulement : l'historique est propre à ce relais) : l'historique de synchronisation s'écrit, ne porte que des compteurs et des horodatages, se purge à la durée RÉGLÉE
       en base (90 jours par défaut, puis 30), jamais en dessous ; la relève d'un mobile est notée par le relais. */
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { dechiffrer } = require('./crypto');
const SYNCHRO = require('./synchro');

const NOM_SECRET = 'KOUASSI Awa';

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async SYN1() {
    titre('RLS-SYN1 · la mère publie l\'état de ses fileuls en compteurs et horodatages ; le relais refuse en nommant tout le reste, ne détient aucun nom, et un téléphone n\'en lit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('Poste caisse'); const f2 = await m.fileul('F2');
    const etat = async () => (await m.relais.direct('GET', '/admin/etat')).json;
    const publiee = async () => { const e = await etat(); return e.indicateurs && Array.isArray(e.indicateurs.fileuls) ? e.indicateurs.fileuls : null; };

    /* 1. LA PUBLICATION : un poste par fileul actif, la liste blanche pour seules clés. */
    verifier('la mère publie le tableau `fileuls` : un poste par fileul actif, avec son nom technique', await attendre(async () => { const f = await publiee(); return f && f.length === 2; }, 20000));
    const f = (await publiee()) || [];
    verifier('les clés publiées sont EXACTEMENT celles de la liste blanche (poste, dernierContact, retardJournal, conflitsOuverts, demandesImportEnAttente), jamais une autre', f.length === 2 && f.every((x) => Object.keys(x).every((k) => SYNCHRO.CLES.includes(k)) && 'poste' in x), f);
    verifier('les noms sont ceux de l\'appairage (le nom technique du poste), pas un nom de personne', JSON.stringify(f.map((x) => x.poste).sort()) === JSON.stringify(['F2', 'Poste caisse']), f.map((x) => x.poste));
    verifier('les valeurs sont des entiers (horodatage, compteurs) ou null : jamais un texte hors le nom du poste', f.every((x) => SYNCHRO.CLES.slice(1).every((k) => !(k in x) || x[k] === null || (Number.isInteger(x[k]) && x[k] >= 0))), f);
    verifier('un fileul qui a parlé à la mère a un dernier contact récent et un retard de journal calculé (jamais zéro par défaut)', f.every((x) => Number.isInteger(x.dernierContact) && Date.now() - x.dernierContact < 60000 && Number.isInteger(x.retardJournal)), f);
    verifier('le tableau passe la liste blanche du relais de référence (même règle, mêmes vecteurs)', SYNCHRO.valider({ fileuls: f }) === null);

    /* 2. UN CONFLIT RÉEL est compté chez un poste (compteur, jamais le détail). Un patient au nom en clair sert à vérifier que rien ne fuit. */
    const p = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: NOM_SECRET, telephone: '111' } });
    await attendre(async () => (await f2.vue('patients', p.fiche)).data.telephone === '111', 15000);
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '222' } });
    await f2.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '333' } });
    m.reseau.regler('ouvert');
    await attendre(async () => (await f1.vide()) && (await f2.vide()), 15000);
    verifier('le conflit ouvert est publié comme un COMPTEUR chez le poste concerné (conflitsOuverts), sans aucun détail', await attendre(async () => { const g = (await publiee()) || []; return g.reduce((a, x) => a + (x.conflitsOuverts || 0), 0) === 1; }, 15000), await publiee());

    /* 3. LE RELAIS REFUSE EN NOMMANT, ET N'ENREGISTRE RIEN. */
    const refus = async (fileuls, motifAttendu, chemin) => {
      const r = await m.relais.direct('POST', '/mere/indicateurs', { indicateurs: { fileuls } });
      const corps = JSON.stringify(r.json);
      return r.status === 422 && r.json.code === motifAttendu && r.json.chemin === chemin && !!r.json.motif && !!r.json.geste && !corps.includes(NOM_SECRET) && !corps.includes('CNT/');
    };
    verifier('une clé inconnue (un nom de personne) est refusée en la nommant, sans recopier la valeur', await refus([{ poste: 'F1', nom: NOM_SECRET }], 'indicateur_cle_inconnue', 'fileuls[0].nom'));
    verifier('un identifiant de patient est refusé de même', await refus([{ poste: 'F1', patientId: 'CNT/12/26' }], 'indicateur_cle_inconnue', 'fileuls[0].patientId'));
    verifier('un motif et un libellé de pièce sont refusés de même', await refus([{ poste: 'F1', motif: 'doublon' }], 'indicateur_cle_inconnue', 'fileuls[0].motif') && await refus([{ poste: 'F1', libelle: 'Facture 123' }], 'indicateur_cle_inconnue', 'fileuls[0].libelle'));
    verifier('un nom de poste qui ressemble à un dossier est refusé', await refus([{ poste: 'CNT/12/26' }], 'indicateur_valeur_invalide', 'fileuls[0].poste'));
    verifier('un compteur qui n\'est pas un nombre est refusé', await refus([{ poste: 'F1', conflitsOuverts: NOM_SECRET }], 'indicateur_valeur_invalide', 'fileuls[0].conflitsOuverts') && await refus([{ poste: 'F1', retardJournal: '4' }], 'indicateur_valeur_invalide', 'fileuls[0].retardJournal'));
    const sansSecret = async () => { const t = (await m.relais.direct('GET', '/banc/tout')).json; return !JSON.stringify(t.meta).includes(NOM_SECRET) && !JSON.stringify(t.meta).includes('CNT/12/26'); };
    verifier('rien d\'un envoi refusé n\'est enregistré : les indicateurs du relais ne portent ni le nom ni l\'identifiant refusés', await sansSecret());
    const refusSansMere = await m.relais.brut('POST', '/mere/indicateurs', { indicateurs: { fileuls: [{ poste: 'F1', nom: 'x' }] } });
    verifier('l\'autorisation PRÉCÈDE la validation : sans le secret de la mère, 403 quelle que soit la forme', refusSansMere.status === 403 && refusSansMere.json.code === 'mere_requise', refusSansMere);

    /* 4. LE RELAIS NE DÉTIENT AUCUN NOM de patient, alors qu'un patient vient d'être créé et répliqué. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes.map((l) => ({ ...l, ct: '', nonce: '' })), codes: brut.codes, appareils: brut.appareils, meta: brut.meta });
    verifier('le relais détient le journal chiffré de la mère mais AUCUN nom de patient ni code de dossier, ni dans ses lignes ni dans ses indicateurs', brut.lignes.length >= 1 && !tout.includes(NOM_SECRET) && !tout.includes('Awa') && !/CNT\/\d+\/\d+/.test(tout), brut.lignes.length);

    /* 5. UN TÉLÉPHONE N'EN LIT RIEN. */
    const mob = await m.mobile('Tel', { profil: 'reception' });
    const code = 'code-syn1-' + Math.random().toString(36).slice(2);
    await m.relais.direct('POST', '/mere/code', { hash: require('node:crypto').createHash('sha256').update(code).digest('hex') });
    const app = await m.relais.brut('POST', '/appairage', { code, uuid: 'tel-brut-syn1' });
    const h = { Authorization: 'Bearer ' + app.json.jeton };
    const ee = await m.relais.brut('GET', '/admin/etat', undefined, h);
    verifier('un téléphone appairé n\'obtient pas l\'état du relais ni ses indicateurs (403 mere_requise)', app.status === 200 && ee.status === 403 && ee.json.code === 'mere_requise' && !JSON.stringify(ee.json).includes('fileuls'), ee);
    const pub = await m.relais.brut('POST', '/mere/indicateurs', { indicateurs: { fileuls: [] } }, h);
    verifier('il ne peut pas non plus publier des indicateurs (403)', pub.status === 403, pub);
    const lectures = await Promise.all(['indicateurs', 'synchro', 'meta', 'journal', 'copie'].map((d) => m.relais.brut('GET', `/releve?dir=${d}&appareil=tel-brut-syn1&depuis_n=0`, undefined, h)));
    verifier('aucune boîte autre que la sienne ne lui est lisible', lectures.every((r) => r.status === 403 && r.json.code === 'lecture_interdite'), lectures.map((r) => [r.status, r.json.code]));
    await dormir(1500);
    const vers = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const recu = JSON.stringify(vers.map((l) => dechiffrer(cleClinique, l)));
    verifier('ce que le relais a distribué au téléphone ne porte aucun des champs de synchronisation (ni fileuls, ni retard, ni contact, ni nom de poste)', vers.length >= 1 && !/fileuls|retardJournal|dernierContact|conflitsOuverts|demandesImportEnAttente|Poste caisse/.test(recu), vers.length);
    verifier('et la base du téléphone n\'en porte rien non plus', !/fileuls|retardJournal|dernierContact|conflitsOuverts/.test(JSON.stringify(await mob.etat())));
    await m.fermer();
  },

  async SYN2() {
    if (process.env.SIGH_RELAIS !== 'laravel') { console.log('  (SYN2 non joué : l\'historique de synchronisation est propre au relais Laravel ; lancer `SIGH_RELAIS=laravel`, ou `npm run banc:cible`)'); return; }
    titre('RLS-SYN2 · l\'historique de synchronisation (relais Laravel) : compteurs et horodatages, purge à la durée RÉGLÉE en base (90 jours puis 30), jamais en dessous ; la relève d\'un mobile est notée');
    const { DatabaseSync } = require('node:sqlite');
    const m = await monde({ relais: true });
    const bd = path.join(m.dir, 'relais.sqlite');
    const WEB = path.resolve(__dirname, '..', '..', '..', 'apps', 'web');
    const env = Object.assign({}, process.env, { APP_KEY: 'base64:' + require('node:crypto').randomBytes(32).toString('base64'), APP_ENV: 'local', DB_CONNECTION: 'sqlite', DB_DATABASE: bd, SESSION_DRIVER: 'array', CACHE_STORE: 'array', QUEUE_CONNECTION: 'sync', MAIL_MAILER: 'array', RELAIS_SECRET_MERE: 'secret-mere' });
    const surveiller = () => spawnSync('php', ['artisan', 'relais:surveiller'], { cwd: WEB, env, encoding: 'utf8' });
    const sql = (texte, ...p) => { const d = new DatabaseSync(bd); d.exec('PRAGMA busy_timeout=5000'); try { return d.prepare(texte).all(...p); } finally { d.close(); } };
    const ecrire = (texte, ...p) => { const d = new DatabaseSync(bd); d.exec('PRAGMA busy_timeout=5000'); try { d.prepare(texte).run(...p); } finally { d.close(); } };
    const f1 = await m.fileul('Poste caisse');
    const mob = await m.mobile('Tel', { profil: 'reception' });

    verifier('l\'historique reçoit un relevé du fileul publié par la mère (un relevé par intervalle réglé, pas un par battement)', await attendre(async () => sql("SELECT COUNT(*) AS n FROM relais_synchro_historique WHERE nature='fileul' AND ref='Poste caisse'")[0].n >= 1, 20000));
    await dormir(2500);
    verifier('plusieurs battements par seconde, mais UN seul relevé dans l\'intervalle de 10 minutes', sql("SELECT COUNT(*) AS n FROM relais_synchro_historique WHERE nature='fileul' AND ref='Poste caisse'")[0].n === 1, sql('SELECT * FROM relais_synchro_historique'));
    const colonnes = sql('PRAGMA table_info(relais_synchro_historique)').map((c) => c.name).sort();
    verifier('la table ne porte que des horodatages et des compteurs, plus la référence de l\'appareil', JSON.stringify(colonnes) === JSON.stringify(['attente', 'conflits', 'demandes', 'dernier_contact', 'id', 'nature', 'quand', 'ref', 'retard_journal']), colonnes);
    verifier('le relais a noté la relève du mobile : une heure et le rang qu\'il a traité', await attendre(async () => { const a = sql('SELECT dernier_releve, releve_n FROM relais_appareils WHERE uuid=?', mob.uuid)[0]; return a && a.dernier_releve > 0 && a.releve_n >= 1; }, 20000), sql('SELECT uuid, dernier_releve, releve_n FROM relais_appareils'));

    const jour = 86400000; const maintenant = Date.now();
    ecrire("INSERT INTO relais_synchro_historique(quand,nature,ref,retard_journal) VALUES(?,?,?,?)", maintenant - 91 * jour, 'fileul', 'VIEUX-91', 1);
    ecrire("INSERT INTO relais_synchro_historique(quand,nature,ref,retard_journal) VALUES(?,?,?,?)", maintenant - 40 * jour, 'fileul', 'MI-40', 1);
    const regle = sql("SELECT v FROM relais_meta WHERE k='reglage.synchro.conservation_jours'")[0];
    verifier('la durée de conservation est un réglage SEMÉ EN BASE, 90 jours par défaut', regle && regle.v === '90', regle);
    const s1 = surveiller();
    const refs = () => sql('SELECT ref FROM relais_synchro_historique').map((r) => r.ref);
    verifier('le passage du cron purge au-delà de 90 jours (91 j partent) et garde en dessous (40 j reste, les relevés du jour aussi)', s1.status === 0 && !refs().includes('VIEUX-91') && refs().includes('MI-40') && refs().includes('Poste caisse'), [s1.status, s1.stderr, refs()]);
    ecrire("UPDATE relais_meta SET v='30' WHERE k='reglage.synchro.conservation_jours'");
    const s2 = surveiller();
    verifier('la durée réglée à 30 jours : le relevé de 40 jours part, celui du jour reste', s2.status === 0 && !refs().includes('MI-40') && refs().includes('Poste caisse'), [s2.status, s2.stderr, refs()]);
    ecrire("UPDATE relais_meta SET v='1' WHERE k='reglage.synchro.conservation_jours'");
    ecrire("INSERT INTO relais_synchro_historique(quand,nature,ref,retard_journal) VALUES(?,?,?,?)", maintenant - 10 * jour, 'fileul', 'DIX-JOURS', 1);
    const s3 = surveiller();
    verifier('une valeur hors borne posée en base (1 jour) ne fait JAMAIS purger sous le plancher de 30 jours', s3.status === 0 && refs().includes('DIX-JOURS'), [s3.status, refs()]);
    await m.fermer();
  },
});
