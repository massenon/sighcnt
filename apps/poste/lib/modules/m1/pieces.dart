import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m1.dart';

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

/// Les types de pièce : la collection `typesPiece` si le jeu la porte, sinon les quatorze du référentiel du domaine (extraits du magasin de la
/// maquette — le jeu du poste ne porte pas encore cette collection).
List<PatTypePiece> typesPiece(Magasin m) {
  final l = m.collection('typesPiece').actives;
  if (l.isEmpty) return patTypesPiece;
  return [
    for (final t in l)
      PatTypePiece('${t['id']}', '${t['sigle']}', '${t['libelle']}', '${t['direction']}', t['tarifCode'] as String?,
          t['collision'] as String?, (t['examens'] as List?)?.cast<String>())
  ];
}

Fiche? _tarif(Magasin m, String? code) =>
    code == null ? null : m.collection('catalogueTarifs').actives.where((t) => t['code'] == code).firstOrNull;

class EcranPieces extends StatelessWidget with EcranMaquette {
  const EcranPieces({super.key});

  @override
  String get description => 'Délivrance, numérotation et impression des quatorze pièces certifiantes de la clinique.';

  @override
  String get regle =>
      'Chaque pièce reçoit un numéro d’ordre dans l’année et la direction émettrice. Le registre porte les pièces des patients de la clinique ET adressés de l’extérieur — une seule numérotation, un seul registre. Toute pièce tarifée passe par la caisse : son état de règlement se LIT sur la pièce de caisse, il n’est jamais ressaisi. Les certificats ne sont couverts par aucune assurance à l’exception de SOS, et le prénuptial se remplit depuis les résultats validés biologiquement, jamais à la main.';

  static List<ChampDef> champs(ContexteEcran c, Fiche? e) {
    final edition = e != null;
    final medecins = [
      for (final a in c.magasin.collection('personnel').actives)
        if (a['fonction'] == 'medecin') OptionChamp('${a['nomComplet']}', '${a['nomComplet']} — ${a['poste']}')
    ];
    const vide = (controle: 'patientCode', quand: ['']);
    return [
      ChampDef(
          nom: 'typeId',
          libelle: 'Type de pièce',
          type: TypeChamp.select,
          requis: true,
          options: [for (final t in typesPiece(c.magasin)) OptionChamp(t.id, t.libelle)]),
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient (dossier du répertoire)',
          type: TypeChamp.select,
          options: [const OptionChamp('', '— Aucun : patient adressé de l’extérieur —'), ...optionsPatientsM1(c.magasin)],
          aide: 'Laisser vide pour un patient qui n’a pas de dossier à la clinique.'),
      if (!edition) ...const [
        ChampDef.section('Ou patient adressé de l’extérieur (dossier créé ici)'),
        ChampDef(nom: 'extNom', libelle: 'Nom', col: ColChamp.tiers, condition: vide),
        ChampDef(nom: 'extPrenom', libelle: 'Prénoms', col: ColChamp.tiers, condition: vide),
        ChampDef(
            nom: 'extSexe',
            libelle: 'Sexe',
            type: TypeChamp.select,
            col: ColChamp.tiers,
            options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')],
            condition: vide),
        ChampDef(
            nom: 'extAge',
            libelle: 'Âge déclaré',
            type: TypeChamp.nombre,
            col: ColChamp.tiers,
            aide: 'À défaut de date de naissance — c’est la réponse ordinaire au guichet.',
            condition: vide),
        ChampDef(nom: 'extTelephone', libelle: 'Téléphone', col: ColChamp.tiers, condition: vide),
        ChampDef(nom: 'extResidence', libelle: 'Résidence', col: ColChamp.tiers, condition: vide),
      ],
      const ChampDef.section('Délivrance'),
      ChampDef(nom: 'medecin', libelle: 'Médecin signataire', type: TypeChamp.select, requis: true, options: medecins),
      const ChampDef(nom: 'dateDelivrance', libelle: 'Date de délivrance', type: TypeChamp.date, requis: true),
      const ChampDef(
          nom: 'contenu',
          libelle: 'Mentions portées sur la pièce',
          type: TypeChamp.textarea,
          lignes: 5,
          col: ColChamp.plein,
          aide: 'Le corps du certificat, tel qu’il sera imprimé.'),
      const ChampDef(nom: 'remisA', libelle: 'Remis à', aide: 'L’intéressé lui-même, ou la personne nommément désignée.'),
    ];
  }

  static String? _refuser(ContexteEcran c, Map<String, Object?> s, Fiche? e) {
    if (e != null) return null;
    if (!patVrai(s['patientCode']) && ('${s['extNom'] ?? ''}'.trim().isEmpty || '${s['extPrenom'] ?? ''}'.trim().isEmpty)) {
      return 'Choisir un dossier du répertoire, ou saisir le nom et les prénoms du patient adressé de l’extérieur.';
    }
    return null;
  }

  /// `transform` : la pièce reçoit son numéro, son patient (au besoin le dossier externe naît par la fabrique UNIQUE), son montant à la grille, et
  /// LA CAISSE EST SAISIE À LA DÉLIVRANCE — une pièce tarifée qui ne produit aucune facture compte dans les recettes une somme que personne n'a encaissée.
  static Fiche _transformer(ContexteEcran c, Map<String, Object?> s, Fiche? existante) {
    if (existante != null) return s;
    final m = c.magasin;
    final t = typesPiece(m).firstWhere((x) => x.id == s['typeId']);
    final patients = m.collection('patients');
    Fiche? pt = patVrai(s['patientCode'])
        ? patients.actives.where((x) => x['code'] == s['patientCode']).firstOrNull
        : null;
    if (pt == null) {
      final d = patDossierExterne({
        'nom': s['extNom'],
        'prenom': s['extPrenom'],
        'sexe': s['extSexe'],
        'age': s['extAge'],
        'telephone': s['extTelephone'],
        'residence': s['extResidence'],
        'origineDossier': 'Patient externe — délivrance d’une pièce certifiante',
      }, c.aujourdhui, patients.toutes.length);
      pt = patients.inserer(d, prefixe: 'PAT').fiche;
    }
    final nu = patNumeroter(t, m.collection('pieces').toutes, c.aujourdhui.year);
    final tarif = _tarif(m, t.tarifCode);
    final montant = tarif == null ? null : tarif['prixNonAssure'] as num?;
    PatFacturePiece? fac;
    if (patVrai(montant)) {
      fac = patFacturerPiece(
          patient: pt,
          montant: montant,
          libelle: t.libelle,
          reference: nu.reference,
          acteCode: t.tarifCode,
          assurable: tarif?['assurable'] ?? false,
          couvertures: m.collection('couverturesAssurance').actives,
          nbFactures: m.collection('factures').toutes.length,
          nouvelId: (p) => '$p${DateTime.now().microsecondsSinceEpoch}',
          date: c.aujourdhui);
      if (fac != null) {
        m.collection('factures').inserer(fac.facture, prefixe: 'FAC');
        m.collection('taches').inserer(fac.tache, prefixe: 'TCH');
      }
    }
    final out = {...s};
    for (final k in ['extNom', 'extPrenom', 'extSexe', 'extAge', 'extTelephone', 'extResidence']) {
      out.remove(k);
    }
    return {
      ...out,
      'numero': nu.numero,
      'annee': nu.annee,
      'reference': nu.reference,
      'sigle': t.sigle,
      'libelle': t.libelle,
      'direction': t.direction,
      'patientId': pt['id'],
      'patientCode': pt['code'],
      'patient': '${pt['nom']} ${pt['prenom']}',
      'patientExterne': patVrai(pt['externe']),
      'montant': montant,
      'factureId': fac?.facture['id'],
      'factureNumero': fac?.facture['numero'],
      'couverture': patCouverturePiece(tarif?['assurable']),
    };
  }

  static void _imprimer(BuildContext ctx, Fiche r) => imprimerM1(ctx,
      titre: '${r['libelle'] ?? ''}'.toUpperCase(),
      sousTitre: 'N°/Réf : ${r['reference']}',
      cartouche: [
        ('Patient', '${r['patient']}'),
        ('Dossier', '${r['patientCode']}'),
        ('Délivrée le', dateFrM1(r['dateDelivrance'])),
        ('Remise à', _t(r['remisA'], 'L’intéressé(e)')),
      ],
      blocs: [
        BlocTexte(_t(r['contenu'], 'En foi de quoi la présente pièce est établie pour servir et valoir ce que de droit.')),
        BlocTexte(_t(r['couverture'], ''), italique: true),
      ],
      signatures: [Signature('Le Médecin', nom: '${r['medecin']}', mention: 'Signature et cachet')]);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final col = m.collection('pieces');
    return ListenableBuilder(
        listenable: Listenable.merge([col, m.collection('factures'), m.collection('patients')]),
        builder: (context, _) {
          final patients = m.collection('patients').toutes;
          final factures = m.collection('factures').toutes;
          final rows = col.actives;
          final internes = rows.where((r) => !patEstExterne(r, patients)).toList();
          final externes = rows.where((r) => patEstExterne(r, patients)).toList();
          final k = patKpisPieces(rows, patients, factures, c.aujourdhui.year);
          PatStatutPiece st(Fiche r) => patStatutPiece(r, factures);
          Widget tableau(List<Fiche> l, bool archive) => RegistreM1(
                collection: col,
                archive: archive,
                entite: 'Pièce',
                lignes: (_, __) => trierPar(l, (r) => r['dateDelivrance']).reversed.toList(),
                libelleNouveau: 'Délivrer une pièce',
                titreNouveau: 'Délivrer un certificat ou une attestation',
                messageVide: archive ? 'Aucune pièce archivée.' : 'Aucune pièce délivrée.',
                champs: champs,
                valeursInitiales: (cc) => {'dateDelivrance': iso(cc.aujourdhui), 'patientCode': ''},
                refuser: _refuser,
                transformer: _transformer,
                etat: _imprimer,
                titreDetail: (x) => '${x['libelle']}',
                actionsSup: (ctx, r) => [
                  if (st(r).code == 'a_encaisser')
                    BoutonIcone(
                        icone: LucideIcons.coins,
                        libelle: 'Reste dû — ouvrir la caisse',
                        onPressed: () {
                          ToastsSigh.afficher(ctx, st(r).detail, type: TypeToast.attention, duree: const Duration(seconds: 8));
                          c.aller('m8-caisse');
                        }),
                ],
                detail: (ctx, x) {
                  final s = st(x);
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DescListeSigh([
                      ('Référence', '${x['reference']}'),
                      ('Pièce', x['libelle']),
                      ('Patient', '${x['patient']} — ${x['patientCode']}'),
                      ('Délivrée le', dateFrM1(x['dateDelivrance'])),
                      ('Signataire', x['medecin']),
                      ('Remise à', _t(x['remisA'], 'L’intéressé(e)')),
                      ('Montant', x['montant'] == null ? 'non tarifé' : money(x['montant'])),
                      ('Couverture', _t(x['couverture'])),
                      ('Règlement', s.label),
                      ('Pièce de caisse', _t(x['factureNumero'], 'aucune')),
                    ]),
                    const SizedBox(height: 12),
                    NoteSigh(s.detail.isEmpty ? '—' : s.detail, ton: tonDe(s.ton), icone: LucideIcons.coins),
                    if (patVrai(x['contenu'])) sectionM1('Mentions portées', paragrapheM1('${x['contenu']}')),
                  ]);
                },
                colonnes: [
                  ColonneTableau(cle: 'reference', libelle: 'Référence', rendu: (_, r) => enMono('${r['reference']}'), texte: (r) => '${r['reference']}'),
                  const ColonneTableau(cle: 'libelle', libelle: 'Pièce'),
                  ColonneTableau(
                      cle: 'patient',
                      libelle: 'Patient',
                      texte: (r) => '${r['patient']} ${r['patientCode']}',
                      rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text('${r['patient']}', overflow: TextOverflow.ellipsis, style: styleM1(c: JetonsShell.slate800)),
                            Text('${r['patientCode']}', style: monoM1.copyWith(color: JetonsShell.slate400)),
                          ])),
                  ColonneTableau(
                      cle: 'origine',
                      libelle: 'Origine',
                      triable: false,
                      texte: (r) => patEstExterne(r, patients) ? 'Externe' : 'Clinique',
                      rendu: (_, r) => patEstExterne(r, patients)
                          ? const BadgeSigh('Externe', ton: TonSigh.info)
                          : const BadgeSigh('Clinique')),
                  ColonneTableau(cle: 'dateDelivrance', libelle: 'Délivrée le', texte: (r) => dateFrM1(r['dateDelivrance']), valeur: (r) => r['dateDelivrance']),
                  const ColonneTableau(cle: 'medecin', libelle: 'Signataire'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (r) => r['montant'] == null ? '' : '${r['montant']}',
                      rendu: (_, r) => Text(r['montant'] == null ? '—' : money(r['montant'], avecDevise: false), style: styleM1())),
                  ColonneTableau(
                      cle: 'reglement',
                      libelle: 'Règlement',
                      triable: false,
                      texte: (r) => st(r).label,
                      rendu: (_, r) => BadgeSigh(st(r).label, ton: tonDe(st(r).ton))),
                ],
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bandeauLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(
                  libelle: 'Pièces délivrées',
                  valeur: nombre(k.delivrees),
                  icone: LucideIcons.stamp,
                  indice: '${nombre(k.clinique)} clinique · ${nombre(k.externes)} externes'),
              KpiSigh(libelle: 'Sur l’exercice ${c.aujourdhui.year}', valeur: nombre(k.exercice), icone: LucideIcons.calendar, ton: TonSigh.info),
              KpiSigh(libelle: 'Encaissé', valeur: money(k.encaisse), icone: LucideIcons.coins, ton: TonSigh.succes),
              KpiSigh(
                  libelle: 'À encaisser',
                  valeur: money(k.aEncaisser),
                  icone: LucideIcons.handCoins,
                  ton: k.aEncaisser > 0 ? TonSigh.danger : TonSigh.neutre,
                  indice: k.sansPiece > 0 ? '${nombre(k.sansPiece)} pièce(s) sans pièce de caisse liée' : null),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'L’assurance ne couvre pas les certificats, à l’exception de SOS. La mention figure en toutes lettres sur la grille tarifaire de la clinique. Un assuré d’une autre compagnie règle donc intégralement, et la pièce de caisse en porte le motif.',
                ton: TonSigh.attention,
                icone: LucideIcons.shieldOff),
            if (k.sansPiece > 0) ...[
              const SizedBox(height: 16),
              NoteSigh(
                  '${nombre(k.sansPiece)} pièce(s) sans pièce de caisse liée — délivrées avant que la caisse n’entre dans le circuit. Elles ne sont ni réglées ni impayées : on ne sait pas. Les compter comme encaissées gonflerait la recette d’autant.',
                  icone: LucideIcons.circleHelp),
            ],
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'toutes', libelle: 'Toutes les pièces', compte: rows.length, construire: (_) => tableau(rows, false)),
              OngletDef(id: 'clinique', libelle: 'Patients de la clinique', compte: internes.length, construire: (_) => tableau(internes, false)),
              OngletDef(id: 'externes', libelle: 'Patients externes', compte: externes.length, construire: (_) => tableau(externes, false)),
              OngletDef(id: 'archives', libelle: 'Archives', compte: col.archivees.length, construire: (_) => tableau(col.archivees, true)),
            ]),
          ]);
        });
  }
}
