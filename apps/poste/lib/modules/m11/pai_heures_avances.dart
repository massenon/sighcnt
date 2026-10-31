import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_crud.dart';
import 'pai_commun.dart';

/// Heures supplémentaires et avances sur salaire : deux `K.crud` de la maquette, portés sur le CRUD de M4 (aux textes EXACTS de `K.crud`). Les règles
/// chiffrées (taux horaire majoré, mensualité, plafond de trois mois de salaire) sont dans `packages/domaine/lib/src/paie/pai_moteur.dart`.
///
/// Écarts : (E683) la maquette ne passait pas la fiche existante à `transform(v, record)` — chaque MODIFICATION renumérotait la déclaration ou l'avance
/// (HS-0001 devenait HS-0023) ; (E684) et modifier une avance remettait « remboursé » à zéro, l'agent redevenant redevable de ce qu'il avait rendu :
/// corrigés dans la maquette, portés corrigés ; (E688) les `min` / `max` des champs sont des attributs HTML que `collect()` ne contrôle pas — une
/// déclaration de 0 heure, une avance de 24 mensualités s'enregistrent. Portés fidèlement, signalés.

List<OptionChamp> _optionsAgents(Magasin m, {bool salaire = false}) => [
      for (final e in trierPar(m.collection('personnel').actives, (e) => e['nomComplet']))
        OptionChamp('${e['id']}',
            salaire ? '${e['matricule']} — ${e['nomComplet']} (salaire ${money(e['salaireBase'])})' : '${e['matricule']} — ${e['nomComplet']}')
    ];

Fiche? _agent(ContexteEcran c, Object? id) => c.magasin.collection('personnel').actives.where((x) => x['id'] == id).firstOrNull;

/// `Number(v)` d'une saisie : vide → absent (`null`) ; un nombre illisible vaut 0.
num? _nombre(Object? v) {
  final t = '${v ?? ''}'.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return num.tryParse(t) ?? 0;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m11-heures-sup
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranHeuresSup extends StatelessWidget with EcranMaquette {
  const EcranHeuresSup({super.key});

  @override
  String get titre => 'Heures supplémentaires';

  @override
  String get description => 'Déclaration et valorisation des heures effectuées au-delà de l’horaire contractuel.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('heuresSup');
    return CrudMat(
      collection: col,
      entite: 'déclaration',
      entiteP: 'déclarations',
      taillePage: 15,
      triInitial: 'montant',
      sensInitial: 'desc',
      prefixeId: 'HEU',
      kpis: (ctx, rows) => [
        KpiSigh(libelle: 'Déclarations', valeur: nombre(rows.length), icone: LucideIcons.clock),
        KpiSigh(libelle: 'Heures déclarées', valeur: nombre(rows.fold<num>(0, (a, h) => a + n(h['heures']))), icone: LucideIcons.timer, ton: TonSigh.info),
        KpiSigh(
            libelle: 'Montant à payer',
            valeur: money(rows.where((h) => h['valide'] == true).fold<num>(0, (a, h) => a + n(h['montant']))),
            icone: LucideIcons.wallet,
            ton: TonSigh.succes),
        KpiSigh(libelle: 'En attente de validation', valeur: nombre(rows.where((h) => h['valide'] != true).length), icone: LucideIcons.hourglass, ton: TonSigh.attention),
      ],
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, h) => monoTexte(h['reference'])),
        const ColonneTableau(cle: 'periode', libelle: 'Période', sansCoupure: true),
        const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
        const ColonneTableau(cle: 'employe', libelle: 'Agent'),
        const ColonneTableau(cle: 'service', libelle: 'Service'),
        const ColonneTableau(cle: 'heures', libelle: 'Heures', droite: true),
        ColonneTableau(cle: 'tauxHoraire', libelle: 'Taux horaire', droite: true, texte: (h) => m(h['tauxHoraire']), rendu: (_, h) => cellMontant(n(h['tauxHoraire']))),
        ColonneTableau(cle: 'majoration', libelle: 'Majoration', droite: true, texte: (h) => '${paiNum(n(h['majoration']))} %', rendu: (_, h) => cellTexte('${paiNum(n(h['majoration']))} %')),
        ColonneTableau(cle: 'montant', libelle: 'Montant', droite: true, texte: (h) => m(h['montant']), rendu: (_, h) => cellMontant(n(h['montant']), fort: true)),
        const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        ColonneTableau(
            cle: 'valide',
            libelle: 'Validation',
            texte: (h) => h['valide'] == true ? 'Validée' : 'En attente',
            rendu: (_, h) => h['valide'] == true ? const BadgeSigh('Validée', ton: TonSigh.succes) : const BadgeSigh('En attente', ton: TonSigh.attention)),
      ],
      filtres: [
        FiltreTableau(nom: 'periode', libelle: 'Période', options: [for (var i = 0; i < 12; i++) OptionChamp(paiPeriodeLibelle(paiAnnee, i))]),
        FiltreTableau(nom: 'service', libelle: 'Service', options: [for (final s in paiServices) OptionChamp(s)]),
      ],
      champs: (mag) => [
        ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: _optionsAgents(mag)),
        ChampDef(nom: 'periode', libelle: 'Période', type: TypeChamp.select, requis: true, options: [for (var i = 0; i < 12; i++) OptionChamp(paiPeriodeLibelle(paiAnnee, i))]),
        const ChampDef(nom: 'heures', libelle: 'Nombre d’heures', type: TypeChamp.nombre, requis: true),
        const ChampDef(nom: 'majoration', libelle: 'Majoration (%)', type: TypeChamp.nombre),
        ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.select, requis: true, options: [for (final x in _motifsHs) OptionChamp(x)]),
        const ChampDef(nom: 'valide', libelle: 'Déclaration validée', type: TypeChamp.case_),
      ],
      valeursInitiales: () => {'majoration': '25', 'valide': false, 'periode': paiPeriodeLibelle(c.aujourdhui.year, c.aujourdhui.month - 1)},
      transformerExistante: (ctx, saisie, existante) {
        final v = <String, Object?>{...saisie, 'heures': _nombre(saisie['heures']), 'majoration': _nombre(saisie['majoration'])};
        return paiHeuresSupTransform(v, _agent(c, saisie['employeId']), reference: () => (existante?['reference'] as String?) ?? paiReferenceSuivante('HS-', 4, col.toutes));
      },
      transformer: (ctx, saisie) => paiHeuresSupTransform({...saisie, 'heures': _nombre(saisie['heures']), 'majoration': _nombre(saisie['majoration'])}, _agent(c, saisie['employeId']),
          reference: () => paiReferenceSuivante('HS-', 4, col.toutes)),
      referenceToast: (f) => '${f['reference'] ?? ''}',
    );
  }
}

const _motifsHs = ['Renfort de garde', 'Urgence', 'Remplacement', 'Surcroît d’activité'];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m11-avances
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranAvances extends StatelessWidget with EcranMaquette {
  const EcranAvances({super.key});

  @override
  String get titre => 'Avances sur salaire';

  @override
  String get description => 'Octroi et suivi du remboursement des avances, avec retenue automatique sur le bulletin.';

  void _imprimer(BuildContext ctx, Fiche a) {
    final c = ContexteEcran.of(ctx);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Demande d’avance sur salaire',
            sousTitre: '${a['reference']}',
            cartouche: [
              ('Agent', '${a['employe']}'),
              ('Matricule', '${a['matricule']}'),
              ('Service', '${a['service']}'),
              ('Date d’octroi', dateFR(DateTime.parse('${a['date']}'))),
              ('Montant accordé', money(a['montant'])),
              ('Mensualités', '${a['nbMensualites']} × ${money(a['mensualite'])}'),
            ],
            blocs: [
              BlocTexte('Il est accordé à ${a['employe']}, matricule ${a['matricule']}, une avance sur salaire d’un montant de ${money(a['montant'])}, au titre de : ${a['motif']}.'),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
                ColonneEtat(libelle: 'Montant', droite: true, valeur: (r) => r['v']),
              ], lignes: [
                {'k': 'Montant accordé', 'v': m(a['montant'])},
                {'k': 'Nombre de mensualités', 'v': '${a['nbMensualites']}'},
                {'k': 'Retenue mensuelle', 'v': m(a['mensualite'])},
                {'k': 'Déjà remboursé', 'v': m(a['rembourse'])},
                {'k': 'RESTANT DÛ', 'v': m(n(a['montant']) - n(a['rembourse']))},
              ])),
              BlocTexte('Le remboursement s’effectue par retenue automatique sur le bulletin de paie, à raison de ${money(a['mensualite'])} par mois, jusqu’à apurement complet.', italique: true),
            ],
            signatures: [Signature('L’Agent', nom: '${a['employe']}', mention: 'Lu et approuvé'), signComptable, signDaf]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('avances');
    return CrudMat(
      collection: col,
      entite: 'avance',
      entiteP: 'avances',
      taillePage: 15,
      triInitial: 'date',
      sensInitial: 'desc',
      prefixeId: 'AVA',
      intro: (_) => const NoteSigh('La mensualité de remboursement est automatiquement retenue sur le bulletin de paie tant que l’avance n’est pas soldée.', ton: TonSigh.info),
      kpis: (ctx, rows) {
        final enCours = rows.where((a) => a['statutAvance'] == 'en_cours');
        return [
          KpiSigh(libelle: 'Avances accordées', valeur: nombre(rows.length), icone: LucideIcons.handCoins),
          KpiSigh(libelle: 'Montant total accordé', valeur: money(rows.fold<num>(0, (a, x) => a + n(x['montant']))), icone: LucideIcons.banknote, ton: TonSigh.info),
          KpiSigh(libelle: 'Restant dû', valeur: money(rows.fold<num>(0, (a, x) => a + n(x['montant']) - n(x['rembourse']))), icone: LucideIcons.wallet, ton: TonSigh.attention),
          KpiSigh(libelle: 'Retenues mensuelles', valeur: money(enCours.fold<num>(0, (a, x) => a + n(x['mensualite']))), icone: LucideIcons.trendingDown, ton: TonSigh.danger),
        ];
      },
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, a) => monoTexte(a['reference'])),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (a) => dateFR(DateTime.parse('${a['date']}')), rendu: (_, a) => cellTexte(dateFR(DateTime.parse('${a['date']}')))),
        const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
        const ColonneTableau(cle: 'employe', libelle: 'Agent'),
        const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        ColonneTableau(cle: 'montant', libelle: 'Montant accordé', droite: true, texte: (a) => m(a['montant']), rendu: (_, a) => cellMontant(n(a['montant']), fort: true)),
        const ColonneTableau(cle: 'nbMensualites', libelle: 'Mensualités', droite: true),
        ColonneTableau(cle: 'mensualite', libelle: 'Retenue mensuelle', droite: true, texte: (a) => m(a['mensualite']), rendu: (_, a) => cellMontant(n(a['mensualite']))),
        ColonneTableau(cle: 'rembourse', libelle: 'Remboursé', droite: true, texte: (a) => m(a['rembourse']), rendu: (_, a) => cellMontant(n(a['rembourse']))),
        ColonneTableau(
            cle: 'restant',
            libelle: 'Restant dû',
            droite: true,
            valeur: (a) => n(a['montant']) - n(a['rembourse']),
            texte: (a) => m(n(a['montant']) - n(a['rembourse'])),
            rendu: (_, a) {
              final r = n(a['montant']) - n(a['rembourse']);
              return r > 0 ? cellTexte(m(r), couleur: JetonsShell.danger600, poids: FontWeight.w600) : const BadgeSigh('Soldée', ton: TonSigh.succes);
            }),
      ],
      filtres: const [
        FiltreTableau(nom: 'statutAvance', libelle: 'Statut', options: [OptionChamp('en_cours', 'En cours'), OptionChamp('solde', 'Soldée')]),
      ],
      champs: (mag) => [
        ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: _optionsAgents(mag, salaire: true)),
        const ChampDef(nom: 'date', libelle: 'Date d’octroi', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'montant', libelle: 'Montant accordé (FCFA)', type: TypeChamp.nombre, requis: true),
        const ChampDef(nom: 'nbMensualites', libelle: 'Nombre de mensualités', type: TypeChamp.nombre, requis: true),
        ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.select, requis: true, options: [for (final x in _motifsAvance) OptionChamp(x)]),
        const ChampDef(nom: 'statutAvance', libelle: 'Statut', type: TypeChamp.select, options: [OptionChamp('en_cours', 'En cours de remboursement'), OptionChamp('solde', 'Soldée')]),
      ],
      valeursInitiales: () => {'date': iso(c.aujourdhui), 'nbMensualites': '3', 'statutAvance': 'en_cours'},
      // `beforeSave` : au plus trois mois de salaire — un refus se nomme, rien n'est écrit.
      refuser: (saisie) => paiAvanceRefus(_nombre(saisie['montant']) ?? 0, _agent(c, saisie['employeId'])),
      transformerExistante: (ctx, saisie, existante) => paiAvanceTransform(
          {
            ...saisie,
            'montant': _nombre(saisie['montant']),
            'nbMensualites': _nombre(saisie['nbMensualites']),
            // Ce que le formulaire ne porte pas se GARDE de la fiche : remboursé, numéro, état.
            if (existante != null) ...{'rembourse': existante['rembourse'], 'reference': existante['reference']},
          },
          _agent(c, saisie['employeId']),
          reference: () => paiReferenceSuivante('AVS-', 4, col.toutes)),
      transformer: (ctx, saisie) => paiAvanceTransform({...saisie, 'montant': _nombre(saisie['montant']), 'nbMensualites': _nombre(saisie['nbMensualites'])}, _agent(c, saisie['employeId']),
          reference: () => paiReferenceSuivante('AVS-', 4, col.toutes)),
      referenceToast: (f) => '${f['reference'] ?? ''}',
      etat: _imprimer,
    );
  }
}

const _motifsAvance = ['Frais de santé', 'Frais de scolarité', 'Événement familial', 'Besoin personnel', 'Autre'];
