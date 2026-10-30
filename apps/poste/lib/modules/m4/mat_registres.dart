import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mat_commun.dart';
import 'mat_crud.dart';

/// Les registres de la maternité (M4) — `K.crud` de la maquette : suivi de grossesse, accouchements, naissances, dossier bébé, décès, CPN, CPoN,
/// planification familiale, SONUB/SONUC, PTME, soins curatifs. Les RÈGLES sont dans `packages/domaine/lib/src/maternite/mat_regles.dart`
/// et rejouées sur les vecteurs de la maquette ; ici, les écrans.

// ---- Colonnes ------------------------------------------------------------------------------------------------------------------------------

ColonneTableau _colRef(String lib, {String cle = 'reference'}) => ColonneTableau(
    cle: cle, libelle: lib, sansCoupure: true, texte: (r) => '${r[cle] ?? ''}', rendu: (_, r) => matRef(r[cle]));

ColonneTableau _colDate(String cle, String lib) =>
    ColonneTableau(cle: cle, libelle: lib, sansCoupure: true, texte: (r) => matDateFR(r[cle]), rendu: (_, r) => Text(matDateFR(r[cle])));

ColonneTableau _colDateHeure(String cle, String lib) => ColonneTableau(
    cle: cle,
    libelle: lib,
    sansCoupure: true,
    valeur: (r) => matMs(r[cle]),
    texte: (r) => matDateHeure(r[cle]),
    rendu: (_, r) => Text(matDateHeure(r[cle])));

/// Nom au-dessus, code en police fixe en dessous.
ColonneTableau _colPatient(String lib, {String nom = 'patient', String code = 'patientCode'}) => ColonneTableau(
    cle: nom,
    libelle: lib,
    texte: (r) => '${r[nom] ?? ''} ${r[code] ?? ''}',
    rendu: (_, r) => matCelPatient('${r[nom] ?? ''}', '${r[code] ?? ''}'));

/// « Nom — CODE » sur une ligne.
ColonneTableau _colPatientLigne(String lib, {String nom = 'patient', String code = 'patientCode'}) =>
    ColonneTableau(cle: nom, libelle: lib, texte: (r) => '${r[nom] ?? ''} — ${r[code] ?? ''}');

ColonneTableau _colBadge(String cle, String lib, String Function(Fiche) texte, TonSigh Function(Fiche) ton) => ColonneTableau(
    cle: cle, libelle: lib, texte: texte, rendu: (_, r) => BadgeSigh(texte(r), ton: ton(r)));

/// Badge ou, sinon, mention discrète (« — », « Non », « Aucune »).
ColonneTableau _colOuiBadge(String cle, String lib, bool Function(Fiche) oui, String texteOui, TonSigh tonOui, String texteNon,
        {TonSigh? tonNon}) =>
    ColonneTableau(
        cle: cle,
        libelle: lib,
        texte: (r) => oui(r) ? texteOui : texteNon,
        rendu: (_, r) => oui(r)
            ? BadgeSigh(texteOui, ton: tonOui)
            : (tonNon != null ? BadgeSigh(texteNon, ton: tonNon) : matMuet(texteNon)));

FiltreTableau _filtreOuiNon(String nom, String lib, String oui, String non, bool Function(Fiche) test) => FiltreTableau(
    nom: nom,
    libelle: lib,
    options: [OptionChamp('oui', oui), OptionChamp('non', non)],
    correspond: (r, v) => v == 'oui' ? test(r) : !test(r));

List<OptionChamp> _opts(Iterable<String> l) => [for (final x in l) OptionChamp(x)];

KpiSigh _kpi(String lib, String val, IconData ic, TonSigh ton, [String? indice]) =>
    KpiSigh(libelle: lib, valeur: val, icone: ic, ton: ton, indice: indice);

num _n(Object? v) => matNum(v) ?? 0;

/// Remplace les valeurs de formulaire (textes) par les valeurs enregistrables : nombres lus, listes vides conservées.
Fiche _nombres(Fiche v, Iterable<String> cles) {
  for (final k in cles) {
    if (v.containsKey(k)) v[k] = matNombreSaisi(v[k]);
  }
  return v;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-maternite — Suivi maternité
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranSuiviMaternite extends StatelessWidget with EcranMaquette {
  const EcranSuiviMaternite({super.key});
  @override
  String get titre => 'Suivi maternité';
  @override
  String get description => 'Consultations prénatales, terme, date prévue d’accouchement et niveau de risque obstétrical.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    return CrudMat(
      collection: c.magasin.collection('suiviMaternite'),
      entite: 'suivi de grossesse',
      entiteP: 'suivis de grossesse',
      prefixeId: 'SUI',
      triInitial: 'dpa',
      taillePage: 12,
      colonnes: [
        _colPatient('Patiente'),
        ColonneTableau(
            cle: 'termeSA', libelle: 'Terme (SA)', droite: true, valeur: (r) => matNum(r['termeSA']), texte: (r) => '${matTexteNombre(r['termeSA'])} SA'),
        _colDate('dpa', 'Date prévue'),
        ColonneTableau(
            cle: 'restant',
            libelle: 'Échéance',
            droite: true,
            valeur: (r) => _jours(r, auj),
            texte: (r) => '${_jours(r, auj)} j',
            rendu: (_, r) {
              final j = _jours(r, auj);
              if (j < 0) return const BadgeSigh('Terme dépassé', ton: TonSigh.danger);
              if (j <= 14) return BadgeSigh('Dans $j j', ton: TonSigh.attention);
              return Text('$j j', style: const TextStyle(color: JetonsShell.slate600, fontSize: 14));
            }),
        ColonneTableau(cle: 'cpn', libelle: 'CPN réalisées', droite: true, texte: (r) => matTexteNombre(r['cpn'])),
        const ColonneTableau(cle: 'groupeSanguin', libelle: 'Groupe'),
        _colBadge('risque', 'Risque', (r) => '${r['risque'] ?? ''}', (r) => r['risque'] == 'Élevé' ? TonSigh.danger : TonSigh.succes),
        const ColonneTableau(cle: 'sageFemme', libelle: 'Sage-femme'),
        const ColonneTableau(cle: 'observations', libelle: 'Observations'),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Patiente', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        const ChampDef(nom: 'termeSA', libelle: 'Terme (semaines d’aménorrhée)', type: TypeChamp.nombre, requis: true),
        const ChampDef(
            nom: 'poids',
            libelle: 'Poids de la patiente (kg)',
            type: TypeChamp.nombre,
            requis: true,
            aide: 'Obligatoire — rapport du 27/08/2026 : l’admission se bloque sans le poids.'),
        const ChampDef(nom: 'dpa', libelle: 'Date prévue d’accouchement', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'cpn', libelle: 'Consultations prénatales réalisées', type: TypeChamp.nombre),
        ChampDef(nom: 'groupeSanguin', libelle: 'Groupe sanguin', type: TypeChamp.select, options: _opts(matGroupesSanguins)),
        ChampDef(nom: 'risque', libelle: 'Niveau de risque', type: TypeChamp.select, requis: true, options: _opts(const ['Standard', 'Élevé'])),
        ChampDef(nom: 'sageFemme', libelle: 'Sage-femme référente', type: TypeChamp.select, options: matSagesFemmes(m)),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      valeursInitiales: () => {},
      refuser: (v) {
        // Le verrou du rapport (Module A) : l'âge vient du dossier patient — s'il y manque, l'admission se refuse en disant OÙ corriger.
        final p = matFemmes(c.magasin).where((x) => x['code'] == v['patientCode']).firstOrNull;
        return matRefusAdmission(
            patientCode: '${v['patientCode']}',
            dateNaissanceConnue: p == null || (p['dateNaissance'] != null && p['dateNaissance'] != ''),
            poids: v['poids']);
      },
      transformer: (ctx, v) => matSansNuls(_nombres(matRattacher(v, matFemmes(c.magasin)), const ['termeSA', 'poids', 'cpn'])),
      transformerExistante: (ctx, v, e) => matSansNuls(_nombres(matRattacher(v, matFemmes(c.magasin)), const ['termeSA', 'poids', 'cpn'])),
      filtres: [FiltreTableau(nom: 'risque', libelle: 'Niveau de risque', options: _opts(const ['Standard', 'Élevé']))],
      kpis: (ctx, rows) => [
        _kpi('Grossesses suivies', matNombre(rows.length), LucideIcons.baby, TonSigh.navy),
        _kpi('Accouchements sous 15 jours', matNombre(rows.where((r) { final j = _jours(r, auj); return j >= 0 && j <= 15; }).length),
            LucideIcons.calendarClock, TonSigh.attention),
        _kpi('Grossesses à risque', matNombre(rows.where((r) => r['risque'] == 'Élevé').length), LucideIcons.heartPulse, TonSigh.danger),
        _kpi('CPN moyennes', rows.isEmpty ? '0' : (rows.fold<num>(0, (a, r) => a + _n(r['cpn'])) / rows.length).toStringAsFixed(1),
            LucideIcons.clipboardCheck, TonSigh.succes),
      ],
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Fiche de suivi de grossesse',
          cartouche: [
            ('Patiente', '${r['patient']}'),
            ('Dossier', '${r['patientCode']}'),
            ('Terme', '${matTexteNombre(r['termeSA'])} SA'),
            ('Date prévue', matDateFR(r['dpa'])),
            ('Groupe sanguin', '${r['groupeSanguin'] ?? ''}'),
            ('Risque', '${r['risque'] ?? ''}'),
          ],
          blocs: [
            matBlocRubriques([
              ('Consultations prénatales réalisées', matTexteNombre(r['cpn'])),
              ('Sage-femme référente', '${r['sageFemme'] ?? ''}'),
              ('Observations cliniques', '${r['observations'] ?? ''}'),
              ('Niveau de risque obstétrical', '${r['risque'] ?? ''}'),
            ])
          ],
          signatures: [Signature('La Sage-femme', nom: '${r['sageFemme'] ?? ''}'), const Signature('Le Médecin')]),
    );
  }

  static int _jours(Fiche r, DateTime auj) {
    final d = DateTime.tryParse('${r['dpa'] ?? ''}');
    return d == null ? 0 : matJoursEntre(auj, d);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-accouchements
// ---------------------------------------------------------------------------------------------------------------------------------------------

void _certificatRepos(BuildContext ctx, Fiche r) {
  final t = '${r['type'] ?? r['voie'] ?? ''}';
  matImprimer(ctx,
      titre: 'CERTIFICAT DE REPOS',
      sousTitre: 'Post-partum — ${r['reference']}',
      filigrane: 'Document officiel',
      cartouche: [
        ('Patiente', '${r['patient']}'),
        ('Dossier', '${r['patientCode']}'),
        ('Accouchement du', matDateHeure(r['dateHeure'])),
        ('Type', t),
        ('Praticien', '${r['sageFemme'] ?? ''}'),
        ('Référence', '${r['reference']}'),
      ],
      blocs: [
        const BlocTexte('Le praticien soussigné certifie avoir assisté l’accouchement de la patiente désignée ci-dessus et prescrit un repos post-partum conforme aux suites de couches.'),
        BlocTexte('Un repos est prescrit à compter du ${matDateFR(r['dateHeure'])}, sauf complication nécessitant une réévaluation.'),
        const BlocTexte('Délivré pour servir et valoir ce que de droit.', italique: true),
      ],
      signatures: [Signature('La Sage-femme', nom: '${r['sageFemme'] ?? ''}', mention: 'Signature et cachet'), const Signature('Le Médecin')]);
}

class EcranAccouchements extends StatelessWidget with EcranMaquette {
  const EcranAccouchements({super.key});
  @override
  String get titre => 'Accouchements';
  @override
  String get description => 'Enregistrement des accouchements : voie, durée du travail, complications et issue.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    String type(Fiche r) => '${r['type'] ?? r['voie'] ?? ''}';
    Fiche fiche(Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      final col = c.magasin.collection('accouchements').toutes;
      v['reference'] = e?['reference'] ?? matReferenceSuivante('ACC-', col);
      v['voie'] = v['type'] == 'Césarienne' ? 'Césarienne' : 'Voie basse';
      matRecomposerDateHeure(v, 'dateHeure');
      return matSansNuls(v);
    }

    return CrudMat(
      collection: c.magasin.collection('accouchements'),
      entite: 'accouchement',
      entiteP: 'accouchements',
      prefixeId: 'ACC',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      colonnes: [
        _colRef('N°'),
        _colDateHeure('dateHeure', 'Date et heure'),
        _colPatient('Parturiente'),
        ColonneTableau(
            cle: 'type',
            libelle: 'Type',
            texte: type,
            rendu: (_, r) => BadgeSigh(type(r), ton: type(r) == 'Césarienne' || type(r) == 'Dystocique' ? TonSigh.attention : TonSigh.succes)),
        ColonneTableau(
            cle: 'actes',
            libelle: 'Actes associés',
            texte: (r) => ((r['actes'] as List?) ?? const []).isEmpty ? '—' : ((r['actes'] as List).join(', ')),
            rendu: (_, r) {
              final a = ((r['actes'] as List?) ?? const []).cast<Object?>();
              return a.isEmpty ? matMuet('—') : matBadges([for (final x in a) ('$x', TonSigh.info)]);
            }),
        const ColonneTableau(cle: 'duree', libelle: 'Durée du travail', droite: true),
        ColonneTableau(
            cle: 'complications',
            libelle: 'Complications',
            texte: (r) => '${r['complications'] ?? ''}',
            rendu: (_, r) => r['complications'] == 'Aucune' ? matMuet('Aucune') : BadgeSigh('${r['complications'] ?? ''}', ton: TonSigh.danger)),
        const ColonneTableau(cle: 'sageFemme', libelle: 'Praticien'),
        _colBadge('issue', 'Issue', (r) => '${r['issue'] ?? ''}', (r) => r['issue'] == 'Favorable' ? TonSigh.succes : TonSigh.danger),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Parturiente', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        ...matChampsDateHeure('dateHeure', 'Date et heure'),
        ChampDef(
            nom: 'type',
            libelle: 'Type d’accouchement',
            type: TypeChamp.select,
            requis: true,
            options: _opts(matTypesAccouchement),
            aide: 'Nomenclature de la cible : eutocique, dystocique, dirigé, gemellaire, trimellaire, césarienne.'),
        ChampDef(
            nom: 'actes',
            libelle: 'Actes associés',
            type: TypeChamp.multiselect,
            options: _opts(matActesAccouchement),
            aide: 'Épisiotomie, délivrance artificielle, révision utérine, AMIU, ventouse, GATPA.'),
        const ChampDef(nom: 'duree', libelle: 'Durée du travail', indicatif: 'ex. 6 h'),
        ChampDef(nom: 'sageFemme', libelle: 'Praticien', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
        ChampDef(
            nom: 'complications',
            libelle: 'Complications',
            type: TypeChamp.select,
            options: _opts(const ['Aucune', 'Hémorragie de la délivrance', 'Souffrance fœtale', 'Dystocie', 'Éclampsie'])),
        ChampDef(nom: 'issue', libelle: 'Issue', type: TypeChamp.select, requis: true, options: _opts(const ['Favorable', 'Défavorable'])),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      valeursInitiales: () => {'type': 'Eutocique', 'voie': 'Voie basse', 'issue': 'Favorable', 'complications': 'Aucune'},
      valeursEdition: (f) => matValeursEdition(f, const ['dateHeure']),
      transformer: (ctx, v) => fiche(v, null),
      transformerExistante: (ctx, v, e) => fiche(v, e),
      filtres: [
        FiltreTableau(nom: 'type', libelle: 'Type', options: _opts(matTypesAccouchement), correspond: (r, v) => type(r) == v),
        FiltreTableau(nom: 'issue', libelle: 'Issue', options: _opts(const ['Favorable', 'Défavorable'])),
      ],
      referenceToast: (f) => '${f['reference'] ?? ''}',
      detail: (ctx, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DescListeSigh([
          ('Référence', '${r['reference']}'),
          ('Parturiente', '${r['patient']} — ${r['patientCode']}'),
          ('Date et heure', matDateHeure(r['dateHeure'])),
          ('Type', type(r)),
          ('Actes associés', ((r['actes'] as List?) ?? const []).isEmpty ? '—' : (r['actes'] as List).join(', ')),
          ('Durée du travail', matOuTiret(r['duree'])),
          ('Complications', '${r['complications'] ?? ''}'),
          ('Praticien', '${r['sageFemme'] ?? ''}'),
          ('Issue', '${r['issue'] ?? ''}'),
        ]),
        const SizedBox(height: 16),
        BoutonSigh(
            libelle: 'Certificat de repos post-partum',
            icone: LucideIcons.fileBadge,
            variante: VarianteBouton.secondaire,
            onPressed: () => _certificatRepos(ctx, r)),
      ]),
      kpis: (ctx, rows) {
        final cesar = rows.where((r) => r['voie'] == 'Césarienne').length;
        return [
          _kpi('Accouchements', matNombre(rows.length), LucideIcons.baby, TonSigh.navy),
          _kpi('Césariennes', matNombre(cesar), LucideIcons.scissors, TonSigh.attention, '${matPct(cesar, rows.length)} des accouchements'),
          _kpi('Avec complications', matNombre(rows.where((r) => r['complications'] != 'Aucune').length), LucideIcons.triangleAlert, TonSigh.danger),
          _kpi('Issues favorables', matPct(rows.where((r) => r['issue'] == 'Favorable').length, rows.length), LucideIcons.heart, TonSigh.succes),
        ];
      },
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Fiche d’accouchement',
          sousTitre: '${r['reference']}',
          cartouche: [
            ('Parturiente', '${r['patient']}'),
            ('Dossier', '${r['patientCode']}'),
            ('Date et heure', matDateHeure(r['dateHeure'])),
            ('Voie', '${r['voie'] ?? ''}'),
            ('Praticien', '${r['sageFemme'] ?? ''}'),
            ('Issue', '${r['issue'] ?? ''}'),
          ],
          blocs: [
            matBlocRubriques([
              ('Durée du travail', matOuTiret(r['duree'])),
              ('Complications constatées', '${r['complications'] ?? ''}'),
              ('Observations', matOuTiret(r['observations'])),
            ])
          ],
          signatures: [Signature('La Sage-femme', nom: '${r['sageFemme'] ?? ''}'), const Signature('Le Médecin')]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-naissances et m4-dossier-bebe — UN formulaire pour deux écrans
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<ChampDef> _champsNaissance(Magasin m) {
  final b = matBornesNouveauNe;
  return [
    ChampDef(nom: 'mereCode', libelle: 'Dossier de la mère', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
    ...matChampsDateHeure('dateHeure', 'Date et heure de naissance'),
    const ChampDef(
        nom: 'sexe',
        libelle: 'Sexe du nouveau-né',
        type: TypeChamp.select,
        requis: true,
        options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')]),
    const ChampDef(nom: 'vivant', libelle: 'Né vivant', type: TypeChamp.case_),
    const ChampDef.section('Biométrie — PC et PT obligatoires (rapport du 27/08/2026)'),
    const ChampDef(nom: 'poids', libelle: 'Poids (kg)', type: TypeChamp.nombre, requis: true),
    const ChampDef(nom: 'taille', libelle: 'Taille (cm)', type: TypeChamp.nombre),
    ChampDef(
        nom: 'pc',
        libelle: 'Périmètre crânien — PC (cm)',
        type: TypeChamp.nombre,
        requis: true,
        aide: 'Bornes physiologiques ${matTexteNombre(b.pcMin)}–${matTexteNombre(b.pcMax)} cm : hors bornes, le dossier est signalé (micro/macrocéphalie).'),
    ChampDef(
        nom: 'pt',
        libelle: 'Périmètre thoracique — PT (cm)',
        type: TypeChamp.nombre,
        requis: true,
        aide: 'Bornes physiologiques ${matTexteNombre(b.ptMin)}–${matTexteNombre(b.ptMax)} cm.'),
    const ChampDef.section('Apgar et réanimation'),
    const ChampDef(nom: 'apgar1', libelle: 'Apgar à 1 min (/10)', type: TypeChamp.nombre, requis: true),
    const ChampDef(
        nom: 'apgar5',
        libelle: 'Apgar à 5 min (/10)',
        type: TypeChamp.nombre,
        requis: true,
        aide: 'Un Apgar à 5 min inférieur à 7 déclenche l’alerte de sécurité clinique.'),
    const ChampDef(nom: 'apgar10', libelle: 'Apgar à 10 min (/10)', type: TypeChamp.nombre),
    const ChampDef(
        nom: 'reanimation',
        libelle: 'Réanimation néonatale effectuée',
        type: TypeChamp.case_,
        aide: 'Se rattache à la fonction 7 SONU (réanimation du nouveau-né).'),
    const ChampDef.section('Soins essentiels et vaccins de naissance'),
    const ChampDef(nom: 'vitK1', libelle: 'Vitamine K1 administrée', type: TypeChamp.case_),
    const ChampDef(nom: 'collyre', libelle: 'Collyre tétracycline', type: TypeChamp.case_),
    const ChampDef(nom: 'vpo0', libelle: 'Polio oral (VPO0)', type: TypeChamp.case_),
    const ChampDef(nom: 'bcg', libelle: 'BCG', type: TypeChamp.case_),
    const ChampDef(nom: 'hepB0', libelle: 'Hépatite B (J0)', type: TypeChamp.case_),
    const ChampDef(nom: 'declare', libelle: 'Déclaré à l’état civil', type: TypeChamp.case_),
  ];
}

/// `transformNaissance` : la mère est rattachée, la référence suit le registre, l'alerte néonatale reste GÉNÉRIQUE (aucune donnée médicale).
Fiche _fiche_naissance(BuildContext ctx, Fiche v, Fiche? existante) {
  final c = ContexteEcran.of(ctx);
  final m = matFemmes(c.magasin).where((x) => x['code'] == v['mereCode']).firstOrNull;
  if (m != null) {
    v['mere'] = '${m['nom']} ${m['prenom']}';
    v['mereId'] = m['id'];
  }
  v['reference'] = existante?['reference'] ?? matReferenceSuivante('NAI-', c.magasin.collection('naissances').toutes);
  _nombres(v, const ['poids', 'taille', 'pc', 'pt', 'apgar1', 'apgar5', 'apgar10']);
  matRecomposerDateHeure(v, 'dateHeure');
  if (matAlertesNouveauNe(v).isNotEmpty) {
    matAlerteDiffere(ctx, matMessageAlerteNouveauNe);
  }
  return matSansNuls(v);
}

class EcranNaissances extends StatelessWidget with EcranMaquette {
  const EcranNaissances({super.key});
  @override
  String get titre => 'Registre des naissances';
  @override
  String get description =>
      'Déclaration des naissances : sexe, poids, taille, score d’Apgar et suivi de la déclaration à l’état civil.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final seuil = matBornesNouveauNe.apgarSeuil5min;
    return CrudMat(
      collection: c.magasin.collection('naissances'),
      entite: 'naissance',
      entiteP: 'naissances',
      prefixeId: 'NAI',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      colonnes: [
        _colRef('N°'),
        _colDateHeure('dateHeure', 'Date et heure'),
        const ColonneTableau(cle: 'mere', libelle: 'Mère'),
        _colRef('Dossier mère', cle: 'mereCode'),
        _colBadge('sexe', 'Sexe', (r) => r['sexe'] == 'M' ? 'Masculin' : 'Féminin', (r) => r['sexe'] == 'M' ? TonSigh.info : TonSigh.navy),
        ColonneTableau(cle: 'poids', libelle: 'Poids (kg)', droite: true, valeur: (r) => matNum(r['poids']), texte: (r) => matTexteNombre(r['poids'])),
        ColonneTableau(
            cle: 'apgar5',
            libelle: 'Apgar 1/5/10',
            droite: true,
            valeur: (r) => matNum(r['apgar5']),
            texte: matApgarTexte,
            rendu: (_, r) => Text(matApgarTexte(r),
                style: TextStyle(
                    fontWeight: matApgarAlerte(r) ? FontWeight.w600 : FontWeight.w400,
                    color: matApgarAlerte(r) ? JetonsShell.danger600 : JetonsShell.slate700))),
        ColonneTableau(
            cle: 'pc',
            libelle: 'PC / PT (cm)',
            droite: true,
            valeur: (r) => matNum(r['pc']),
            texte: (r) => '${matOuTiret(matTexteNombre(r['pc']))} / ${matOuTiret(matTexteNombre(r['pt']))}',
            rendu: (_, r) => Text('${matOuTiret(matTexteNombre(r['pc']))} / ${matOuTiret(matTexteNombre(r['pt']))}',
                style: TextStyle(
                    fontWeight: matAlertesNouveauNe(r).isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                    color: matAlertesNouveauNe(r).isNotEmpty ? JetonsShell.warning700 : JetonsShell.slate700))),
        _colOuiBadge('vivant', 'État', (r) => matVrai(r['vivant']), 'Né vivant', TonSigh.succes, 'Mort-né', tonNon: TonSigh.danger),
        _colOuiBadge('declare', 'État civil', (r) => matVrai(r['declare']), 'Déclarée', TonSigh.succes, 'À déclarer', tonNon: TonSigh.attention),
      ],
      champs: _champsNaissance,
      valeursInitiales: () => {'vivant': true, 'declare': false, 'apgar1': '8', 'apgar5': '9', 'apgar10': '10', 'vitK1': true, 'collyre': true},
      valeursEdition: (f) => matValeursEdition(f, const ['dateHeure']),
      transformer: (ctx, v) => _fiche_naissance(ctx, v, null),
      transformerExistante: _fiche_naissance,
      filtres: [
        const FiltreTableau(nom: 'sexe', libelle: 'Sexe', options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')]),
        FiltreTableau(
            nom: 'declare',
            libelle: 'État civil',
            options: const [OptionChamp('true', 'Déclarées'), OptionChamp('false', 'À déclarer')],
            correspond: (r, v) => '${matVrai(r['declare'])}' == v),
      ],
      referenceToast: (f) => '${f['reference'] ?? ''}',
      kpis: (ctx, rows) {
        final g = rows.where((r) => r['sexe'] == 'M').length;
        return [
          _kpi('Naissances enregistrées', matNombre(rows.length), LucideIcons.baby, TonSigh.navy),
          _kpi('Garçons / Filles', '${matNombre(g)} / ${matNombre(rows.length - g)}', LucideIcons.users, TonSigh.info),
          _kpi('Poids moyen', rows.isEmpty ? '—' : '${(rows.fold<num>(0, (a, r) => a + _n(r['poids'])) / rows.length).toStringAsFixed(2)} kg',
              LucideIcons.scale, TonSigh.succes),
          _kpi('À déclarer à l’état civil', matNombre(rows.where((r) => !matVrai(r['declare'])).length), LucideIcons.fileClock, TonSigh.attention),
        ];
      },
      etat: (ctx, r) {
        String ou(Object? v, String u) => '${matOuTiret(matTexteNombre(v))} $u';
        final vaccins = [if (matVrai(r['vpo0'])) 'VPO0', if (matVrai(r['bcg'])) 'BCG', if (matVrai(r['hepB0'])) 'Hép. B J0'].join(', ');
        matImprimer(ctx,
            titre: 'Attestation de naissance',
            sousTitre: 'Établie par la maternité — ${r['reference']}',
            filigrane: 'Document officiel',
            cartouche: [
              ('Référence', '${r['reference']}'),
              ('Date et heure', matDateHeure(r['dateHeure'])),
              ('Mère', '${r['mere']}'),
              ('Dossier mère', '${r['mereCode']}'),
              ('Sexe', r['sexe'] == 'M' ? 'Masculin' : 'Féminin'),
              ('État', matVrai(r['vivant']) ? 'Né vivant' : 'Mort-né'),
            ],
            blocs: [
              const BlocTexte('La direction de la CLINIQUE NASSIERA TOO SARL atteste que l’enfant désigné ci-après est né dans ses services :'),
              matBlocRubriques([
                ('Date et heure de naissance', matDateHeure(r['dateHeure'])),
                ('Sexe', r['sexe'] == 'M' ? 'Masculin' : 'Féminin'),
                ('Poids à la naissance', '${matTexteNombre(r['poids'])} kg'),
                ('Taille', ou(r['taille'], 'cm')),
                ('Périmètre crânien (PC)', ou(r['pc'], 'cm')),
                ('Périmètre thoracique (PT)', ou(r['pt'], 'cm')),
                ('Score d’Apgar (1 / 5 / 10 min)', matApgarTexte(r)),
                ('Vitamine K1 / collyre',
                    '${matVrai(r['vitK1']) ? 'K1 administrée' : 'K1 non tracée'} · ${matVrai(r['collyre']) ? 'collyre fait' : 'collyre non tracé'}'),
                ('Vaccins de naissance', vaccins.isEmpty ? 'Aucun tracé' : vaccins),
                ('Nom de la mère', '${r['mere']}'),
              ]),
              const BlocTexte('La présente attestation est délivrée pour servir et valoir ce que de droit, en vue de la déclaration à l’état civil.',
                  italique: true),
            ],
            signatures: const [Signature('La Sage-femme'), Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko')]);
      },
    );
  }
}

class EcranDossierBebe extends StatelessWidget with EcranMaquette {
  const EcranDossierBebe({super.key});
  @override
  String get titre => 'Dossier bébé & soins du nouveau-né';
  @override
  String get description => 'PC et PT obligatoires, Apgar aux trois temps, vitamine K1, réanimation et vaccins de naissance.';
  @override
  String get regle =>
      'MÊME collection et MÊME formulaire que le registre des naissances : deux saisies auraient divergé au premier correctif. Ici, la lecture est celle des soins — bornes PC 32–38 cm, PT 30–36 cm, alerte si l’Apgar à 5 min est < 7 (rapport du 27/08/2026, §5.4).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final b = matBornesNouveauNe;
    Widget mesure(Object? v, bool hors) => Text(v == null ? '—' : matTexteNombre(v),
        style: TextStyle(fontWeight: hors ? FontWeight.w600 : FontWeight.w400, color: hors ? JetonsShell.danger600 : JetonsShell.slate700));
    String soins(Fiche r, {bool court = false}) => [
          if (matVrai(r['vitK1'])) court ? 'K1' : 'Vit K1',
          if (matVrai(r['vpo0'])) 'VPO0',
          if (matVrai(r['bcg'])) 'BCG',
          if (matVrai(r['hepB0'])) court ? 'HépB' : 'Hép. B',
        ].join(' ');
    return CrudMat(
      collection: c.magasin.collection('naissances'),
      entite: 'dossier bébé',
      entiteP: 'dossiers bébé',
      prefixeId: 'NAI',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      source: 'Rapport officiel maternité du 27/08/2026 — Module C et tableau 7.',
      colonnes: [
        _colRef('N°'),
        ColonneTableau(
            cle: 'mere',
            libelle: 'Nouveau-né de',
            texte: (r) => 'Nouveau-né de ${r['mere']} ${r['mereCode']} — ${matDateHeure(r['dateHeure'])}',
            rendu: (_, r) => matCelPatient('Nouveau-né de ${r['mere']}', '${r['mereCode']} — ${matDateHeure(r['dateHeure'])}')),
        ColonneTableau(cle: 'poids', libelle: 'Poids (kg)', droite: true, valeur: (r) => matNum(r['poids']), texte: (r) => matTexteNombre(r['poids'])),
        ColonneTableau(
            cle: 'pc',
            libelle: 'PC (cm)',
            droite: true,
            valeur: (r) => matNum(r['pc']),
            texte: (r) => r['pc'] == null ? '—' : matTexteNombre(r['pc']),
            rendu: (_, r) => mesure(r['pc'], matPcHorsBornes(r))),
        ColonneTableau(
            cle: 'pt',
            libelle: 'PT (cm)',
            droite: true,
            valeur: (r) => matNum(r['pt']),
            texte: (r) => r['pt'] == null ? '—' : matTexteNombre(r['pt']),
            rendu: (_, r) => mesure(r['pt'], matPtHorsBornes(r))),
        ColonneTableau(cle: 'apgar5', libelle: 'Apgar 1/5/10', droite: true, valeur: (r) => matNum(r['apgar5']), texte: matApgarTexte),
        _colOuiBadge('reanimation', 'Réanimation', (r) => matVrai(r['reanimation']), 'Réanimé — fonction 7 SONU', TonSigh.danger, '—'),
        ColonneTableau(
            cle: 'vitK1',
            libelle: 'Soins J0',
            texte: (r) => soins(r).isEmpty ? 'Aucun soin tracé' : soins(r),
            rendu: (_, r) {
              final l = soins(r).isEmpty ? <String>[] : [if (matVrai(r['vitK1'])) 'Vit K1', if (matVrai(r['vpo0'])) 'VPO0', if (matVrai(r['bcg'])) 'BCG', if (matVrai(r['hepB0'])) 'Hép. B'];
              return l.isEmpty
                  ? const BadgeSigh('Aucun soin tracé', ton: TonSigh.attention)
                  : matBadges([for (final x in l) (x, TonSigh.succes)]);
            }),
      ],
      champs: _champsNaissance,
      valeursInitiales: () => {'vivant': true, 'declare': false, 'vitK1': true, 'collyre': true},
      valeursEdition: (f) => matValeursEdition(f, const ['dateHeure']),
      transformer: (ctx, v) => _fiche_naissance(ctx, v, null),
      transformerExistante: _fiche_naissance,
      filtres: [_filtreOuiNon('reanimation', 'Réanimation', 'Réanimés', 'Sans réanimation', (r) => matVrai(r['reanimation']))],
      referenceToast: (f) => '${f['reference'] ?? ''}',
      kpis: (ctx, rows) {
        final hors = rows.where((r) => matAlertesNouveauNe(r).isNotEmpty).length;
        return [
          _kpi('Dossiers bébé', matNombre(rows.length), LucideIcons.baby, TonSigh.navy),
          _kpi('Mesures hors bornes', matNombre(hors), LucideIcons.triangleAlert, hors > 0 ? TonSigh.danger : TonSigh.succes,
              'PC ${matTexteNombre(b.pcMin)}–${matTexteNombre(b.pcMax)} · PT ${matTexteNombre(b.ptMin)}–${matTexteNombre(b.ptMax)} · Apgar 5 min ≥ ${matTexteNombre(b.apgarSeuil5min)}'),
          _kpi('Réanimations', matNombre(rows.where((r) => matVrai(r['reanimation'])).length), LucideIcons.heartPulse, TonSigh.attention, 'Fonction 7 SONU'),
          _kpi('Vitamine K1', matPct(rows.where((r) => matVrai(r['vitK1'])).length, rows.length), LucideIcons.syringe, TonSigh.info),
        ];
      },
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Volet nouveau-né',
          sousTitre: 'Nouveau-né de ${r['mere']} — ${r['reference']}',
          cartouche: [
            ('Mère', '${r['mere']}'),
            ('Dossier mère', '${r['mereCode']}'),
            ('Naissance', matDateHeure(r['dateHeure'])),
            ('Sexe', r['sexe'] == 'M' ? 'Masculin' : 'Féminin'),
            ('Statut', matVrai(r['vivant']) ? 'Né vivant' : 'Mort-né'),
            ('Référence', '${r['reference']}'),
          ],
          blocs: [
            matBlocRubriques([
              ('Poids / taille', '${matTexteNombre(r['poids'])} kg · ${matOuTiret(matTexteNombre(r['taille']))} cm'),
              ('Périmètre crânien (PC)', '${matOuTiret(matTexteNombre(r['pc']))} cm'),
              ('Périmètre thoracique (PT)', '${matOuTiret(matTexteNombre(r['pt']))} cm'),
              ('Apgar 1 / 5 / 10 min', matApgarTexte(r)),
              ('Réanimation néonatale', matVrai(r['reanimation']) ? 'OUI — fonction 7 SONU' : 'Non'),
              ('Soins essentiels', [if (matVrai(r['vitK1'])) 'Vitamine K1', if (matVrai(r['collyre'])) 'Collyre'].join(', ').isEmpty ? '—' : [if (matVrai(r['vitK1'])) 'Vitamine K1', if (matVrai(r['collyre'])) 'Collyre'].join(', ')),
              ('Vaccins J0', [if (matVrai(r['vpo0'])) 'VPO0', if (matVrai(r['bcg'])) 'BCG', if (matVrai(r['hepB0'])) 'Hépatite B'].join(', ').isEmpty ? '—' : [if (matVrai(r['vpo0'])) 'VPO0', if (matVrai(r['bcg'])) 'BCG', if (matVrai(r['hepB0'])) 'Hépatite B'].join(', ')),
            ], libelleValeur: 'Valeur')
          ],
          signatures: const [Signature('La Sage-femme')]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-deces
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDeces extends StatelessWidget with EcranMaquette {
  const EcranDeces({super.key});
  @override
  String get titre => 'Registre des décès';
  @override
  String get description => 'Enregistrement des décès survenus dans l’établissement : date, heure, cause et déclaration.';

  static const lieux = ['Hospitalisation', 'Urgences', 'Bloc opératoire', 'Maternité', 'Domicile'];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    Fiche fiche(Fiche v, Fiche? e) {
      matRattacher(v, matPatients(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('DEC-', c.magasin.collection('deces').toutes);
      matRecomposerDateHeure(v, 'dateHeure');
      return matSansNuls(v);
    }

    return CrudMat(
      collection: c.magasin.collection('deces'),
      entite: 'décès',
      entiteP: 'décès',
      prefixeId: 'DEC',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      colonnes: [
        _colRef('N°'),
        _colDateHeure('dateHeure', 'Date et heure'),
        _colPatient('Patient'),
        const ColonneTableau(cle: 'cause', libelle: 'Cause du décès'),
        const ColonneTableau(cle: 'lieu', libelle: 'Lieu'),
        const ColonneTableau(cle: 'medecin', libelle: 'Médecin constatant'),
        _colOuiBadge('declare', 'Déclaration', (r) => matVrai(r['declare']), 'Déclaré', TonSigh.succes, 'À déclarer', tonNon: TonSigh.attention),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Patient', type: TypeChamp.select, requis: true, options: matOptionsPatients(m), col: ColChamp.plein),
        ...matChampsDateHeure('dateHeure', 'Date et heure du décès'),
        const ChampDef(nom: 'cause', libelle: 'Cause du décès', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'lieu', libelle: 'Lieu', type: TypeChamp.select, options: _opts(lieux)),
        ChampDef(nom: 'medecin', libelle: 'Médecin constatant', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
        const ChampDef(nom: 'declare', libelle: 'Déclaré à l’état civil', type: TypeChamp.case_),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      valeursInitiales: () => {},
      valeursEdition: (f) => matValeursEdition(f, const ['dateHeure']),
      transformer: (ctx, v) => fiche(v, null),
      transformerExistante: (ctx, v, e) => fiche(v, e),
      filtres: [FiltreTableau(nom: 'lieu', libelle: 'Lieu', options: _opts(lieux))],
      referenceToast: (f) => '${f['reference'] ?? ''}',
      kpis: (ctx, rows) {
        // « Sur l'année 2026 » : l'année est ÉCRITE dans la maquette (écart E406) — portée fidèlement.
        final annee = rows.where((r) => (DateTime.tryParse('${r['dateHeure'] ?? ''}')?.toLocal().year) == 2026).length;
        return [
          _kpi('Décès enregistrés', matNombre(rows.length), LucideIcons.fileText, TonSigh.neutre),
          _kpi('Sur l’année 2026', matNombre(annee), LucideIcons.calendar, TonSigh.navy),
          _kpi('À déclarer', matNombre(rows.where((r) => !matVrai(r['declare'])).length), LucideIcons.fileClock, TonSigh.attention),
          _kpi('Causes distinctes', matNombre({for (final r in rows) '${r['cause']}'}.length), LucideIcons.list, TonSigh.info),
        ];
      },
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Déclaration de décès',
          sousTitre: '${r['reference']}',
          filigrane: 'Document officiel',
          cartouche: [
            ('Patient', '${r['patient']}'),
            ('Dossier', '${r['patientCode']}'),
            ('Date et heure', matDateHeure(r['dateHeure'])),
            ('Lieu', matOuTiret(r['lieu'])),
            ('Médecin constatant', '${r['medecin'] ?? ''}'),
            ('Référence', '${r['reference']}'),
          ],
          blocs: [
            const BlocTexte('Le médecin soussigné certifie avoir constaté le décès de la personne désignée ci-dessus.'),
            matBlocRubriques([
              ('Date et heure du décès', matDateHeure(r['dateHeure'])),
              ('Lieu du décès', matOuTiret(r['lieu'])),
              ('Cause du décès', '${r['cause'] ?? ''}'),
              ('Observations', matOuTiret(r['observations'])),
            ])
          ],
          signatures: [
            Signature('Le Médecin constatant', nom: '${r['medecin'] ?? ''}', mention: 'Signature et cachet'),
            const Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko')
          ]),
    );
  }
}
