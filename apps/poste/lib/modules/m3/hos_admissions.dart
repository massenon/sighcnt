import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/stock_crud.dart';
import 'hos_commun.dart';

/// `m3-admissions` — « Admissions » : registre d'hospitalisation, un lit ne portant qu'UNE admission active (refus nommé). Création et correction en
/// modale, fiche en tiroir avec le solde (RG-06), bon d'admission imprimable. Règles : `hosConstruireAdmission`, `hosRefusAdmission`,
/// `hosKpisAdmissions` (domaine), rejouées sur les vecteurs de la maquette.
class EcranAdmissions extends StatelessWidget with EcranMaquette {
  const EcranAdmissions({super.key});

  @override
  String get titre => 'Admissions';

  @override
  String get description =>
      'Enregistrement des admissions, affectation d’un lit et ouverture du registre d’hospitalisation.';

  @override
  String get regle =>
      'Un lit ne peut porter qu’une seule admission active à la fois : la liste des lits proposés ne présente que les lits libres.';

  /// `optionsLitsLibres(courant)` : les lits sans admission en cours, plus le lit de la fiche corrigée.
  static List<OptionChamp> optionsLits(Iterable<Fiche> admissions, String? courant) => [
        for (final l in hosTousLits())
          if (hosLitOccupePar(l.label, admissions) == null || l.label == courant)
            OptionChamp(l.label,
                '${l.label} — ${l.chambre.aile} (${hosLibelleTypeChambre(l.chambre.type)})')
      ];

  static List<ChampDef> champs(Magasin m, Fiche? fiche) => [
        const ChampDef.section('Patient'),
        ChampDef(
            nom: 'patientCode',
            libelle: 'Dossier patient',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: optionsPatientsHos(m)),
        const ChampDef.section('Affectation'),
        ChampDef(
            nom: 'lit',
            libelle: 'Lit',
            type: TypeChamp.select,
            requis: true,
            options: optionsLits(
                m.collection('admissions').actives, fiche?['lit'] as String?)),
        ChampDef(
            nom: 'infirmier',
            libelle: 'Infirmier référent',
            type: TypeChamp.select,
            requis: true,
            options: optionsInfirmiersNom(m)),
        const ChampDef(
            nom: 'dateEntree',
            libelle: 'Date d’entrée',
            type: TypeChamp.date,
            requis: true),
        const ChampDef(
            nom: 'priseEnCharge',
            libelle: 'Type de prise en charge',
            type: TypeChamp.select,
            requis: true,
            options: [
              OptionChamp('moins_8h', 'Moins de 8 heures'),
              OptionChamp('plus_8h', 'Plus de 8 heures')
            ]),
        const ChampDef.section('Motif d’hospitalisation'),
        const ChampDef(
            nom: 'diagnosticEntree',
            libelle: 'Diagnostic d’entrée',
            requis: true,
            col: ColChamp.plein),
        const ChampDef(
            nom: 'symptomes',
            libelle: 'Symptômes constatés',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
      ];

  static Widget detail(BuildContext context, Fiche a) {
    final c = ContexteEcran.of(context);
    final solde = soldePatient(c.magasin, a['patientId']);
    final auj = c.aujourdhui;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DescListeSigh([
        ('Référence', _mono('${a['reference'] ?? a['id']}')),
        ('Patient', a['patient']),
        ('Dossier', _mono('${a['patientCode'] ?? ''}')),
        ('Lit', a['lit']),
        ('Chambre', hosLibelleTypeChambre(a['typeChambre'])),
        ('Date d’entrée', jourFR(a['dateEntree'])),
        ('Date de sortie', a['dateSortie'] != null ? jourFR(a['dateSortie']) : 'En cours'),
        ('Durée', '${hosDureeSejour(a, auj)} jour(s)'),
        ('Diagnostic d’entrée', a['diagnosticEntree']),
        ('Symptômes', a['symptomes']),
        ('Prise en charge', statutBadge(a['priseEnCharge'])),
        ('Infirmier référent', a['infirmier']),
        ('Statut', statutBadge(a['statut'])),
      ]),
      if (a['statut'] == 'en_cours') ...[
        const SizedBox(height: 16),
        solde > 0
            ? NoteSigh(
                'RG-06 — Reste à régler : ${money(solde)} avant finalisation de la sortie.',
                ton: TonSigh.attention,
                icone: LucideIcons.wallet)
            : const NoteSigh('RG-06 — Situation financière apurée.',
                ton: TonSigh.succes, icone: LucideIcons.circleCheck),
      ],
    ]);
  }

  static Widget _mono(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'LiberationMono',
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w500,
          color: JetonsShell.slate800));

  /// `etatAdmission` : le bon d'admission (A4).
  static PieceA4 bon(ContexteEcran c, Fiche a) => PieceA4(
      titre: 'Bon d’admission',
      sousTitre: 'Référence ${a['reference'] ?? a['id']}',
      cartouche: [
        ('Patient', '${a['patient'] ?? ''}'),
        ('Dossier', '${a['patientCode'] ?? ''}'),
        ('Date d’entrée', jourFR(a['dateEntree'])),
        ('Lit affecté', '${a['lit'] ?? ''}'),
        ('Chambre', hosLibelleTypeChambre(a['typeChambre'])),
        ('Infirmier référent', '${a['infirmier'] ?? ''}'),
      ],
      tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
          ColonneEtat(libelle: 'Information', valeur: (r) => r['v']),
        ], lignes: [
          {'k': 'Diagnostic d’entrée', 'v': a['diagnosticEntree']},
          {'k': 'Symptômes constatés', 'v': a['symptomes']},
          {
            'k': 'Type de prise en charge',
            'v': a['priseEnCharge'] == 'plus_8h'
                ? 'Hospitalisation de plus de 8 heures'
                : 'Prise en charge de moins de 8 heures'
          },
          {
            'k': 'Lit et chambre',
            'v': '${a['lit']} — ${hosLibelleTypeChambre(a['typeChambre'])}'
          },
        ]),
      ],
      signatures: [
        const Signature('Le Médecin', mention: 'Décision d’hospitalisation'),
        Signature('L’Infirmier traitant', nom: '${a['infirmier'] ?? ''}'),
        const Signature('Le Patient ou son représentant'),
      ],
      reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('admissions');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) => CrudStock(
        collection: col,
        entite: 'admission',
        entiteP: 'admissions',
        prefixeId: 'ADM',
        triInitial: 'dateEntree',
        sensInitial: 'desc',
        taillePage: 12,
        largeurTiroir: 768,
        messageModification: 'Modifications enregistrées.',
        referenceToast: (f) => '${f['reference'] ?? ''}',
        libelleRecherche: 'Rechercher un admission…',
        colonnes: [
          ColonneTableau(
              cle: 'reference',
              libelle: 'N°',
              sansCoupure: true,
              texte: (a) => '${a['reference'] ?? '—'}',
              rendu: (_, a) => Text('${a['reference'] ?? '—'}',
                  style: const TextStyle(
                      fontFamily: 'LiberationMono',
                      fontSize: 12,
                      color: JetonsShell.slate700))),
          ColonneTableau(
              cle: 'patient',
              libelle: 'Patient',
              texte: (a) => '${a['patient'] ?? ''} ${a['patientCode'] ?? ''}',
              rendu: (_, a) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${a['patient'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: JetonsShell.slate800,
                                fontSize: 14,
                                height: 20 / 14,
                                fontWeight: FontWeight.w500)),
                        Text('${a['patientCode'] ?? ''}',
                            style: const TextStyle(
                                fontFamily: 'LiberationMono',
                                fontSize: 12,
                                color: JetonsShell.slate400)),
                      ])),
          ColonneTableau(
              cle: 'lit',
              libelle: 'Lit',
              sansCoupure: true,
              rendu: (_, a) => Text('${a['lit'] ?? ''}',
                  style: const TextStyle(
                      fontFamily: 'LiberationMono',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: JetonsShell.navy800))),
          ColonneTableau(
              cle: 'typeChambre',
              libelle: 'Chambre',
              texte: (a) => hosLibelleTypeChambre(a['typeChambre']),
              rendu: (_, a) => BadgeSigh(hosLibelleTypeChambre(a['typeChambre']),
                  ton: a['typeChambre'] == 'standard' ? TonSigh.neutre : TonSigh.navy)),
          ColonneTableau(
              cle: 'dateEntree',
              libelle: 'Entrée',
              sansCoupure: true,
              texte: (a) => jourFR(a['dateEntree']),
              rendu: (_, a) => Text(jourFR(a['dateEntree']),
                  style: const TextStyle(
                      color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
          ColonneTableau(
              cle: 'duree',
              libelle: 'Durée',
              droite: true,
              valeur: (a) => hosDureeSejour(a, c.aujourdhui),
              texte: (a) => '${hosDureeSejour(a, c.aujourdhui)} j',
              rendu: (_, a) => Text('${hosDureeSejour(a, c.aujourdhui)} j',
                  style: const TextStyle(
                      color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
          const ColonneTableau(cle: 'diagnosticEntree', libelle: 'Diagnostic'),
          ColonneTableau(
              cle: 'priseEnCharge',
              libelle: 'Prise en charge',
              texte: (a) => statutsMetier['${a['priseEnCharge']}']?.$1 ?? '',
              rendu: (_, a) => statutBadge(a['priseEnCharge'])),
          ColonneTableau(
              cle: 'statut',
              libelle: 'Statut',
              texte: (a) => statutsMetier['${a['statut']}']?.$1 ?? '${a['statut']}',
              rendu: (_, a) => statutBadge(a['statut'])),
        ],
        filtres: const [
          FiltreTableau(nom: 'statut', libelle: 'Statut', options: [
            OptionChamp('en_cours', 'En cours'),
            OptionChamp('sortie', 'Sorti')
          ]),
          FiltreTableau(nom: 'typeChambre', libelle: 'Type de chambre', options: [
            OptionChamp('standard', 'Standard'),
            OptionChamp('vip', 'VIP'),
            OptionChamp('vvip', 'VVIP')
          ]),
          FiltreTableau(nom: 'priseEnCharge', libelle: 'Prise en charge', options: [
            OptionChamp('moins_8h', 'Moins de 8h'),
            OptionChamp('plus_8h', 'Plus de 8h')
          ]),
        ],
        kpis: (ctx, rows) {
          final k = hosKpisAdmissions(rows, c.aujourdhui);
          return [
            KpiSigh(
                libelle: 'Admissions enregistrées',
                valeur: nombre(k.admissions),
                icone: LucideIcons.clipboardList,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Hospitalisations en cours',
                valeur: nombre(k.enCours),
                icone: LucideIcons.bedDouble,
                ton: TonSigh.danger),
            KpiSigh(
                libelle: 'Taux d’occupation',
                valeur: pourcent(k.taux, 1),
                icone: LucideIcons.gauge,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Durée moyenne de séjour',
                valeur: '${hosNum(k.dms)} j',
                icone: LucideIcons.timer,
                ton: TonSigh.neutre),
          ];
        },
        champs: (m) => champs(m, null),
        champsPour: champs,
        valeursInitiales: () => {
          'dateEntree': iso(c.aujourdhui),
          'priseEnCharge': 'plus_8h',
        },
        transformer: (ctx, v) => hosConstruireAdmission(
            v,
            null,
            c.magasin.collection('patients').actives,
            col.toutes,
            reference: referenceSuivante),
        transformerExistante: (ctx, v, existante) => hosConstruireAdmission(
            v,
            existante,
            c.magasin.collection('patients').actives,
            col.toutes,
            reference: referenceSuivante),
        refuserExistante: (v, existante) =>
            hosRefusAdmission('${v['lit']}', existante, col.actives),
        detail: detail,
        titreDetail: (a) => '${a['patient'] ?? a['id']}',
        sousTitreDetail: (a) => '${a['reference'] ?? a['id']}',
        etat: (ctx, a) => afficherApercu(ctx, bon(ContexteEcran.of(ctx), a)),
      ),
    );
  }
}
