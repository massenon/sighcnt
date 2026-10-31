import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import '../m4/mat_crud.dart';
import 'adm_commun.dart';

/// Les quatre registres de M13 construits sur `K.crud` : courriers, réunions, interventions d'ambulance, parc technique. Règles et références dans
/// `packages/domaine/lib/src/administration` ; la mise en page est celle de `CrudMat` (copie fidèle de `K.crud`).

const _signDa = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');

num _entier(num n) => n == n.roundToDouble() ? n.toInt() : n;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-courriers
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranCourriers extends StatelessWidget with EcranMaquette {
  const EcranCourriers({super.key});
  @override
  String get titre => 'Courriers (départ / arrivée)';
  @override
  String get description => 'Registre numérisé du courrier administratif, avec suivi des réponses et des accusés de réception.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Imprimer le registre',
            icone: LucideIcons.printer,
            variante: VarianteBouton.secondaire,
            onPressed: () {
              final c = ContexteEcran.of(context);
              final rows = trierPar(c.magasin.collection('courriers').actives, (x) => x['date'], descendant: true);
              matImprimer(context,
                  titre: 'Registre du courrier',
                  sousTitre: 'Arrivées et départs — exercice 2026',
                  cartouche: [
                    ('Courriers enregistrés', nombre(rows.length)),
                    ('Arrivées', nombre(rows.where((x) => x['sens'] == 'arrivee').length)),
                    ('Départs', nombre(rows.where((x) => x['sens'] == 'depart').length)),
                    ('Date d’édition', dateFR(c.aujourdhui)),
                  ],
                  blocs: [
                    BlocTableau(TableauEtat(colonnes: [
                      ColonneEtat(libelle: 'N° d’ordre', valeur: (l) => l['reference']),
                      ColonneEtat(libelle: 'Sens', valeur: (l) => admLibelleSens(l['sens'])),
                      ColonneEtat(libelle: 'Date', valeur: (l) => admDateFR(l['date'])),
                      ColonneEtat(libelle: 'Correspondant', valeur: (l) => l['correspondant']),
                      ColonneEtat(libelle: 'Objet', valeur: (l) => l['objet']),
                      ColonneEtat(libelle: 'Affecté à', valeur: (l) => l['affecteA']),
                      ColonneEtat(libelle: 'Traitement', valeur: (l) => admTraitementCourrier(l['traitement']).$1),
                    ], lignes: rows.take(80).toList())),
                  ],
                  signatures: const [Signature('L’Agent administratif'), _signDa]);
            }),
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('courriers');
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      // E530 : à la modification la référence est GARDÉE (le formulaire ne la porte pas).
      v['reference'] = e?['reference'] ?? admReferenceCourrier(v['sens'], col.toutes.length);
      return matSansNuls(v);
    }

    return CrudMat(
      collection: col,
      entite: 'courrier',
      entiteP: 'courriers',
      prefixeId: 'COU',
      triInitial: 'date',
      sensInitial: 'desc',
      taillePage: 15,
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N° d’ordre', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        ColonneTableau(
            cle: 'sens',
            libelle: 'Sens',
            texte: (r) => admLibelleSens(r['sens']),
            rendu: (_, r) => r['sens'] == 'arrivee' ? const BadgeSigh('Arrivée', ton: TonSigh.info) : const BadgeSigh('Départ', ton: TonSigh.succes)),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => admDateFR(r['date'])),
        const ColonneTableau(cle: 'correspondant', libelle: 'Correspondant'),
        const ColonneTableau(cle: 'objet', libelle: 'Objet'),
        ColonneTableau(cle: 'nature', libelle: 'Nature', rendu: (_, r) => BadgeSigh('${r['nature'] ?? ''}', ton: TonSigh.neutre)),
        const ColonneTableau(cle: 'affecteA', libelle: 'Affecté à'),
        ColonneTableau(
            cle: 'traitement',
            libelle: 'Traitement',
            texte: (r) => admTraitementCourrier(r['traitement']).$1,
            rendu: (_, r) {
              final t = admTraitementCourrier(r['traitement']);
              return BadgeSigh(t.$1, ton: matTon(t.$2));
            }),
        ColonneTableau(
            cle: 'numerise',
            libelle: 'Numérisé',
            texte: (r) => matVrai(r['numerise']) ? 'Oui' : 'Non',
            rendu: (_, r) => matVrai(r['numerise']) ? const BadgeSigh('Oui', ton: TonSigh.succes) : const BadgeSigh('À scanner', ton: TonSigh.attention)),
      ],
      champs: (m) => [
        const ChampDef(nom: 'sens', libelle: 'Sens', type: TypeChamp.select, requis: true, options: [OptionChamp('arrivee', 'Courrier arrivée'), OptionChamp('depart', 'Courrier départ')]),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'correspondant', libelle: 'Correspondant', requis: true, col: ColChamp.plein),
        const ChampDef(nom: 'objet', libelle: 'Objet', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'nature', libelle: 'Nature', type: TypeChamp.select, requis: true, options: admOptions(admNaturesCourrier)),
        ChampDef(nom: 'affecteA', libelle: 'Service destinataire', type: TypeChamp.select, requis: true, options: admOptions(admServicesCourrier)),
        const ChampDef(nom: 'traitement', libelle: 'État du traitement', type: TypeChamp.select, requis: true, options: [
          OptionChamp('en_attente', 'En attente'),
          OptionChamp('en_cours', 'En cours'),
          OptionChamp('traite', 'Traité'),
        ]),
        const ChampDef(nom: 'accuseReception', libelle: 'Accusé de réception', type: TypeChamp.case_),
        const ChampDef(nom: 'numerise', libelle: 'Document numérisé', type: TypeChamp.case_),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      valeursInitiales: () => {'date': iso(c.aujourdhui), 'sens': 'arrivee', 'traitement': 'en_attente', 'nature': 'Lettre'},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        const FiltreTableau(nom: 'sens', libelle: 'Sens', options: [OptionChamp('arrivee', 'Arrivée'), OptionChamp('depart', 'Départ')]),
        const FiltreTableau(nom: 'traitement', libelle: 'Traitement', options: [
          OptionChamp('traite', 'Traité'),
          OptionChamp('en_cours', 'En cours'),
          OptionChamp('en_attente', 'En attente'),
        ]),
        FiltreTableau(nom: 'affecteA', libelle: 'Service', options: admOptions(admServicesFiltreCourrier)),
      ],
      kpis: (ctx, rows) => [for (final k in admKpisCourriers(rows)) admKpi(k)],
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Fiche de courrier',
          sousTitre: '${r['reference']}',
          cartouche: [
            ('Référence', '${r['reference']}'),
            ('Sens', admLibelleSens(r['sens'])),
            ('Date', admDateFR(r['date'])),
            ('Correspondant', '${r['correspondant'] ?? ''}'),
            ('Nature', '${r['nature'] ?? ''}'),
            ('Service destinataire', '${r['affecteA'] ?? ''}'),
          ],
          blocs: [
            matBlocRubriques([
              ('Objet', '${r['objet'] ?? ''}'),
              ('État du traitement', admTraitementCourrier(r['traitement']).$1),
              ('Accusé de réception', matOuiNon(r['accuseReception'])),
              ('Document numérisé', matOuiNon(r['numerise'])),
              ('Observations', matVrai(r['observations']) ? '${r['observations']}' : '—'),
            ]),
          ],
          signatures: const [Signature('L’Agent administratif'), _signDa]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-reunions
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranReunions extends StatelessWidget with EcranMaquette {
  const EcranReunions({super.key});
  @override
  String get titre => 'Réunions';
  @override
  String get description => 'Planification des réunions, convocations, ordres du jour et comptes rendus.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('reunions');
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      // E531 : série du registre (archivés compris), gardée à la modification.
      v['reference'] = e?['reference'] ?? admReferenceSuivante('RU-2026-', 3, col.toutes);
      v['participants'] = admNombre(v['participants']);
      v['heure'] = admHeure(v['heure']);
      return matSansNuls(v);
    }

    return CrudMat(
      collection: col,
      entite: 'réunion',
      entiteP: 'réunions',
      prefixeId: 'REU',
      triInitial: 'date',
      sensInitial: 'desc',
      taillePage: 12,
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => admDateFR(r['date'])),
        const ColonneTableau(cle: 'heure', libelle: 'Heure', sansCoupure: true),
        ColonneTableau(cle: 'type', libelle: 'Type', rendu: (_, r) => BadgeSigh('${r['type'] ?? ''}', ton: TonSigh.navy)),
        const ColonneTableau(cle: 'lieu', libelle: 'Lieu'),
        const ColonneTableau(cle: 'president', libelle: 'Présidée par'),
        ColonneTableau(cle: 'participants', libelle: 'Participants', droite: true, valeur: (r) => r['participants'], texte: (r) => matTexteNombre(r['participants'])),
        ColonneTableau(
            cle: 'statutReunion',
            libelle: 'Statut',
            triable: false,
            valeur: (r) => admReunionAVenir(r, c.aujourdhui) ? 'À venir' : 'Tenue',
            texte: (r) => admReunionAVenir(r, c.aujourdhui) ? 'À venir' : 'Tenue',
            rendu: (_, r) => admReunionAVenir(r, c.aujourdhui) ? const BadgeSigh('À venir', ton: TonSigh.info) : const BadgeSigh('Tenue', ton: TonSigh.succes)),
        ColonneTableau(
            cle: 'compteRendu',
            libelle: 'Compte rendu',
            texte: (r) => matVrai(r['compteRendu']) ? 'Rédigé' : 'À rédiger',
            rendu: (_, r) => matVrai(r['compteRendu']) ? const BadgeSigh('Rédigé', ton: TonSigh.succes) : const BadgeSigh('À rédiger', ton: TonSigh.attention)),
      ],
      champs: (m) => [
        ChampDef(nom: 'type', libelle: 'Type de réunion', type: TypeChamp.select, requis: true, options: admOptions(admTypesReunion)),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        admChampHeure('heure', 'Heure'),
        ChampDef(nom: 'lieu', libelle: 'Lieu', type: TypeChamp.select, options: admOptions(admLieuxReunion)),
        ChampDef(nom: 'president', libelle: 'Présidée par', type: TypeChamp.select, requis: true, options: admOptionsAgents(m)),
        const ChampDef(nom: 'participants', libelle: 'Nombre de participants', type: TypeChamp.nombre),
        const ChampDef(nom: 'ordreDuJour', libelle: 'Ordre du jour', type: TypeChamp.textarea, lignes: 3, requis: true, col: ColChamp.plein),
        const ChampDef(nom: 'compteRendu', libelle: 'Compte rendu rédigé', type: TypeChamp.case_),
        const ChampDef(nom: 'resolutions', libelle: 'Résolutions adoptées', type: TypeChamp.textarea, lignes: 3, col: ColChamp.plein),
      ],
      valeursInitiales: () => {'date': iso(c.aujourdhui), 'heure': '09:00', 'lieu': 'Salle de réunion', 'participants': '8'},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [FiltreTableau(nom: 'type', libelle: 'Type', options: admOptions(admTypesReunion))],
      kpis: (ctx, rows) => [for (final k in admKpisReunions(rows, c.aujourdhui)) admKpi(k)],
      etat: (ctx, r) {
        final futur = admReunionAVenir(r, c.aujourdhui);
        matImprimer(ctx,
            titre: futur ? 'Convocation à une réunion' : 'Compte rendu de réunion',
            sousTitre: '${r['type']} — ${admDateFR(r['date'])}',
            cartouche: [
              ('Référence', '${r['reference']}'),
              ('Type', '${r['type']}'),
              ('Date', admDateFR(r['date'])),
              ('Heure', '${r['heure'] ?? ''}'),
              ('Lieu', '${r['lieu'] ?? ''}'),
              ('Présidée par', '${r['president'] ?? ''}'),
            ],
            blocs: [
              const BlocTexte('Ordre du jour', gras: true),
              BlocTexte('${r['ordreDuJour'] ?? ''}'),
              if (futur)
                const BlocTexte('Les personnes concernées sont priées de bien vouloir prendre toutes dispositions utiles pour prendre part à cette réunion.')
              else ...[
                const BlocTexte('Résolutions adoptées', gras: true),
                BlocTexte(matVrai(r['resolutions']) ? '${r['resolutions']}' : 'Aucune résolution consignée.'),
                BlocTexte('Nombre de participants : ${matTexteNombre(r['participants'])}'),
              ],
            ],
            signatures: futur ? const [_signDa] : [const Signature('Le Secrétaire de séance'), Signature('Le Président de séance', nom: '${r['president'] ?? ''}')]);
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-ambulance
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranAmbulance extends StatelessWidget with EcranMaquette {
  const EcranAmbulance({super.key});
  @override
  String get titre => 'Interventions ambulance';
  @override
  String get description => 'Registre des sorties d’ambulance : transports sanitaires, urgences et évacuations.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('ambulance');
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRecomposerDateHeure(v, 'dateHeure');
      final p = matPatientDe(c.magasin, v['patientCode']);
      if (p != null) {
        v['patientId'] = p['id'];
        v['patient'] = '${p['nom']} ${p['prenom']}';
      }
      v['kilometrage'] = admNombre(v['kilometrage']);
      v['tarif'] = _entier(admTarifAmbulance(v['tarif'], v['kilometrage']));
      // E534 : série du registre (archivés compris), gardée à la modification.
      v['reference'] = e?['reference'] ?? admReferenceSuivante('AM-2026-', 4, col.toutes);
      return matSansNuls(v);
    }

    return CrudMat(
      collection: col,
      entite: 'intervention',
      entiteP: 'interventions',
      prefixeId: 'AMB',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      taillePage: 15,
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        ColonneTableau(cle: 'dateHeure', libelle: 'Date et heure', sansCoupure: true, valeur: (r) => matMs(r['dateHeure']), texte: (r) => matDateHeure(r['dateHeure'])),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (r) => '${r['patient'] ?? ''} ${r['patientCode'] ?? ''}',
            rendu: (_, r) => matCelPatient('${r['patient'] ?? ''}', '${r['patientCode'] ?? ''}')),
        ColonneTableau(
            cle: 'motif',
            libelle: 'Motif',
            rendu: (_, r) => BadgeSigh('${r['motif'] ?? ''}', ton: '${r['motif']}'.startsWith('Urgence') ? TonSigh.danger : TonSigh.navy)),
        const ColonneTableau(cle: 'destination', libelle: 'Destination'),
        ColonneTableau(cle: 'kilometrage', libelle: 'Km', droite: true, texte: (r) => matTexteNombre(r['kilometrage'])),
        const ColonneTableau(cle: 'chauffeur', libelle: 'Chauffeur'),
        const ColonneTableau(cle: 'accompagnant', libelle: 'Accompagnant'),
        ColonneTableau(cle: 'tarif', libelle: 'Montant', droite: true, texte: (r) => money(r['tarif'], avecDevise: false)),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (r) => admEtatsIntervention['${r['etat']}']?.$1 ?? '—',
            rendu: (_, r) {
              final x = admEtatsIntervention['${r['etat']}'] ?? ('—', 'neutral');
              return BadgeSigh(x.$1, ton: matTon(x.$2));
            }),
        ColonneTableau(
            cle: 'facture',
            libelle: 'Facturation',
            texte: (r) => matVrai(r['facture']) ? 'Facturée' : 'À facturer',
            rendu: (_, r) => matVrai(r['facture']) ? const BadgeSigh('Facturée', ton: TonSigh.succes) : const BadgeSigh('À facturer', ton: TonSigh.attention)),
      ],
      champs: (m) {
        final agents = admOptionsAgents(m);
        return [
          ChampDef(nom: 'patientCode', libelle: 'Patient', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: matOptionsPatients(m)),
          ...matChampsDateHeure('dateHeure', 'Date et heure'),
          ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.select, requis: true, options: admOptions(admMotifsIntervention)),
          const ChampDef(nom: 'destination', libelle: 'Destination', requis: true, col: ColChamp.plein),
          const ChampDef(nom: 'kilometrage', libelle: 'Kilométrage parcouru', type: TypeChamp.nombre, requis: true),
          const ChampDef(nom: 'etat', libelle: 'État de l’intervention', type: TypeChamp.select, requis: true, options: [
            OptionChamp('demandee', 'Demandée'),
            OptionChamp('en_cours', 'En cours'),
            OptionChamp('terminee', 'Terminée'),
          ]),
          ChampDef(nom: 'chauffeur', libelle: 'Chauffeur', type: TypeChamp.select, options: agents),
          ChampDef(nom: 'accompagnant', libelle: 'Accompagnant médical', type: TypeChamp.select, options: agents),
          const ChampDef(nom: 'tarif', libelle: 'Montant facturé (FCFA)', type: TypeChamp.nombre),
          const ChampDef(nom: 'facture', libelle: 'Intervention facturée', type: TypeChamp.case_),
        ];
      },
      valeursInitiales: () => {
        if (c.magasin.collection('personnel').actives.any((e) => e['nomComplet'] == 'TCHANE Nourou')) 'chauffeur': 'TCHANE Nourou',
        'facture': false,
        'kilometrage': '10',
        'etat': 'demandee',
      },
      valeursEdition: (f) => matValeursEdition(f, ['dateHeure']),
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        const FiltreTableau(nom: 'etat', libelle: 'État', options: [OptionChamp('demandee', 'Demandée'), OptionChamp('en_cours', 'En cours'), OptionChamp('terminee', 'Terminée')]),
        FiltreTableau(nom: 'motif', libelle: 'Motif', options: admOptions(admMotifsIntervention)),
        FiltreTableau(
            nom: 'facture',
            libelle: 'Facturation',
            options: const [OptionChamp('oui', 'Facturées'), OptionChamp('non', 'À facturer')],
            correspond: (a, v) => v == 'oui' ? matVrai(a['facture']) : !matVrai(a['facture'])),
      ],
      kpis: (ctx, rows) => [for (final k in admKpisInterventions(rows, c.aujourdhui)) admKpi(k)],
      etat: (ctx, a) => matImprimer(ctx,
          titre: 'Fiche d’intervention — ambulance',
          sousTitre: '${a['reference']}',
          cartouche: [
            ('Référence', '${a['reference']}'),
            ('Date et heure', matDateHeure(a['dateHeure'])),
            ('Patient', '${a['patient'] ?? ''}'),
            ('Dossier', '${a['patientCode'] ?? ''}'),
            ('Motif', '${a['motif'] ?? ''}'),
            ('Destination', '${a['destination'] ?? ''}'),
          ],
          blocs: [
            matBlocRubriques([
              ('Kilométrage parcouru', '${matTexteNombre(a['kilometrage'])} km'),
              ('Chauffeur', '${a['chauffeur'] ?? ''}'),
              ('Accompagnant médical', '${a['accompagnant'] ?? ''}'),
              ('Montant facturé', money(a['tarif'])),
              ('Facturation', matVrai(a['facture']) ? 'Facturée' : 'À facturer'),
            ]),
          ],
          signatures: [Signature('Le Chauffeur', nom: '${a['chauffeur'] ?? ''}'), Signature('L’Accompagnant médical', nom: '${a['accompagnant'] ?? ''}'), _signDa]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-maintenance — parc technique
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMaintenance extends StatefulWidget with EcranMaquette {
  const EcranMaintenance({super.key});
  @override
  String get titre => 'Parc technique & maintenance';
  @override
  String get description => 'Équipements de la clinique, état de marche, entretiens périodiques et pannes signalées.';
  @override
  String get regle =>
      'Un automate en panne arrête le laboratoire : l’état de marche prime sur tout le reste, et c’est la première colonne. Le parc amorcé ici est une proposition à compléter — aucun document de cadrage n’inventorie les équipements, l’inventaire SAGE ne porte que les articles. Les fiches non vérifiées sont signalées, jamais présentées comme relevées.';

  @override
  State<EcranMaintenance> createState() => _EcranMaintenanceState();
}

class _EcranMaintenanceState extends State<EcranMaintenance> {
  bool _amorce = false;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('materiel');
    // Amorçage à l'ouverture, comme la maquette : le parc que les documents laissent DÉDUIRE (rien de plus), jamais sur un jeu vidé.
    if (!_amorce) {
      _amorce = true;
      if (col.toutes.isEmpty) {
        for (final f in admAmorcerMateriel(c.aujourdhui).reversed) {
          col.inserer(f);
        }
      }
    }
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      v['reference'] = e?['reference'] ?? admReferenceSuivante('EQ-', 3, col.toutes);
      v['periodiciteMois'] = admNombre(v['periodiciteMois']);
      // Une fiche renseignée cesse d'être « à compléter » : le marquage disparaît par la SAISIE.
      v['aCompleter'] = admMaterielACompleter(v);
      return matSansNuls(v);
    }

    return CrudMat(
      collection: col,
      entite: 'équipement',
      entiteP: 'équipements',
      prefixeId: 'MAT',
      triInitial: 'libelle',
      taillePage: 14,
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            sansCoupure: true,
            texte: (r) => admEtatMateriel(r['etat']).$2,
            rendu: (_, r) {
              final e = admEtatMateriel(r['etat']);
              return BadgeSigh(e.$2, ton: e.$3 == 'danger' ? TonSigh.danger : (e.$3 == 'success' ? TonSigh.succes : TonSigh.neutre));
            }),
        const ColonneTableau(cle: 'libelle', libelle: 'Équipement'),
        ColonneTableau(cle: 'categorie', libelle: 'Catégorie', rendu: (_, r) => BadgeSigh('${r['categorie'] ?? ''}', ton: TonSigh.navy)),
        const ColonneTableau(cle: 'localisation', libelle: 'Localisation'),
        ColonneTableau(
            cle: 'marque',
            libelle: 'Marque',
            texte: (r) => matVrai(r['marque']) ? '${r['marque']}' : '—',
            rendu: (_, r) => matVrai(r['marque'])
                ? Text('${r['marque']}', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))
                : const Text('à compléter', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic))),
        ColonneTableau(
            cle: 'dernierEntretien',
            libelle: 'Dernier entretien',
            sansCoupure: true,
            texte: (r) => matVrai(r['dernierEntretien']) ? admDateFR(r['dernierEntretien']) : '—',
            rendu: (_, r) {
              if (!matVrai(r['dernierEntretien'])) {
                return const Text('jamais', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic));
              }
              final t = Text(admDateFR(r['dernierEntretien']), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14));
              if (!admEntretienEchu(r, c.aujourdhui)) return t;
              return Row(mainAxisSize: MainAxisSize.min, children: [t, const SizedBox(width: 6), const BadgeSigh('échu', ton: TonSigh.attention)]);
            }),
        ColonneTableau(
            cle: 'periodiciteMois',
            libelle: 'Périodicité',
            droite: true,
            texte: (r) => matVrai(r['periodiciteMois']) ? '${matTexteNombre(r['periodiciteMois'])} mois' : '—'),
      ],
      champs: (m) => [
        const ChampDef(nom: 'libelle', libelle: 'Équipement', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'categorie', libelle: 'Catégorie', type: TypeChamp.select, requis: true, options: admOptions(admCategoriesMateriel)),
        ChampDef(nom: 'localisation', libelle: 'Localisation', type: TypeChamp.select, requis: true, options: admOptions(admLocalisationsMateriel)),
        ChampDef(nom: 'etat', libelle: 'État de marche', type: TypeChamp.select, requis: true, options: [for (final e in admEtatsMateriel) OptionChamp(e.$1, e.$2)]),
        const ChampDef(nom: 'marque', libelle: 'Marque et modèle'),
        const ChampDef(nom: 'numeroSerie', libelle: 'Numéro de série'),
        const ChampDef(nom: 'miseEnService', libelle: 'Mise en service', type: TypeChamp.date),
        const ChampDef(nom: 'periodiciteMois', libelle: 'Périodicité d’entretien (mois)', type: TypeChamp.nombre),
        const ChampDef(nom: 'dernierEntretien', libelle: 'Dernier entretien', type: TypeChamp.date),
        const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      valeursInitiales: () => {'etat': 'service', 'periodiciteMois': '12', 'dernierEntretien': iso(c.aujourdhui)},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        // Trois lectures d'une même population, pas trois populations : un filtre, et non des onglets.
        FiltreTableau(
            nom: 'suivi',
            libelle: 'Suivi',
            options: const [OptionChamp('panne', 'En panne'), OptionChamp('echu', 'Entretien échu'), OptionChamp('acompleter', 'Fiche à compléter')],
            correspond: (r, v) => admSuiviMateriel(r, v, c.aujourdhui)),
        FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: admOptions(admCategoriesMateriel)),
        FiltreTableau(nom: 'localisation', libelle: 'Localisation', options: admOptions(admLocalisationsMateriel)),
      ],
      kpis: (ctx, rows) => [for (final k in admKpisMateriel(rows, c.aujourdhui)) admKpi(k)],
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Fiche d’équipement',
          sousTitre: '${r['libelle']} — ${r['reference']}',
          cartouche: [
            ('Référence', '${r['reference']}'),
            ('Catégorie', '${r['categorie'] ?? ''}'),
            ('Localisation', '${r['localisation'] ?? ''}'),
            ('État', admEtatMateriel(r['etat']).$2),
            ('Marque et modèle', matVrai(r['marque']) ? '${r['marque']}' : 'non relevé'),
            ('N° de série', matVrai(r['numeroSerie']) ? '${r['numeroSerie']}' : 'non relevé'),
            ('Mise en service', matVrai(r['miseEnService']) ? admDateFR(r['miseEnService']) : 'non relevée'),
            ('Périodicité d’entretien', matVrai(r['periodiciteMois']) ? '${matTexteNombre(r['periodiciteMois'])} mois' : 'non définie'),
            ('Dernier entretien', matVrai(r['dernierEntretien']) ? admDateFR(r['dernierEntretien']) : 'jamais'),
          ],
          blocs: [
            const BlocTexte('Observation', gras: true),
            BlocTexte(matVrai(r['observation']) ? '${r['observation']}' : 'Aucune observation consignée.'),
            if (matVrai(r['aCompleter']))
              const BlocTexte('Fiche à compléter : marque, numéro de série ou date de mise en service non relevés sur la machine.', italique: true),
          ],
          signatures: const [Signature('L’Ingénieur biomédical'), _signDa]),
    );
  }
}
