/* Les 21 écrans du mobile (prototype). Données de démonstration ; aucune requête réseau. */
(function (global) {
  'use strict';
  var S = global.SIGHM, M = global.SIGHM_MANIFESTE, E = S.ecran, esc = S.esc;

  var TOURNEE = [
    { id: 'p1', code: 'CNT/12/26', nom: 'DOSSOU Aline', age: 67, quartier: 'Kouba', tel: '97 11 22 33', motif: 'Suivi HTA', assurance: 'valide', allergies: 'Pénicilline', rdv: 'Visite à 09:30' },
    { id: 'p2', code: 'CNT/174/26', nom: 'KPOGNON Rose', age: 29, quartier: 'Péporiyakou', tel: '96 44 55 66', motif: 'Post-partum J5', assurance: 'expiree', allergies: '—', rdv: 'Visite à 10:45' },
    { id: 'p3', code: 'CNT/1109/26', nom: 'TAMOU Félix', age: 8, quartier: 'Bérécingou', tel: '95 00 11 22', motif: 'Paludisme — contrôle', assurance: 'aucune', allergies: '—', rdv: 'Visite à 14:00' },
    { id: 'p4', code: 'CNT/913/25', nom: 'SOUROU Mariam', age: 31, quartier: 'Winké', tel: '94 33 22 11', motif: 'CPN 3 — 28 SA', assurance: 'valide', allergies: '—', rdv: 'Visite à 15:30' },
  ];
  function patient(id) { return TOURNEE.filter(function (p) { return p.id === id; })[0] || TOURNEE[0]; }
  function assuranceBadge(a) { return a === 'valide' ? S.badge('Carte valide', 'ok') : (a === 'expiree' ? S.badge('CARTE NON VALIDE', 'err') : S.badge('Non assuré', '')); }
  function etatBadge(e) { return e === 'acceptee' ? S.badge('Acceptée', 'ok') : (e === 'refusee' ? S.badge('Refusée', 'err') : S.badge('En attente', 'warn')); }
  function choixPatient(selectId, ctx) {
    return S.champ(selectId, 'Patient', { type: 'select', options: TOURNEE.map(function (p) { return p.nom + ' — ' + p.code; }) });
  }
  function enregistrer(type, libelle, detail, retour) {
    S.enfiler(type, libelle, detail);
    S.toast(S.enLigne() ? 'Enregistré — envoi en cours.' : 'Enregistré sur le téléphone — part dès que le réseau revient.');
    setTimeout(function () { S.aller(retour); }, 900);
  }
  function lancer(accueilModules, ctx) { return accueilModules; }
  function accueilKpis(a, b, c, d) { return '<div class="kpis">' + [[a[0], a[1]], [b[0], b[1]], [c[0], c[1]], [d[0], d[1]]].map(function (k) { return '<div class="kpi"><div class="v">' + k[1] + '</div><div class="l">' + k[0] + '</div></div>'; }).join('') + '</div>'; }
  function enAttente() { return S.file().filter(function (o) { return o.etat === 'en_attente'; }).length; }
  function modules(ids, ctx) {
    return S.liste(ids.map(function (id) { var e = S.entree(id); return S.item({ titre: e.label, icone: e.icone, href: S.lien(id) }); }));
  }

  /* --- démarrage -------------------------------------------------------------------------------------------------- */
  E('appairage', function (ctx) {
    return { titre: 'Appairer ce téléphone', sansOnglets: true, html:
      '<img class="logo" src="../../assets/img/logo.jpeg" alt="">'
      + S.note('Demandez un <strong>code</strong> à la mère (DAF ou administrateur). Il ne sert <strong>qu’une fois</strong> et expire au bout de 15 minutes. Essayez <code>ABCD2345</code> (valide), <code>EXPIREE1</code> (expiré).', '', 'link')
      + S.carte('', S.champ('code', 'Code d’appairage', { requis: true, ph: 'ABCD2345' }) + S.champ('cle', 'Clé de clinique', { requis: true, ph: 'Scanner le QR', type: 'password' })
        + '<div style="height:10px"></div><button class="btn sec petit" id="scan">' + S.icone('qr-code') + 'Scanner le QR (simulation)</button>')
      + S.carte('Profil de ce téléphone', '<div class="segments" id="seg">' + ['soignant', 'medecin', 'sagefemme', 'reception'].map(function (p, i) { return '<button data-p="' + p + '" class="' + (p === ctx.profil ? 'actif' : '') + '">' + ({ soignant: 'Soignant', medecin: 'Médecin', sagefemme: 'Sage-f.', reception: 'Réception' })[p] + '</button>'; }).join('') + '</div>')
      + '<button class="btn" id="go">Appairer</button>',
      apres: function () {
        var profil = ctx.profil;
        document.getElementById('scan').onclick = function () { document.getElementById('cle').value = 'CLE-DEMO-9F2C-77A1'; S.toast('Clé lue (clé de démonstration).'); };
        Array.prototype.forEach.call(document.querySelectorAll('#seg button'), function (b) { b.onclick = function () { profil = b.dataset.p; Array.prototype.forEach.call(document.querySelectorAll('#seg button'), function (x) { x.classList.toggle('actif', x === b); }); }; });
        document.getElementById('go').onclick = function () {
          var c = S.valeur('code').toUpperCase(), ok = S.valider([{ id: 'code', requis: true, libelle: 'Le code' }, { id: 'cle', requis: true, libelle: 'La clé de clinique' }]);
          if (!ok) return;
          if (c === 'EXPIREE1') { S.erreur('code', 'Code expiré — demandez-en un nouveau à la mère.'); return; }
          if (!/^[A-Z0-9]{8}$/.test(c)) { S.erreur('code', 'Code invalide : 8 caractères (lettres et chiffres).'); return; }
          S.ecrire('appaire', true); S.ecrire('profil', profil); S.ecrire('lot', { depose: Date.now() - 5400000, expire: Date.now() + 36000000, dossiers: 4 });
          S.toast('Appairé. Le lot du jour arrive à la première synchronisation.');
          setTimeout(function () { global.location.href = 'verrou.php?os=' + ctx.os + '&profil=' + profil; }, 900);
        };
      } };
  });

  E('verrou', function (ctx) {
    return { titre: 'Code PIN', sansOnglets: true, html:
      '<div style="text-align:center;margin-top:8px">' + S.icone('lock') + '<p style="color:var(--ink-2)">Saisissez votre code à 4 chiffres.<br><span class="cle">Démonstration : 1234</span></p></div><div class="points" id="pts"><span></span><span></span><span></span><span></span></div>'
      + '<div id="msg" style="text-align:center;color:var(--err-700);min-height:20px;margin-bottom:8px"></div>'
      + '<div class="pin">' + ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'].map(function (k) { return k === '' ? '<span></span>' : '<button data-k="' + k + '">' + k + '</button>'; }).join('') + '</div>',
      apres: function () {
        var saisie = '', essais = 0;
        function pts() { Array.prototype.forEach.call(document.querySelectorAll('#pts span'), function (s, i) { s.classList.toggle('plein', i < saisie.length); }); }
        Array.prototype.forEach.call(document.querySelectorAll('.pin button'), function (b) {
          b.onclick = function () {
            if (essais >= 3) return;
            if (b.dataset.k === '⌫') saisie = saisie.slice(0, -1); else if (saisie.length < 4) saisie += b.dataset.k; pts();
            if (saisie.length === 4) {
              if (saisie === '1234') { global.location.href = S.lien(M.PROFILS[ctx.profil].accueil); return; }
              essais++; saisie = ''; pts();
              document.getElementById('msg').textContent = essais >= 3 ? 'Trop d’essais — réessayez dans 30 s.' : 'Code incorrect (' + essais + '/3).';
            }
          };
        });
      } };
  });

  /* --- accueils par profil ----------------------------------------------------------------------------------------- */
  E('accueil-soignant', function (ctx) {
    return { titre: 'Ma tournée', sous: M.PROFILS.soignant.agent, sansOnglets: false, html:
      accueilKpis(['Dossiers du lot', TOURNEE.length], ['Constantes à saisir', 2], ['En attente d’envoi', enAttente()], ['Validité du lot', '10 h'])
      + S.liste(TOURNEE.map(function (p) { return S.item({ titre: p.nom, detail: esc(p.rdv) + ' · ' + esc(p.quartier), icone: 'user', href: S.lien('dossier', { p: p.id }) }); }))
      + modules(['constantes'], ctx) };
  });
  E('accueil-medecin', function (ctx) {
    return { titre: 'Mes visites', sous: M.PROFILS.medecin.agent, html:
      accueilKpis(['Visites du jour', TOURNEE.length], ['Consultations saisies', S.file().filter(function (o) { return o.type === 'consultation'; }).length], ['En attente d’envoi', enAttente()], ['Analyses demandées', S.file().filter(function (o) { return o.type === 'analyses'; }).length])
      + S.liste(TOURNEE.map(function (p) { return S.item({ titre: p.nom, detail: esc(p.rdv) + ' · ' + esc(p.motif), icone: 'user', href: S.lien('dossier', { p: p.id }) }); }))
      + S.carte('Raccourcis', '') + modules(['consultation', 'prescription', 'demande-analyse', 'constantes'], ctx) };
  });
  E('accueil-sagefemme', function (ctx) {
    return { titre: 'Mes suivis', sous: M.PROFILS.sagefemme.agent, html:
      accueilKpis(['Femmes suivies', 2], ['CPN du jour', 1], ['Post-natales', 1], ['En attente d’envoi', enAttente()])
      + S.liste([TOURNEE[3], TOURNEE[1]].map(function (p) { return S.item({ titre: p.nom, detail: esc(p.motif) + ' · ' + esc(p.quartier), icone: 'baby', href: S.lien('dossier', { p: p.id }) }); }))
      + S.carte('Raccourcis', '') + modules(['cpn', 'cpon', 'surveillance', 'constantes'], ctx) };
  });
  E('accueil-reception', function (ctx) {
    var p = S.lire('plage', { prochain: 1241, fin: 1243 });
    return { titre: 'Accueil de secours', sous: M.PROFILS.reception.agent, html:
      S.note('Pour les <strong>coupures de courant</strong> : on ouvre les dossiers ici, ils rejoignent la clinique par le relais. La <strong>caisse</strong> et le dossier médical complet ne sont pas couverts par ce profil.', 'warn', 'zap-off')
      + accueilKpis(['Numéros réservés restants', Math.max(0, p.fin - p.prochain + 1)], ['Dossiers ouverts', S.dossiers().length], ['En attente d’envoi', enAttente()], ['Numéro suivant', esc(S.prochainCode().code)])
      + modules(['nouveau-dossier', 'dossiers-crees', 'orientation'], ctx) };
  });

  /* --- dossier et constantes ----------------------------------------------------------------------------------------- */
  E('dossier', function (ctx) {
    var p = patient(ctx.p);
    var dernieres = S.file().filter(function (o) { return o.type === 'constantes'; })[0];
    return { titre: p.nom, sous: p.code, retour: M.PROFILS[ctx.profil].accueil, html:
      S.carte('Identité', '<div class="deux"><div><div class="l">Âge</div><b>' + p.age + ' ans</b></div><div><div class="l">Quartier</div><b>' + esc(p.quartier) + '</b></div></div><div style="margin-top:8px"><div class="l">Téléphone</div><b>' + esc(p.tel) + '</b></div>')
      + S.carte('Couverture', assuranceBadge(p.assurance) + (p.assurance === 'expiree' ? '<p style="margin:8px 0 0;font-size:13px;color:var(--ink-2)">La prise en charge ne s’applique pas : facturation intégrale au patient (RG-09).</p>' : ''))
      + S.carte('Allergies', p.allergies === '—' ? 'Aucune connue.' : S.badge(p.allergies, 'err'))
      + S.carte('Motif de la visite', esc(p.motif) + '<div class="detail" style="color:var(--ink-2);margin-top:4px">' + esc(p.rdv) + '</div>')
      + S.carte('Dernières constantes', dernieres ? esc(dernieres.detail) + '<div class="cle">' + S.il(dernieres.quand) + '</div>' : 'Aucune saisie sur ce téléphone.')
      + '<div class="actions"><a class="btn" href="' + S.lien('constantes', { p: p.id }) + '">' + S.icone('heart-pulse') + 'Saisir les constantes</a>'
      + (ctx.profil === 'medecin' ? '<a class="btn sec" href="' + S.lien('consultation', { p: p.id }) + '">' + S.icone('clipboard-pen') + 'Consultation à domicile</a>' : '')
      + (ctx.profil === 'sagefemme' ? '<a class="btn sec" href="' + S.lien(p.id === 'p2' ? 'cpon' : 'cpn', { p: p.id }) + '">' + S.icone('baby') + (p.id === 'p2' ? 'Visite post-natale' : 'Visite prénatale') + '</a>' : '') + '</div>' };
  });

  E('constantes', function (ctx) {
    var p = patient(ctx.p);
    return { titre: 'Constantes', sous: p.nom, retour: 'dossier', retourExtra: { p: p.id }, html:
      '<div class="carte">' + S.champ('temperature', 'Température (°C)', { requis: true, inputmode: 'decimal', ph: '37,0' })
      + '<div class="deux">' + S.champ('sys', 'Tension — systolique', { inputmode: 'numeric', ph: '120' }) + S.champ('dia', 'diastolique', { inputmode: 'numeric', ph: '80' }) + '</div>'
      + '<div class="trois">' + S.champ('pouls', 'Pouls', { inputmode: 'numeric', ph: '76' }) + S.champ('fr', 'FR', { inputmode: 'numeric', ph: '18' }) + S.champ('spo2', 'SpO₂ %', { inputmode: 'numeric', ph: '98' }) + '</div>'
      + S.champ('poids', 'Poids (kg)', { inputmode: 'decimal', ph: '62' }) + '</div><div id="alerte"></div><button class="btn" id="ok">' + S.icone('check') + 'Enregistrer</button>',
      apres: function () {
        document.getElementById('ok').onclick = function () {
          var okk = S.valider([{ id: 'temperature', requis: true, nombre: [30, 45], libelle: 'La température' }, { id: 'sys', nombre: [50, 260], libelle: 'La systolique' }, { id: 'dia', nombre: [30, 160], libelle: 'La diastolique' }, { id: 'pouls', nombre: [20, 250], libelle: 'Le pouls' }, { id: 'fr', nombre: [5, 80], libelle: 'La FR' }, { id: 'spo2', nombre: [50, 100], libelle: 'La SpO₂' }, { id: 'poids', nombre: [0.5, 300], libelle: 'Le poids' }]);
          if (!okk) return;
          var t = Number(S.valeur('temperature').replace(',', '.')), txt = 'T° ' + t + (S.valeur('sys') ? ' · TA ' + S.valeur('sys') + '/' + S.valeur('dia') : '') + (S.valeur('pouls') ? ' · pouls ' + S.valeur('pouls') : '') + (S.valeur('spo2') ? ' · SpO₂ ' + S.valeur('spo2') + ' %' : '') + (S.valeur('poids') ? ' · ' + S.valeur('poids') + ' kg' : '');
          if (t >= 38) document.getElementById('alerte').innerHTML = S.note('<strong>Fièvre (' + t + ' °C).</strong> Signalée au médecin avec la saisie.', 'warn', 'thermometer');
          enregistrer('constantes', 'Constantes — ' + p.nom, txt, 'dossier');
        };
      } };
  });

  /* --- médecin ---------------------------------------------------------------------------------------------------- */
  E('consultation', function (ctx) {
    var p = patient(ctx.p);
    return { titre: 'Consultation à domicile', sous: p.nom, retour: 'dossier', retourExtra: { p: p.id }, html:
      S.note('Dossier → fiche → prescription : la <strong>prescription</strong> se fait après l’enregistrement de la fiche. Les constantes relevées ce jour sont reprises, jamais ressaisies.', '', 'route')
      + S.carte('', S.champ('motif', 'Motif', { requis: true, valeur: p.motif }) + S.champ('anamnese', 'Anamnèse', { type: 'textarea', ph: 'Histoire de la maladie…' })
        + '<div class="deux">' + S.champ('inspection', 'Inspection', { type: 'textarea' }) + S.champ('palpation', 'Palpation', { type: 'textarea' }) + S.champ('percussion', 'Percussion', { type: 'textarea' }) + S.champ('auscultation', 'Auscultation', { type: 'textarea' }) + '</div>'
        + S.champ('diagnostic', 'Diagnostic', { requis: true, type: 'select', options: ['Paludisme simple', 'Paludisme grave', 'Hypertension artérielle', 'Infection respiratoire aiguë', 'Gastro-entérite', 'Autre (à préciser)'] })
        + S.champ('orientation', 'Orientation', { type: 'select', options: ['Traitement à domicile', 'Revoir à la clinique', 'Référer / hospitaliser', 'Rendez-vous de contrôle'] }))
      + '<button class="btn" id="ok">' + S.icone('check') + 'Enregistrer la fiche</button>',
      apres: function () { document.getElementById('ok').onclick = function () { if (!S.valider([{ id: 'motif', requis: true, libelle: 'Le motif' }, { id: 'diagnostic', requis: true, libelle: 'Le diagnostic' }])) return; enregistrer('consultation', 'Consultation — ' + p.nom, S.valeur('diagnostic') + ' · ' + S.valeur('orientation'), 'dossier'); }; } };
  });
  E('prescription', function (ctx) {
    return { titre: 'Prescription', retour: 'accueil-medecin', html:
      S.note('Prescrire génère l’<strong>ordonnance</strong> et la <strong>facture de la caisse</strong>. Le patient règle à la caisse de la clinique ; la <strong>délivrance</strong> n’a lieu qu’après paiement (RG-03).', '', 'receipt')
      + S.carte('', choixPatient('pat', ctx) + S.champ('med', 'Médicament', { requis: true, ph: 'Paracétamol 500 mg' }) + '<div class="deux">' + S.champ('poso', 'Posologie', { requis: true, ph: '1 cp × 3/j' }) + S.champ('duree', 'Durée (jours)', { requis: true, inputmode: 'numeric', ph: '5' }) + '</div>')
      + '<button class="btn" id="ok">' + S.icone('check') + 'Enregistrer l’ordonnance</button>',
      apres: function () { document.getElementById('ok').onclick = function () { if (!S.valider([{ id: 'med', requis: true, libelle: 'Le médicament' }, { id: 'poso', requis: true, libelle: 'La posologie' }, { id: 'duree', requis: true, nombre: [1, 90], libelle: 'La durée' }])) return; enregistrer('ordonnance', 'Ordonnance — ' + S.valeur('pat').split(' — ')[0], S.valeur('med') + ' · ' + S.valeur('poso') + ' · ' + S.valeur('duree') + ' j', 'accueil-medecin'); }; } };
  });
  E('demande-analyse', function (ctx) {
    var ex = ['NFS', 'Glycémie', 'Goutte épaisse / TDR paludisme', 'CRP', 'Test de grossesse (TBG)', 'Créatininémie'];
    return { titre: 'Demande d’analyses', retour: 'accueil-medecin', html:
      S.note('<strong>Rien ne se prélève avant le paiement.</strong> La demande part par le relais, le patient règle à la caisse, puis passe à la salle de prélèvement.', 'warn', 'wallet')
      + S.carte('', choixPatient('pat', ctx) + '<div class="champ"><span>Examens demandés <em>*</em></span>' + ex.map(function (x, i) { return '<label style="display:flex;gap:10px;align-items:center;padding:8px 0;border-top:1px solid var(--line)"><input type="checkbox" class="ex" value="' + esc(x) + '" style="width:20px;height:20px"> ' + esc(x) + '</label>'; }).join('') + '<div class="erreur" id="err-ex" hidden></div></div>'
        + S.champ('urgence', 'Urgence', { type: 'select', options: ['Non urgent', 'Urgent — bilan entier', 'Urgent — examens cochés'] }))
      + '<button class="btn" id="ok">' + S.icone('send') + 'Envoyer la demande</button>',
      apres: function () { document.getElementById('ok').onclick = function () {
        var cochés = Array.prototype.filter.call(document.querySelectorAll('.ex'), function (c) { return c.checked; }).map(function (c) { return c.value; });
        var er = document.getElementById('err-ex'); er.hidden = cochés.length > 0; er.textContent = 'Cochez au moins un examen.'; er.style.color = 'var(--err-700)';
        if (!cochés.length) return;
        enregistrer('analyses', 'Analyses — ' + S.valeur('pat').split(' — ')[0], cochés.join(', ') + ' · ' + S.valeur('urgence'), 'accueil-medecin'); }; } };
  });

  /* --- sage-femme ------------------------------------------------------------------------------------------------- */
  E('cpn', function (ctx) {
    var p = patient(ctx.p || 'p4');
    return { titre: 'Visite prénatale (CPN)', sous: p.nom, retour: 'accueil-sagefemme', html:
      (p.age < 18 || p.age > 35 ? S.note('Âge à risque (hors 18–35 ans).', 'warn', 'triangle-alert') : '')
      + S.carte('Examen', '<div class="deux">' + S.champ('sa', 'Terme (SA)', { requis: true, inputmode: 'numeric', ph: '28' }) + S.champ('poids', 'Poids (kg)', { requis: true, inputmode: 'decimal' }) + '</div>'
        + '<div class="deux">' + S.champ('sys', 'TA systolique', { requis: true, inputmode: 'numeric' }) + S.champ('dia', 'diastolique', { requis: true, inputmode: 'numeric' }) + '</div>'
        + '<div class="deux">' + S.champ('hu', 'Hauteur utérine (cm)', { inputmode: 'decimal' }) + S.champ('bcf', 'BCF (/min)', { inputmode: 'numeric', ph: '140' }) + '</div>'
        + S.champ('presentation', 'Présentation', { type: 'select', options: ['Céphalique', 'Siège', 'Transversale', 'Non déterminée'] }))
      + S.carte('Prévention', S.champ('sp', 'SP / TPI — dose', { type: 'select', options: ['Aucune', 'SP 1', 'SP 2', 'SP 3', 'SP 4'] }) + S.champ('milda', 'MILDA remise', { type: 'select', options: ['Oui', 'Non'] }) + S.champ('proteinurie', 'Protéinurie', { type: 'select', options: ['Négative', 'Traces', '+', '++', '+++'] }))
      + S.champ('rdv', 'Prochain rendez-vous', { type: 'date' }) + '<button class="btn" id="ok">' + S.icone('check') + 'Enregistrer la visite</button>',
      apres: function () { document.getElementById('ok').onclick = function () {
        if (!S.valider([{ id: 'sa', requis: true, nombre: [4, 45], libelle: 'Le terme' }, { id: 'poids', requis: true, nombre: [30, 200], libelle: 'Le poids' }, { id: 'sys', requis: true, nombre: [60, 260], libelle: 'La systolique' }, { id: 'dia', requis: true, nombre: [30, 160], libelle: 'La diastolique' }, { id: 'bcf', nombre: [60, 220], libelle: 'Le BCF' }])) return;
        var alerte = Number(S.valeur('sys')) >= 140 || Number(S.valeur('dia')) >= 90 || S.valeur('proteinurie') === '++' || S.valeur('proteinurie') === '+++';
        if (alerte) S.toast('TA élevée ou protéinurie : signalée comme grossesse à risque.');
        enregistrer('cpn', 'CPN — ' + p.nom, S.valeur('sa') + ' SA · TA ' + S.valeur('sys') + '/' + S.valeur('dia') + (alerte ? ' · À RISQUE' : ''), 'accueil-sagefemme'); }; } };
  });
  E('cpon', function (ctx) {
    var p = patient(ctx.p || 'p2');
    return { titre: 'Visite post-natale (CPoN)', sous: p.nom, retour: 'accueil-sagefemme', html:
      S.carte('Mère', S.champ('jour', 'Jour post-natal', { requis: true, type: 'select', options: ['J1', 'J3', 'J7', 'J14', 'J42'] }) + '<div class="deux">' + S.champ('ta', 'TA (ex. 12/8)', { requis: true }) + S.champ('t', 'T° (°C)', { requis: true, inputmode: 'decimal' }) + '</div>'
        + S.champ('lochies', 'Lochies', { type: 'select', options: ['Normales', 'Abondantes', 'Malodorantes'] }) + S.champ('uterus', 'Involution utérine', { type: 'select', options: ['Normale', 'Insuffisante'] }))
      + S.carte('Nouveau-né', '<div class="deux">' + S.champ('pb', 'Poids (g)', { requis: true, inputmode: 'numeric' }) + S.champ('cordon', 'Cordon', { type: 'select', options: ['Propre et sec', 'Suintant', 'Infecté'] }) + '</div>' + S.champ('allait', 'Allaitement', { type: 'select', options: ['Exclusif', 'Mixte', 'Difficulté'] }))
      + '<button class="btn" id="ok">' + S.icone('check') + 'Enregistrer</button>',
      apres: function () { document.getElementById('ok').onclick = function () { if (!S.valider([{ id: 'ta', requis: true, libelle: 'La TA' }, { id: 't', requis: true, nombre: [34, 43], libelle: 'La température' }, { id: 'pb', requis: true, nombre: [1000, 6000], libelle: 'Le poids du bébé' }])) return; enregistrer('cpon', 'CPoN ' + S.valeur('jour') + ' — ' + p.nom, 'T° ' + S.valeur('t') + ' · cordon ' + S.valeur('cordon').toLowerCase(), 'accueil-sagefemme'); }; } };
  });
  E('surveillance', function (ctx) {
    return { titre: 'Surveillance mère-bébé', retour: 'accueil-sagefemme', html:
      S.note('Une seule grille de temps pour la <strong>mère ET le bébé</strong> : c’est la coïncidence des deux séries qui fait la valeur de la feuille.', '', 'activity')
      + S.carte('', S.champ('heure', 'Temps', { type: 'select', options: ['H4', 'H8', 'H12', 'H16', 'H20', 'H24'] }) + '<h2 style="margin-top:12px">Mère</h2><div class="trois">' + S.champ('mta', 'TA') + S.champ('mpouls', 'Pouls', { inputmode: 'numeric' }) + S.champ('saign', 'Saignement', { type: 'select', options: ['Normal', 'Abondant'] }) + '</div>'
        + '<h2>Bébé</h2><div class="trois">' + S.champ('bfr', 'FR', { inputmode: 'numeric' }) + S.champ('bt', 'T°', { inputmode: 'decimal' }) + S.champ('bcordon', 'Cordon', { type: 'select', options: ['Sec', 'Suintant'] }) + '</div>')
      + '<button class="btn" id="ok">' + S.icone('check') + 'Enregistrer ce temps</button>',
      apres: function () { document.getElementById('ok').onclick = function () { if (!S.valider([{ id: 'mpouls', nombre: [30, 220], libelle: 'Le pouls' }, { id: 'bfr', nombre: [10, 100], libelle: 'La FR du bébé' }, { id: 'bt', nombre: [34, 41], libelle: 'La T° du bébé' }])) return; enregistrer('surveillance', 'Surveillance ' + S.valeur('heure'), 'mère ' + (S.valeur('mta') || '—') + ' · bébé FR ' + (S.valeur('bfr') || '—'), 'accueil-sagefemme'); }; } };
  });

  /* --- réception de secours -------------------------------------------------------------------------------------- */
  E('nouveau-dossier', function (ctx) {
    var c = S.prochainCode();
    return { titre: 'Nouveau dossier', retour: 'accueil-reception', html:
      S.note('Numéro réservé : <strong>' + esc(c.code) + '</strong>' + (c.provisoire ? ' — <strong>provisoire</strong> : plage épuisée, il sera réconcilié à l’arrivée.' : ' (plage de ce téléphone).'), c.provisoire ? 'warn' : '', 'hash')
      + S.carte('', '<div class="deux">' + S.champ('nom', 'Nom', { requis: true }) + S.champ('prenom', 'Prénom', { requis: true }) + '</div>'
        + '<div class="deux">' + S.champ('age', 'Âge déclaré', { requis: true, inputmode: 'numeric' }) + S.champ('sexe', 'Sexe', { type: 'select', options: ['Féminin', 'Masculin'] }) + '</div>'
        + S.champ('tel', 'Téléphone', { type: 'tel' }) + S.champ('quartier', 'Quartier') + S.champ('motif', 'Motif de venue', { type: 'select', options: ['Urgence', 'Consultation', 'Accouchement', 'Analyses', 'Autre'] }))
      + '<div id="doublon"></div><button class="btn" id="ok">' + S.icone('user-plus') + 'Ouvrir le dossier</button>',
      apres: function () { document.getElementById('ok').onclick = function () {
        if (!S.valider([{ id: 'nom', requis: true, libelle: 'Le nom' }, { id: 'prenom', requis: true, libelle: 'Le prénom' }, { id: 'age', requis: true, nombre: [0, 120], libelle: 'L’âge' }])) return;
        var nom = S.valeur('nom').toUpperCase(), prenom = S.valeur('prenom'), age = Number(S.valeur('age'));
        var doublon = S.dossiers().some(function (d) { return d.nom === nom && d.prenom.toLowerCase() === prenom.toLowerCase() && d.age === age; }) || (nom === 'AKPO' && prenom.toLowerCase() === 'marc' && age === 34);
        var code = S.prochainCode(); S.consommerCode();
        S.ajouterDossier({ id: 'd' + Date.now(), code: code.code, provisoire: code.provisoire, nom: nom, prenom: prenom, age: age, quartier: S.valeur('quartier'), motif: S.valeur('motif'), quand: Date.now(), doublon: doublon });
        S.enfiler('dossier', 'Dossier — ' + nom + ' ' + prenom, code.code + (doublon ? ' · DOUBLON POSSIBLE signalé à la mère' : ''));
        if (doublon) document.getElementById('doublon').innerHTML = S.note('<strong>Homonyme possible.</strong> Le dossier est <strong>enregistré quand même</strong> (on ne bloque pas un patient devant le guichet) ; la mère arbitre.', 'warn', 'copy');
        S.toast('Dossier ' + code.code + ' ouvert.'); setTimeout(function () { S.aller('dossiers-crees'); }, doublon ? 2200 : 900); }; } };
  });
  E('dossiers-crees', function () {
    var l = S.dossiers();
    return { titre: 'Dossiers ouverts', retour: 'accueil-reception', html: l.length ? S.liste(l.map(function (d) { return S.item({ titre: d.nom + ' ' + d.prenom, detail: esc(d.code) + ' · ' + esc(d.motif) + ' · ' + S.il(d.quand), icone: 'user', fin: d.doublon ? S.badge('Doublon ?', 'warn') : (d.provisoire ? S.badge('PROV', 'warn') : S.badge('Ouvert', 'ok')) }); })) : S.vide('users', 'Aucun dossier ouvert depuis ce téléphone.') };
  });
  E('orientation', function () {
    var l = S.dossiers();
    return { titre: 'Orienter un patient', retour: 'accueil-reception', html: l.length
      ? S.carte('', S.champ('pat', 'Patient', { type: 'select', options: l.map(function (d) { return d.nom + ' ' + d.prenom + ' — ' + d.code; }) }) + S.champ('dest', 'Orienter vers', { type: 'select', options: ['Médecin de garde', 'Laboratoire', 'Salle de soins', 'Maternité', 'Caisse (dès retour du courant)', 'Référence vers un autre établissement'] }) + S.champ('urg', 'Degré', { type: 'select', options: ['Normal', 'Urgent', 'Très urgent'] })) + '<button class="btn" id="ok">' + S.icone('send') + 'Envoyer l’orientation</button>'
      : S.vide('signpost', 'Ouvrez d’abord un dossier.'),
      apres: function () { var b = document.getElementById('ok'); if (b) b.onclick = function () { enregistrer('orientation', 'Orientation — ' + S.valeur('pat').split(' — ')[0], S.valeur('dest') + ' · ' + S.valeur('urg'), 'accueil-reception'); }; } };
  });

  /* --- téléphone ---------------------------------------------------------------------------------------------------- */
  E('sync', function () {
    var f = S.file();
    return { titre: 'Synchronisation', html:
      S.carte('État', (S.enLigne() ? S.badge('Connecté', 'ok') : S.badge('Hors ligne', 'warn')) + '<p style="margin:10px 0 0;color:var(--ink-2);font-size:13px">' + (S.enLigne() ? 'Vos saisies partent par le relais ; la mère les relève et accuse réception.' : 'Rien ne se perd : tout est gardé sur le téléphone et part au retour du réseau.') + '</p>')
      + '<div class="actions"><button class="btn sec" id="force">' + S.icone('refresh-cw') + 'Synchroniser maintenant</button></div>'
      + (f.length ? S.liste(f.slice(0, 20).map(function (o) { return S.item({ titre: o.libelle, detail: esc(o.detail) + ' · ' + S.il(o.quand), icone: 'send', fin: etatBadge(o.etat) }); })) : S.vide('inbox', 'Rien dans la file d’envoi.')),
      apres: function () { document.getElementById('force').onclick = function () { if (!S.enLigne()) { S.toast('Hors ligne : rien ne peut partir.'); return; } S.vider(); S.toast('Synchronisé.'); setTimeout(function () { global.location.reload(); }, 500); }; } };
  });
  E('a-traiter', function () {
    var refus = S.lire('refus', [{ op: 'Facture · FC-PROV-3', code: 'PROFIL_NON_COUVERT', motif: 'Le profil « réception de secours » ne couvre pas la caisse.', geste: 'Ressaisir la facture à la caisse de la clinique.' }]);
    return { titre: 'À traiter', html: refus.length ? S.note('Chaque refus dit <strong>pourquoi</strong> et <strong>quoi faire</strong>. Rien n’est perdu : l’opération reste sur ce téléphone.', '', 'info') + S.liste(refus.map(function (r) { return S.item({ titre: r.op, detail: '<code>' + esc(r.code) + '</code><br>' + esc(r.motif) + '<br><b>' + esc(r.geste) + '</b>', icone: 'octagon-alert', fin: '' }); })) : S.vide('check-check', 'Aucun refus.') };
  });
  E('lot', function () {
    var l = S.lire('lot', { depose: Date.now() - 5400000, expire: Date.now() + 36000000, dossiers: 4 });
    var h = Math.max(0, Math.round((l.expire - Date.now()) / 3600000));
    return { titre: 'Lot de tournée', html:
      S.carte('Lot du jour', '<div class="kpis"><div class="kpi"><div class="v">' + l.dossiers + '</div><div class="l">Dossiers</div></div><div class="kpi"><div class="v">' + h + ' h</div><div class="l">Validité restante</div></div></div>')
      + S.note('Le lot est <strong>chiffré</strong> et <strong>expire</strong> : passé le délai, les dossiers s’effacent du téléphone — <strong>sauf ce qui n’est pas encore parti</strong>.', 'warn', 'timer')
      + S.liste(TOURNEE.map(function (p) { return S.item({ titre: p.nom, detail: esc(p.code), icone: 'user', href: S.lien('dossier', { p: p.id }) }); })) };
  });
  E('parametres', function (ctx) {
    var P = M.PROFILS[ctx.profil];
    return { titre: 'Réglages', html:
      S.carte('Ce téléphone', '<div class="deux"><div><div class="l">Profil</div><b>' + esc(P.label) + '</b></div><div><div class="l">Agent</div><b>' + esc(P.agent) + '</b></div></div><div style="margin-top:10px" class="cle">Appareil u-0' + (ctx.profil === 'soignant' ? 6 : 7) + ' · version 1.0.1 · schéma v66</div>')
      + S.liste([S.item({ titre: 'Verrouillage automatique', detail: 'après 5 minutes d’inactivité', icone: 'lock', fin: S.badge('Activé', 'ok') }), S.item({ titre: 'Effacement à distance', detail: 'à la révocation, au prochain contact', icone: 'shield-alert', fin: S.badge('Actif', 'ok') }), S.item({ titre: 'Notifications', detail: 'réveil seulement — aucune donnée de santé', icone: 'bell', fin: S.badge('Activées', 'ok') })])
      + '<div class="actions"><button class="btn danger" id="reset">' + S.icone('unlink') + 'Réinitialiser l’appairage</button></div>',
      apres: function () { document.getElementById('reset').onclick = function () { if (global.confirm('Les saisies non envoyées seront EXPORTÉES avant effacement. Continuer ?')) { S.ecrire('appaire', false); S.aller('appairage'); } }; } };
  });
})(window);
