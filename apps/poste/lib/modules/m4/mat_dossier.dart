import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/besoins_commun.dart' show ChronologieSigh;
import 'mat_commun.dart';
import 'mat_crud.dart';

/// Le DOSSIER OBSTÉTRICAL (M4) : le cahier de la parturiente — UN seul cahier, de la première CPN à la surveillance du deuxième jour. L'écran est une
/// LECTURE qui rassemble ce que les autres écrans de M4 tiennent chacun de leur côté ; il ne duplique aucun geste. Le numéro suit le registre papier
/// (NNNNN/AA, série annuelle) ; la date probable se DÉDUIT de la DDR (280 jours) ; le risque se déduit du CUMUL des douze facteurs cochés.

List<ChampDef> matChampsDossier(Magasin m) {
  final femmes = matOptionsFemmes(m);
  return [
    const ChampDef.section('Dossier'),
    const ChampDef(nom: 'numeroDossier', libelle: 'N° de dossier (registre papier)', requis: true, aide: 'Série annuelle NNNNN/AA — reprise du cahier de la maternité.'),
    const ChampDef(nom: 'dateEntree', libelle: 'Date d’entrée', type: TypeChamp.date, requis: true),
    ChampDef(nom: 'patientCode', libelle: 'Parturiente (dossier patient)', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: femmes),
    const ChampDef(nom: 'profession', libelle: 'Profession'),
    const ChampDef(nom: 'nationalite', libelle: 'Nationalité'),
    const ChampDef(nom: 'quartier', libelle: 'Village / quartier de ville'),
    const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
    const ChampDef(nom: 'personneContact', libelle: 'Personne à contacter'),
    const ChampDef(nom: 'telephoneContact', libelle: 'Téléphone de la personne à contacter', type: TypeChamp.tel),
    const ChampDef(nom: 'referee', libelle: 'Référée par un autre centre', type: TypeChamp.case_),
    const ChampDef(nom: 'refereePar', libelle: 'Si référée, par qui'),
    const ChampDef.section('Procréateur'),
    const ChampDef(nom: 'procreateurNom', libelle: 'Nom et prénoms'),
    const ChampDef(nom: 'procreateurProfession', libelle: 'Profession'),
    const ChampDef(nom: 'procreateurGs', libelle: 'Groupe sanguin / Rhésus'),
    const ChampDef(nom: 'procreateurSerologie', libelle: 'Sérologie du conjoint'),
    const ChampDef.section('Antécédents'),
    const ChampDef(nom: 'maladies', libelle: 'Maladies et opérations', col: ColChamp.plein),
    const ChampDef(nom: 'traitements', libelle: 'Traitements en cours', col: ColChamp.plein),
    const ChampDef(nom: 'allergies', libelle: 'Allergies', col: ColChamp.plein),
    const ChampDef(nom: 'gestite', libelle: 'Gestité', type: TypeChamp.nombre, requis: true),
    const ChampDef(nom: 'parite', libelle: 'Parité', type: TypeChamp.nombre, requis: true),
    const ChampDef(nom: 'avortements', libelle: 'Nombre d’avortements', type: TypeChamp.nombre),
    const ChampDef(nom: 'enfantsVivants', libelle: 'Nombre d’enfants vivants', type: TypeChamp.nombre),
    const ChampDef(nom: 'enfantsDecedes', libelle: 'Nombre d’enfants décédés', type: TypeChamp.nombre),
    const ChampDef(nom: 'transfusions', libelle: 'Transfusions antérieures', type: TypeChamp.nombre),
    const ChampDef(nom: 'ddr', libelle: 'Date des dernières règles (DDR)', type: TypeChamp.date, requis: true, aide: 'La date probable de l’accouchement en est déduite (280 jours).'),
    const ChampDef(nom: 'taille', libelle: 'Taille (m)', type: TypeChamp.nombre),
    const ChampDef.section('Facteurs de surveillance — leur cumul classe la grossesse à risque'),
    for (final f in matFacteursSurveillance) ChampDef(nom: 'facteur_${f['code']}', libelle: '${f['libelle']}', type: TypeChamp.case_),
    const ChampDef.section('Suivi'),
    ChampDef(nom: 'sageFemme', libelle: 'Sage-femme référente', type: TypeChamp.select, options: [
      for (final e in m.collection('personnel').actives)
        if (e['fonction'] == 'sage_femme') OptionChamp('${e['nomComplet']}', '${e['nomComplet']}')
    ]),
    const ChampDef(
        nom: 'statutDossier',
        libelle: 'État du dossier',
        type: TypeChamp.select,
        requis: true,
        options: [OptionChamp('suivi', 'Suivi en cours'), OptionChamp('accouchee', 'Accouchée'), OptionChamp('clos', 'Clos')]),
  ];
}

/// Valeurs d'un dossier ouvert à l'édition : les facteurs se déplient en cases `facteur_<code>`.
Map<String, Object?> _valeursEdition(Fiche d) => {
      for (final e in d.entries) e.key: e.value is num ? '${e.value}' : e.value,
      for (final f in matFacteursSurveillance) 'facteur_${f['code']}': ((d['facteurs'] as Map?)?['${f['code']}']) == true,
    };

/// `transform` : patient rattaché, âge relevé, DPA déduite de la DDR, facteurs rangés dans UNE carte.
Fiche matFicheDossier(Magasin m, Fiche v, DateTime auj, [Fiche? existante]) {
  final col = m.collection('dossiersObstetricaux');
  if (v['numeroDossier'] == null || '${v['numeroDossier']}'.isEmpty) v['numeroDossier'] = matNumeroDossier(col.toutes, DateTime.tryParse('${v['dateEntree']}') ?? auj);
  final p = matPatientDe(m, v['patientCode']);
  if (p != null) {
    v['patientId'] = p['id'];
    v['patient'] = '${p['nom']} ${p['prenom']}';
    v['age'] = matAge(p['dateNaissance'], auj);
  }
  for (final k in const ['gestite', 'parite', 'avortements', 'enfantsVivants', 'enfantsDecedes', 'transfusions', 'taille']) {
    v[k] = matNombreSaisi(v[k]);
  }
  return matSansNuls(matRanger(v));
}

Map<String, Object?> matInitialesDossier(Magasin m, DateTime auj) => {
      'dateEntree': iso(auj),
      'statutDossier': 'suivi',
      'gestite': '1',
      'parite': '0',
      'numeroDossier': matNumeroDossier(m.collection('dossiersObstetricaux').toutes, auj),
    };

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le registre
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDossierObstetrical extends StatelessWidget with EcranMaquette {
  const EcranDossierObstetrical({super.key});
  @override
  String get titre => 'Dossier obstétrical';
  @override
  String get description =>
      'Le cahier de la parturiente, de la première CPN à la surveillance du deuxième jour — identité, antécédents, facteurs de surveillance, examens, plan d’accouchement.';
  @override
  String get regle =>
      'Le dossier obstétrical est un seul cahier : identité et antécédents, soins préventifs, consultations prénatales, accouchement, surveillance. Les éclater en cinq écrans obligeait la sage-femme de garde à tous les ouvrir pour savoir ce qu’on savait déjà. Le numéro de dossier suit le registre papier (NNNNN/AA, série annuelle) : le renuméroter romprait la correspondance avec les cahiers tenus depuis des années. Un facteur de surveillance coché classe la grossesse à risque — et c’est le cumul qui compte, jamais un facteur isolé.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    const etats = {'suivi': ('Suivi en cours', TonSigh.info), 'accouchee': ('Accouchée', TonSigh.succes), 'clos': ('Clos', TonSigh.neutre)};
    String etat(Fiche d) => (etats['${d['statutDossier']}'] ?? etats['suivi']!).$1;
    return CrudMat(
      collection: c.magasin.collection('dossiersObstetricaux'),
      entite: 'dossier obstétrical',
      entiteP: 'dossiers obstétricaux',
      prefixeId: 'DOB',
      triInitial: 'dateEntree',
      sensInitial: 'desc',
      plageChamp: 'dateEntree',
      creerVers: 'm4-dossier-obstetrical-nouveau',
      largeurTiroir: 896,
      source: 'Formulaire national « DOSSIER OBSTÉTRICAL » — Ministère de la Santé, République du Bénin.',
      colonnes: [
        ColonneTableau(
            cle: 'numeroDossier',
            libelle: 'N° dossier',
            sansCoupure: true,
            texte: (d) => '${d['numeroDossier'] ?? ''}',
            rendu: (_, d) => Text('${d['numeroDossier'] ?? ''}',
                style: const TextStyle(fontFamily: matPoliceMono, fontSize: 12, fontWeight: FontWeight.w600, color: JetonsShell.slate900))),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Parturiente',
            texte: (d) => '${d['patient'] ?? ''} ${d['patientCode'] ?? ''} · ${d['age'] ?? '—'} ans',
            rendu: (_, d) => matCelPatient('${d['patient'] ?? ''}', '${d['patientCode'] ?? ''} · ${d['age'] ?? '—'} ans', mono: false)),
        ColonneTableau(
            cle: 'gestiteParite',
            libelle: 'G / P',
            sansCoupure: true,
            valeur: (d) => 'G${matTexteNombre(d['gestite']).isEmpty ? 0 : matTexteNombre(d['gestite'])} P${matTexteNombre(d['parite']).isEmpty ? 0 : matTexteNombre(d['parite'])}',
            texte: (d) => 'G${matTexteNombre(d['gestite']).isEmpty ? 0 : matTexteNombre(d['gestite'])} P${matTexteNombre(d['parite']).isEmpty ? 0 : matTexteNombre(d['parite'])}'),
        ColonneTableau(cle: 'ddr', libelle: 'DDR', sansCoupure: true, texte: (d) => matVrai(d['ddr']) ? matDateFR(d['ddr']) : ''),
        ColonneTableau(
            cle: 'dpa',
            libelle: 'Terme prévu',
            sansCoupure: true,
            texte: (d) {
              if (!matVrai(d['dpa'])) return '';
              final reste = matJoursEntre(auj, DateTime.parse('${d['dpa']}'));
              return '${matDateFR(d['dpa'])} ${reste >= 0 ? 'dans $reste j' : 'dépassé de ${-reste} j'}';
            },
            rendu: (_, d) {
              if (!matVrai(d['dpa'])) return const Text('—');
              final reste = matJoursEntre(auj, DateTime.parse('${d['dpa']}'));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(matDateFR(d['dpa']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14)),
                matMuet(reste >= 0 ? 'dans $reste j' : 'dépassé de ${-reste} j'),
              ]);
            }),
        ColonneTableau(
            cle: 'gar',
            libelle: 'Surveillance',
            valeur: (d) => matEstGar(d) ? 'gar' : 'normal',
            texte: (d) {
              final f = matFacteursCoches(d);
              return f.isEmpty ? 'Sans facteur' : 'GAR — ${f.length} facteur(s) ${f.first['libelle']}${f.length > 1 ? '…' : ''}';
            },
            rendu: (_, d) {
              final f = matFacteursCoches(d);
              if (f.isEmpty) return const BadgeSigh('Sans facteur', ton: TonSigh.succes);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                BadgeSigh('GAR — ${f.length} facteur(s)', ton: TonSigh.danger),
                matMuet('${f.first['libelle']}${f.length > 1 ? '…' : ''}'),
              ]);
            }),
        ColonneTableau(
            cle: 'statutDossier',
            libelle: 'État',
            texte: etat,
            rendu: (_, d) => BadgeSigh(etat(d), ton: (etats['${d['statutDossier']}'] ?? etats['suivi']!).$2)),
      ],
      champs: matChampsDossier,
      valeursInitiales: () => matInitialesDossier(c.magasin, auj),
      valeursEdition: _valeursEdition,
      transformer: (ctx, v) => matFicheDossier(c.magasin, v, auj),
      transformerExistante: (ctx, v, e) => matFicheDossier(c.magasin, v, auj, e),
      referenceToast: (f) => null,
      filtres: [
        const FiltreTableau(
            nom: 'statutDossier',
            libelle: 'État',
            options: [OptionChamp('suivi', 'Suivi en cours'), OptionChamp('accouchee', 'Accouchée'), OptionChamp('clos', 'Clos')]),
        FiltreTableau(
            nom: 'gar',
            libelle: 'Surveillance',
            options: const [OptionChamp('gar', 'Grossesse à risque'), OptionChamp('normal', 'Sans facteur')],
            correspond: (d, v) => v == 'gar' ? matEstGar(d) : !matEstGar(d)),
        FiltreTableau(
            nom: 'venue',
            libelle: 'Venue',
            options: const [OptionChamp('elle', 'Venue d’elle-même'), OptionChamp('referee', 'Référée')],
            correspond: (d, v) => v == 'referee' ? matVrai(d['referee']) : !matVrai(d['referee'])),
      ],
      kpis: (ctx, rows) {
        final gar = rows.where(matEstGar).length;
        return [
          KpiSigh(libelle: 'Dossiers ouverts', valeur: nombre(rows.length), icone: LucideIcons.folderOpen, ton: TonSigh.navy),
          KpiSigh(libelle: 'Suivis en cours', valeur: nombre(rows.where((d) => d['statutDossier'] == 'suivi').length), icone: LucideIcons.activity, ton: TonSigh.info),
          KpiSigh(
              libelle: 'Grossesses à risque (GAR)',
              valeur: nombre(gar),
              icone: LucideIcons.triangleAlert,
              ton: gar > 0 ? TonSigh.danger : TonSigh.succes,
              indice: 'Au moins un facteur de surveillance coché'),
          KpiSigh(libelle: 'Référées', valeur: nombre(rows.where((d) => matVrai(d['referee'])).length), icone: LucideIcons.share2, ton: TonSigh.attention),
        ];
      },
      detail: (ctx, d) => _Fiche(d, c.magasin),
      etat: _etat,
    );
  }

  static void _etat(BuildContext ctx, Fiche d) {
    final f = matFacteursCoches(d);
    BlocPiece titre(String t) => BlocTexte(t.toUpperCase(), gras: true);
    String ou(Object? v, String repli) => v == null || v == '' ? repli : '$v';
    matImprimer(ctx,
        titre: 'Dossier obstétrical',
        sousTitre: 'N° ${d['numeroDossier']} — ${d['patient']}',
        cartouche: [
          ('N° de dossier', '${d['numeroDossier']}'),
          ('Parturiente', '${d['patient']}'),
          ('Dossier patient', '${d['patientCode']}'),
          ('Âge', d['age'] != null ? '${d['age']} ans' : '—'),
          ('Date d’entrée', matDateFR(d['dateEntree'])),
          ('Gestité / Parité', 'G${matTexteNombre(d['gestite'])} P${matTexteNombre(d['parite'])}'),
          ('DDR', matVrai(d['ddr']) ? matDateFR(d['ddr']) : '—'),
          ('Date probable de l’accouchement', matVrai(d['dpa']) ? matDateFR(d['dpa']) : '—'),
          ('Sage-femme référente', ou(d['sageFemme'], '—')),
          ('Venue', matVrai(d['referee']) ? 'Référée' : 'D’elle-même'),
        ],
        blocs: [
          titre('Antécédents'),
          matBlocRubriques([
            ('Maladies et opérations', ou(d['maladies'], 'Néant')),
            ('Traitements en cours', ou(d['traitements'], 'Néant')),
            ('Allergies', ou(d['allergies'], 'Non connues')),
            ('Avortements', matTexteNombre(d['avortements']).isEmpty ? '0' : matTexteNombre(d['avortements'])),
            ('Enfants vivants', matTexteNombre(d['enfantsVivants']).isEmpty ? '0' : matTexteNombre(d['enfantsVivants'])),
            ('Enfants décédés', matTexteNombre(d['enfantsDecedes']).isEmpty ? '0' : matTexteNombre(d['enfantsDecedes'])),
            ('Transfusions antérieures', matTexteNombre(d['transfusions']).isEmpty ? '0' : matTexteNombre(d['transfusions'])),
          ]),
          titre('Facteurs de surveillance'),
          if (f.isEmpty)
            const BlocTexte('Aucun facteur de surveillance coché.', italique: true)
          else
            BlocTableau(TableauEtat(colonnes: [ColonneEtat(libelle: 'Facteur relevé', valeur: (l) => l['l'])], lignes: [
              for (final x in f) {'l': x['libelle']}
            ])),
          titre('Examens complémentaires'),
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Examen', valeur: (l) => l['l']),
            ColonneEtat(libelle: 'Groupe', valeur: (l) => l['g']),
            ColonneEtat(libelle: 'Résultat', valeur: (l) => l['v']),
          ], lignes: [
            for (final x in matExamensDossier)
              {
                'l': x['libelle'],
                'g': x['groupe'],
                'v': () {
                  final v = ((d['examens'] as Map?) ?? const {})[x['code']];
                  return v == null || v == '' ? 'Non renseigné' : '$v';
                }()
              }
          ])),
          const BlocTexte(
              'Formulaire national « DOSSIER OBSTÉTRICAL » — Ministère de la Santé, République du Bénin. Le numéro de dossier suit le registre papier de la maternité.',
              italique: true),
        ],
        signatures: [Signature('La Sage-femme', nom: ou(d['sageFemme'], '')), const Signature('Le Médecin', mention: 'Visa')]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La fiche : les cinq feuillets, dans l'ordre du cahier
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Fiche extends StatelessWidget {
  const _Fiche(this.d, this.m);
  final Fiche d;

  /// Le magasin vient de l'écran : un tiroir vit AU-DESSUS de la coque, `ContexteEcran.of` y échoue.
  final Magasin m;

  List<Fiche> _liee(Magasin m, String col, bool Function(Fiche) test) => [for (final x in m.collection(col).actives) if (test(x)) x];

  @override
  Widget build(BuildContext context) {
    final f = matFacteursCoches(d);
    final cpn = _liee(m, 'grossesses', (g) => g['dossierId'] == d['id'] || g['patientId'] == d['patientId']);
    final acc = _liee(m, 'accouchements', (a) => a['dossierId'] == d['id'] || a['patientId'] == d['patientId']);
    final nais = _liee(m, 'naissances', (n) => acc.any((a) => a['id'] == n['accouchementId']));
    final parto = _liee(m, 'partogrammes', (x) => x['dossierId'] == d['id'] || x['patientId'] == d['patientId']);
    final cpo = _liee(m, 'cpon', (x) => x['patientId'] == d['patientId']);
    String ou(Object? v, String repli) => v == null || v == '' ? repli : '$v';
    String n0(Object? v) => matTexteNombre(v).isEmpty ? '0' : matTexteNombre(v);

    Widget carte(String t, Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: CarteSigh(titre: t, child: w));

    final identite = Column(children: [
      carte(
          'Parturiente',
          DescListeSigh([
            ('N° de dossier', Text('${d['numeroDossier']}', style: const TextStyle(fontFamily: matPoliceMono, fontSize: 14))),
            ('Nom', '${d['patient']}'),
            ('Dossier patient', '${d['patientCode']}'),
            ('Âge', d['age'] != null && d['age'] != 0 ? '${d['age']} ans' : '—'),
            ('Taille', matVrai(d['taille']) ? '${matTexteNombre(d['taille'])} m' : '—'),
            ('Profession', ou(d['profession'], '—')),
            ('Nationalité', ou(d['nationalite'], '—')),
            ('Quartier', ou(d['quartier'], '—')),
            ('Téléphone', ou(d['telephone'], '—')),
            ('Personne à contacter', '${ou(d['personneContact'], '—')}${matVrai(d['telephoneContact']) ? ' · ${d['telephoneContact']}' : ''}'),
            ('Venue', matVrai(d['referee']) ? 'Référée${matVrai(d['refereePar']) ? ' par ${d['refereePar']}' : ''}' : 'D’elle-même'),
            ('Date d’entrée', matDateFR(d['dateEntree'])),
            ('Sage-femme référente', ou(d['sageFemme'], '—')),
          ])),
      carte(
          'Procréateur',
          DescListeSigh([
            ('Nom et prénoms', ou(d['procreateurNom'], '—')),
            ('Profession', ou(d['procreateurProfession'], '—')),
            ('Groupe sanguin / Rhésus', ou(d['procreateurGs'], '—')),
            ('Sérologie du conjoint', ou(d['procreateurSerologie'], '—')),
          ])),
      carte(
          'Antécédents',
          DescListeSigh([
            ('Maladies et opérations', ou(d['maladies'], 'Néant')),
            ('Traitements en cours', ou(d['traitements'], 'Néant')),
            ('Allergies', ou(d['allergies'], 'Non connues')),
            ('Gestité', n0(d['gestite'])),
            ('Parité', n0(d['parite'])),
            ('Avortements', n0(d['avortements'])),
            ('Enfants vivants', n0(d['enfantsVivants'])),
            ('Enfants décédés', n0(d['enfantsDecedes'])),
            ('Transfusions antérieures', n0(d['transfusions'])),
            ('DDR', matVrai(d['ddr']) ? matDateFR(d['ddr']) : '—'),
            ('Date probable de l’accouchement', matVrai(d['dpa']) ? matDateFR(d['dpa']) : '—'),
          ])),
      carte(
          'Facteurs de surveillance',
          f.isEmpty
              ? const VideSigh('Aucun facteur de surveillance coché.', icone: LucideIcons.circleCheck)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  matNote('Grossesse à risque — ${nombre(f.length)} facteur(s) coché(s). C’est leur CUMUL qui classe, jamais un facteur isolé.',
                      ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
                  const SizedBox(height: 8),
                  MiniTableauSigh(colonnes: [ColonneMini('Facteur relevé', (x) => '${x['libelle']}')], lignes: f),
                ])),
      carte(
          'Examens complémentaires',
          MiniTableauSigh(colonnes: [
            ColonneMini('Examen', (x) => '${x['libelle']}'),
            ColonneMini('Groupe', (x) => '${x['groupe']}'),
            ColonneMini('Résultat', (x) {
              final v = ((d['examens'] as Map?) ?? const {})[x['code']];
              return v == null || v == '' ? 'Non renseigné' : '$v';
            }),
          ], lignes: matExamensDossier)),
    ]);

    final preventifs = Column(children: [
      carte(
          'Vaccination antitétanique',
          MiniTableauSigh(colonnes: [
            ColonneMini('Dose', (x) => '${x['k']}'),
            ColonneMini('Date', (x) => x['v'] == null ? '—' : matDateFR(x['v'])),
          ], lignes: [
            for (final v in const ['VAT1', 'VAT2', 'VAT3', 'VAT4', 'VAT5']) {'k': v, 'v': ((d['vat'] as Map?) ?? const {})[v]}
          ])),
      carte(
          'Vulgarisation des dix droits fondamentaux',
          MiniTableauSigh(colonnes: [ColonneMini('Droit', (x) => '${x['k']}'), ColonneMini('Vulgarisé', (x) => '${x['v']}')], lignes: [
            for (final (i, x) in matDroitsFondamentaux.indexed) {'k': '${i + 1}. $x', 'v': ((d['droits'] as Map?) ?? const {})['$i'] == true || ((d['droits'] as Map?) ?? const {})[i] == true ? 'Oui' : '—'}
          ])),
      carte(
          'Plan pour l’accouchement',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            matNote('Chacune de ces neuf lignes est une cause connue de retard le jour de l’accouchement : savoir qui décide en l’absence du mari, ou qui garde les enfants, évite l’heure perdue à la chercher.',
                icone: LucideIcons.route),
            const SizedBox(height: 8),
            MiniTableauSigh(colonnes: [ColonneMini('Point du plan', (x) => '${x['k']}'), ColonneMini('Arrêté', (x) => '${x['v']}')], lignes: [
              for (final (i, x) in matPlanAccouchement.indexed) {'k': x, 'v': ((d['plan'] as Map?) ?? const {})['$i'] == true ? 'Oui' : '—'}
            ]),
          ])),
      carte(
          'Autres soins promotionnels',
          DescListeSigh([
            ('Informations sur la PF', ou(d['infoPF'], '—')),
            ('Référence pour CPN', ou(d['referenceCPN'], '—')),
            ('Référence pour accouchement', ou(d['referenceAccouchement'], '—')),
            ('Classe des mères', ((d['classesMeres'] as List?) ?? const []).isEmpty ? '—' : (d['classesMeres'] as List).join(' · ')),
          ])),
    ]);

    Widget prenatales() {
      if (cpn.isEmpty) return const VideSigh('Aucune consultation prénatale rattachée.', icone: LucideIcons.clipboardList);
      final visites = [for (final g in cpn) for (final v in ((g['visites'] as List?) ?? const [])) (v as Map).cast<String, Object?>()];
      if (visites.isEmpty) return const VideSigh('Aucune visite enregistrée.', icone: LucideIcons.clipboardList);
      final groupes = <String, List<Fiche>>{};
      for (final x in matGrilleCpn) {
        groupes.putIfAbsent('${x['groupe']}', () => []).add(x);
      }
      return Column(children: [
        for (final g in groupes.entries)
          carte(
              'CPN — ${g.key}',
              MiniTableauSigh(colonnes: [
                ColonneMini(g.key, (l) => '${l['libelle']}'),
                for (final (i, v) in visites.indexed)
                  ColonneMini('V${v['n'] ?? i + 1}${matVrai(v['date']) ? ' — ${matDateFR(v['date'])}' : ''}', (l) => '${l['v$i']}', droite: true),
              ], lignes: [
                for (final l in g.value)
                  {
                    'libelle': l['libelle'],
                    for (final (i, v) in visites.indexed)
                      'v$i': () {
                        final val = v[l['code']];
                        return val == null || val == '' ? '—' : (val is bool ? (val ? 'Oui' : 'Non') : matTexteNombre(val));
                      }()
                  }
              ])),
      ]);
    }

    Widget accouchement() {
      if (acc.isEmpty) return const VideSigh('La parturiente n’a pas encore accouché.', icone: LucideIcons.baby);
      return Column(children: [
        for (final a in acc)
          carte(
              'Accouchement ${a['reference'] ?? ''}',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Date et heure', matDateHeure(a['dateHeure'])),
                  ('Type', ou(a['type'], '—')),
                  ('Accoucheur', ou(a['sageFemme'] ?? a['accoucheur'], '—')),
                  ('Délivrance', ou(a['modeDelivrance'], '—')),
                  ('Hémorragie', matVrai(a['hemorragie']) ? 'OUI — ${nombre(a['quantiteSang'] ?? 0)} ml' : 'Non'),
                  ('Issue mère', matVrai(a['femmeDecedee']) ? 'DÉCÉDÉE' : (matVrai(a['femmeReferee']) ? 'Référée' : 'Sortie')),
                ]),
                const SizedBox(height: 12),
                if (a['surveillance'] is Map && ((a['surveillance'] as Map)['releves'] as List? ?? const []).isNotEmpty)
                  carte(
                      'Fiche de surveillance intégrée — accouchée et nouveau-né',
                      MiniTableauSigh(colonnes: [
                        ColonneMini('Temps', (r) => '${r['temps']}'),
                        ColonneMini('Pouls mère', (r) => matTexteNombre((r['mere'] as Map)['pouls'])),
                        ColonneMini('TA mère', (r) => '${(r['mere'] as Map)['ta'] ?? ''}'),
                        ColonneMini('T° mère', (r) => matTexteNombre((r['mere'] as Map)['temperature'])),
                        ColonneMini('Écoulement', (r) => '${(r['mere'] as Map)['ecoulement'] ?? ''}'),
                        ColonneMini('Globe', (r) => '${(r['mere'] as Map)['globe'] ?? ''}'),
                        ColonneMini('T° bébé', (r) => matTexteNombre((r['bebe'] as Map)['temperature'])),
                        ColonneMini('Coloration', (r) => '${(r['bebe'] as Map)['coloration'] ?? ''}'),
                        ColonneMini('Respiration', (r) => matTexteNombre((r['bebe'] as Map)['respiration'])),
                        ColonneMini('Allaitement', (r) => '${(r['bebe'] as Map)['allaitement'] ?? ''}'),
                      ], lignes: [for (final r in ((a['surveillance'] as Map)['releves'] as List)) (r as Map).cast<String, Object?>()]))
                else
                  matNote('La fiche de surveillance intégrée couvre les 48 premières heures : elle n’est tenue que pour les accouchements récents.', icone: LucideIcons.clock),
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final bebes = nais.where((n) => n['accouchementId'] == a['id']).toList();
                  if (bebes.isEmpty) return const Text('Aucun nouveau-né enregistré.', style: TextStyle(color: JetonsShell.slate500, fontSize: 14, fontStyle: FontStyle.italic));
                  return MiniTableauSigh(colonnes: [
                    ColonneMini('Sexe', (n) => n['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
                    ColonneMini('Poids', (n) => '${n['poids']} kg'),
                    ColonneMini('Taille', (n) => '${n['taille']} cm'),
                    ColonneMini('PC', (n) => '${n['pc']} cm'),
                    ColonneMini('PT', (n) => '${n['pt']} cm'),
                    ColonneMini('Apgar 1/5/10', (n) => [n['apgar1'], n['apgar5'], n['apgar10']].join(' / ')),
                    ColonneMini('Vivant', (n) => matVrai(n['vivant']) ? 'Oui' : 'NON'),
                  ], lignes: bebes);
                }),
              ])),
      ]);
    }

    final suites = Column(children: [
      carte(
          'Partogramme',
          parto.isEmpty
              ? const VideSigh('Aucun partogramme ouvert.', icone: LucideIcons.activity)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('Référence', (x) => ou(x['reference'], '—')),
                  ColonneMini('Date', (x) => matVrai(x['date']) ? matDateFR(x['date']) : '—'),
                  ColonneMini('Dilatation atteinte', (x) => '${ou(x['dilatationFinale'], '—')} cm'),
                  ColonneMini('Issue', (x) => ou(x['issue'], '—')),
                ], lignes: parto)),
      carte(
          'Consultations post-natales',
          cpo.isEmpty
              ? const VideSigh('Aucune CPoN enregistrée.', icone: LucideIcons.stethoscope)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('Date', (x) => matDateFR(x['date'])),
                  ColonneMini('Type', (x) => ou(x['type'], '—')),
                  ColonneMini('HPP', (x) => matVrai(x['hpp']) ? 'OUI' : 'Non'),
                  ColonneMini('Examen', (x) => ou(x['examen'], '—')),
                ], lignes: cpo)),
      matNote('Le dossier rassemble ce que les écrans de M4 tiennent chacun de leur côté : la CPN, le partogramme, l’accouchement, le nouveau-né et les CPoN. Il ne les duplique pas — c’est une LECTURE, et chaque geste se fait à son écran.',
          icone: LucideIcons.link),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(colonnes: 4, kpis: [
        KpiSigh(libelle: 'N° de dossier', valeur: '${d['numeroDossier']}', icone: LucideIcons.folderOpen, ton: TonSigh.navy),
        KpiSigh(libelle: 'Gestité / Parité', valeur: 'G${n0(d['gestite'])} P${n0(d['parite'])}', icone: LucideIcons.baby, ton: TonSigh.info),
        KpiSigh(libelle: 'Terme prévu', valeur: matVrai(d['dpa']) ? matDateFR(d['dpa']) : '—', icone: LucideIcons.calendarClock, ton: TonSigh.attention),
        KpiSigh(
            libelle: 'Facteurs de surveillance',
            valeur: nombre(f.length),
            icone: f.isNotEmpty ? LucideIcons.triangleAlert : LucideIcons.circleCheck,
            ton: f.isNotEmpty ? TonSigh.danger : TonSigh.succes),
      ]),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(id: 'identite', libelle: 'Identité & antécédents', construire: (_) => identite),
        OngletDef(id: 'preventifs', libelle: 'Soins préventifs', construire: (_) => preventifs),
        OngletDef(id: 'cpn', libelle: 'Consultations prénatales (${cpn.length})', construire: (_) => prenatales()),
        OngletDef(id: 'accouchement', libelle: 'Accouchement & nouveau-né', construire: (_) => accouchement()),
        OngletDef(id: 'suites', libelle: 'Partogramme & suites', construire: (_) => suites),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La page d'ouverture d'un dossier
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDossierObstetricalNouveau extends StatefulWidget with EcranMaquette {
  const EcranDossierObstetricalNouveau({super.key});
  static VoidCallback? _enregistrerCourant;

  @override
  String get titre => 'Ouvrir un dossier obstétrical';
  @override
  String get description =>
      'Identité, antécédents gynéco-obstétricaux, facteurs de surveillance et plan d’accouchement — le cahier de la parturiente s’ouvre ici.';
  @override
  String get regle =>
      'Le numéro de dossier suit le registre papier (NNNNN/AA, série annuelle). La date probable de l’accouchement se déduit de la DDR (280 jours) — la saisir à part ouvrirait deux dates qui ne se recoupent pas. Le risque n’est pas un champ : il se déduit du cumul des facteurs cochés.';
  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) return const [];
    return [
      BoutonSigh(libelle: 'Ouvrir le dossier', icone: LucideIcons.save, taille: TailleBouton.sm, onPressed: () => _enregistrerCourant?.call())
    ];
  }

  @override
  State<EcranDossierObstetricalNouveau> createState() => _EtatNouveau();
}

class _EtatNouveau extends State<EcranDossierObstetricalNouveau> {
  ControleurFormulaire? _ctl;

  @override
  void dispose() {
    EcranDossierObstetricalNouveau._enregistrerCourant = null;
    _ctl?.dispose();
    super.dispose();
  }

  void _enregistrer(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final v = _ctl!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final fiche = matFicheDossier(c.magasin, v, c.aujourdhui);
    c.magasin.collection('dossiersObstetricaux').inserer({'statut': 'actif', ...fiche, '_creePar': c.utilisateur, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: 'DOB');
    // Le message survit à la navigation : il est posé sur le calque racine avant de revenir au registre.
    ToastsSigh.afficher(ctx, 'Dossier obstétrical créé.', type: TypeToast.succes, duree: const Duration(seconds: 7));
    c.aller('m4-dossier-obstetrical');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        matNote('Votre profil consulte les dossiers obstétricaux sans les ouvrir. Le cahier appartient à la sage-femme et au médecin qui suivent la grossesse.',
            ton: TonSigh.attention, icone: LucideIcons.lock),
        const SizedBox(height: 12),
        BoutonSigh(libelle: 'Revenir au registre', icone: LucideIcons.arrowLeft, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m4-dossier-obstetrical')),
      ]);
    }
    _ctl ??= ControleurFormulaire(matChampsDossier(c.magasin), matInitialesDossier(c.magasin, c.aujourdhui));
    EcranDossierObstetricalNouveau._enregistrerCourant = () => _enregistrer(context);
    final principal = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(titre: 'Le cahier de la parturiente', child: FormulaireSigh(controleur: _ctl!)),
    ]);
    final aside = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Enchaînement du parcours',
          child: ChronologieSigh(const [
            (titre: 'Ouverture du cahier', detail: 'Identité, antécédents, facteurs de surveillance — vous y êtes', date: 'Étape 1', ton: TonSigh.navy),
            (titre: 'Consultations prénatales', detail: 'La grille CPN, visite après visite — SP1-5, MILDA, dépistages (M4)', date: 'Étape 2', ton: TonSigh.info),
            (titre: 'Travail et partogramme', detail: 'Alerte à 4 cm puis 1 cm/h ; action décalée de 4 h (M4)', date: 'Étape 3', ton: TonSigh.info),
            (titre: 'Accouchement et nouveau-né', detail: 'Délivrance, placenta, Apgar 1-5-10, PC/PT (M4)', date: 'Étape 4', ton: TonSigh.attention),
            (titre: 'Surveillance et CPoN', detail: 'Fiche intégrée mère-bébé, puis les trois consultations post-natales', date: 'Étape 5', ton: TonSigh.neutre),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Ce que le cahier engage',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            matNote('Le risque se déduit du CUMUL des facteurs cochés, jamais d’un facteur isolé. Cocher, c’est classer la grossesse à risque et la faire remonter au tableau de bord de la maternité.',
                ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
            const SizedBox(height: 12),
            matNote('La date probable ne se saisit pas : elle vient de la DDR, à 280 jours. C’est la règle que la sage-femme applique de tête, et la tenir à un seul endroit évite deux termes qui ne se recoupent pas.',
                icone: LucideIcons.calendarClock),
            const SizedBox(height: 12),
            matNote('Le numéro suit le registre papier (NNNNN/AA) : le renuméroter romprait la correspondance avec les cahiers tenus depuis des années.',
                ton: TonSigh.neutre, icone: LucideIcons.hash),
          ])),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (ctx, k) => k.maxWidth >= 1024
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: principal), const SizedBox(width: 16), Expanded(child: aside)])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [principal, const SizedBox(height: 16), aside])),
      const SizedBox(height: 16),
      Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate200))),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            BoutonSigh(libelle: 'Annuler', icone: LucideIcons.x, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m4-dossier-obstetrical')),
            const SizedBox(width: 8),
            BoutonSigh(libelle: 'Ouvrir le dossier', icone: LucideIcons.plus, onPressed: () => _enregistrer(context)),
          ])),
    ]);
  }
}
