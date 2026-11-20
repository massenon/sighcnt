import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tbb_commun.dart';

/// Tableaux de bord de poste « B » : ambulance, aide-soignante, technicien d'échographie, surveillant, assistant de direction. Lecture seule :
/// tout est compté depuis les registres (règles : `packages/domaine/lib/src/tableaux_de_bord/tbb_regles.dart`, rejouées sur les vecteurs de la maquette).

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-ambulancier
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashAmbulancier extends StatelessWidget with EcranMaquette {
  const EcranDashAmbulancier({super.key});

  @override
  String get titre => 'Tableau de bord — Ambulance';

  @override
  String get description => 'Interventions, transports sanitaires, consultations et soins à domicile.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['ambulance', 'consultations'],
        construire: (c) {
          final consultations = lire(c, 'consultations');
          final releve = tbbAmbulancier(ambulance: lire(c, 'ambulance'), consultations: consultations, auj: c.aujourdhui);
          final dom = tbbDomicile(consultations).take(10).toList();
          return TbbDisposition(
            releve: releve,
            raccourcis: [
              raccourci('m13-ambulance', 'ambulance', 'Interventions', 'Registre des sorties'),
              raccourci('m2-domicile', 'house-plus', 'Soins à domicile', 'Planification et facturation'),
            ],
            parcours: const [
              ParcoursDef('Assurer une évacuation', 'ambulance', action: 'Interventions', detail: 'Un transfert est demandé.', [
                EtapeDef('Prendre l’intervention', ecran: 'm13-ambulance'),
                EtapeDef('Emporter la fiche de référence', ecran: 'm1-reference', detail: 'Elle porte les constantes et les traitements déjà donnés.'),
                EtapeDef('Renseigner départ et arrivée', ecran: 'm1-reference', detail: 'Ces heures font foi : c’est vous qui les inscrivez.'),
                EtapeDef('Clore l’intervention', ecran: 'm13-ambulance'),
              ]),
            ],
            sections: [
              CarteSigh(
                titre: 'Consultations et soins à domicile',
                actions: [lienIcone('Planifier', 'plus', () => c.aller('m2-domicile'))],
                sansRemplissage: dom.isNotEmpty,
                child: dom.isEmpty
                    ? videCarte('Aucune intervention à domicile enregistrée.', 'house')
                    : MiniTableauSigh(colonnes: [
                        ColonneMini('Date', (x) => tbbCellulesDomicile(x)[0]),
                        ColonneMini('Patient', (x) => tbbCelluleCle(x['patient'])),
                        ColonneMini('Motif', (x) => tbbCelluleCle(x['motif'])),
                        ColonneMini('Praticien', (x) => tbbCelluleCle(x['medecin'])),
                        ColonneMini('Statut', (x) => '', rendu: (x) => statutBadge(x['statut'])),
                      ], lignes: dom),
              ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-aide-soignant — elle ne consulte AUCUN résultat d'analyse : son tableau montre les hospitalisés, jamais un résultat.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashAideSoignant extends StatelessWidget with EcranMaquette {
  const EcranDashAideSoignant({super.key});

  @override
  String get titre => 'Tableau de bord — Aide-soignante';

  @override
  String get description => 'Patients hospitalisés, soins du jour et visites — sans aucun résultat d’analyse.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['admissions', 'releves', 'visitesHospi'],
        construire: (c) => TbbDisposition(
          releve: tbbAideSoignant(
              admissions: lire(c, 'admissions'), releves: lire(c, 'releves'), visites: lire(c, 'visitesHospi'), auj: c.aujourdhui),
          raccourcis: [
            raccourci('m3-admissions', 'bed-double', 'Patients hospitalisés', 'Séjours en cours'),
            raccourci('m3-surveillance', 'activity', 'Fiche de surveillance', 'Constantes et courbe'),
            raccourci('m3-visites-patients', 'users-round', 'Visites aux hospitalisés', 'Registre du jour'),
            raccourci('m1-constantes', 'thermometer', 'Relever des constantes', 'Température, TA, pouls'),
          ],
          parcours: const [
            ParcoursDef('Prendre soin d’un hospitalisé', 'hand-heart', action: 'Voir les patients', detail: 'Les patients dont vous avez la charge.', [
              EtapeDef('Voir les patients hospitalisés', ecran: 'm3-admissions'),
              EtapeDef('Relever les constantes', ecran: 'm1-constantes'),
              EtapeDef('Reporter sur la fiche de surveillance', ecran: 'm3-surveillance'),
              EtapeDef('Signaler toute anomalie', poste: 'Infirmier'),
            ]),
            ParcoursDef('Accueillir les visites', 'users-round', action: 'Visites', detail: 'Les proches se présentent.', [
              EtapeDef('Enregistrer la visite', ecran: 'm3-visites-patients'),
              EtapeDef('Orienter vers la chambre', ecran: 'm3-plan-lits'),
            ]),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-echographiste — AUCUN accès financier : son tableau ne porte aucun montant.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashEchographiste extends StatelessWidget with EcranMaquette {
  const EcranDashEchographiste({super.key});

  @override
  String get titre => 'Tableau de bord — Échographie';

  @override
  String get description => 'Examens d’imagerie à réaliser et comptes rendus à rendre au prescripteur.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['resultatsImagerie', 'examensImagerie'],
        construire: (c) => TbbDisposition(
          releve: tbbEchographiste(
              resultats: lire(c, 'resultatsImagerie'),
              examensAuCatalogue: tbbActives(lire(c, 'examensImagerie')).length,
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m2-imagerie', 'scan-line', 'Imagerie médicale', 'Saisie des comptes rendus'),
            raccourci('m1-patients', 'users', 'Répertoire des patients', 'Lecture seule'),
            raccourci('m2-prescriptions', 'clipboard-plus', 'Prescriptions', 'Lecture seule'),
          ],
          parcours: const [
            ParcoursDef('Réaliser un examen', 'scan-line', action: 'Nouveau compte rendu', detail: 'Un examen d’imagerie est prescrit.', [
              EtapeDef('Vérifier l’indication du prescripteur',
                  ecran: 'm2-prescriptions', detail: 'En lecture seule : vous ne modifiez pas la prescription d’un autre service.'),
              EtapeDef('Ouvrir le compte rendu et saisir', ecran: 'm2-imagerie', detail: 'Listes de choix partout ; Annexes et Conclusion restent libres.'),
              EtapeDef('Rédiger la conclusion', ecran: 'm2-imagerie', detail: 'Obligatoire avant de rendre : c’est elle que le prescripteur lit.'),
              EtapeDef('Rendre au prescripteur', ecran: 'm2-imagerie'),
              EtapeDef('Le clinicien décide', poste: 'Consultation'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Ce que votre profil ne voit pas',
                child: NoteSigh(
                    'Votre compte n’a aucun accès financier — ni caisse, ni assurances, ni comptabilité. C’est une condition posée par la Direction : un '
                    'manipulateur qui verrait la caisse pourrait faire dépendre l’examen du paiement, ce qui n’est pas son rôle. Le dossier patient vous '
                    'est ouvert en lecture seule, et vous ne modifiez pas les prescriptions d’un autre service.',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-surveillant — missions 1 et 5 de la description de poste de l'Infirmier Général.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashSurveillant extends StatelessWidget with EcranMaquette {
  const EcranDashSurveillant({super.key});

  @override
  String get titre => 'Tableau de bord — Surveillant';

  @override
  String get description => 'Retards, absences, présences et planning du personnel paramédical.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['presences', 'planning', 'conges', 'personnel'],
        construire: (c) => TbbDisposition(
          releve: tbbSurveillant(
              presences: lire(c, 'presences'),
              planning: lire(c, 'planning'),
              conges: lire(c, 'conges'),
              personnel: lire(c, 'personnel'),
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m10-presences', 'user-check', 'Présences et retards', 'Pointage du jour'),
            raccourci('m10-planning', 'calendar-clock', 'Planning et gardes', 'Vacations du personnel'),
            raccourci('m10-conges', 'palmtree', 'Congés et absences', 'Demandes et soldes'),
            raccourci('m10-stats-gardes', 'chart-column', 'Statistiques de garde', 'Charge par agent'),
          ],
          parcours: const [
            ParcoursDef('Contrôler les présences', 'user-check', action: 'Présences du jour', detail: 'Mission 1 de votre description de poste.', [
              EtapeDef('Pointer les présences', ecran: 'm10-presences'),
              EtapeDef('Constater ET notifier les retards',
                  ecran: 'm10-presences', detail: 'Votre indicateur : 95 % des retards constatés et notifiés. Constater ne suffit pas.'),
              EtapeDef('Signaler les absences non autorisées', ecran: 'm10-conges'),
            ]),
            ParcoursDef('Faire le planning', 'calendar-clock', action: 'Planning', detail: 'Mission 5 — personnel paramédical.', [
              EtapeDef('Poser les vacations',
                  ecran: 'm10-planning', detail: 'Garde 24 h, permanence 08h–18h, repos. Les incompatibilités sont bloquées.'),
              EtapeDef('Vérifier la charge par agent',
                  ecran: 'm10-stats-gardes', detail: 'Repos et congés exclus : sinon les plus reposés paraissent les plus chargés.'),
              EtapeDef('Les primes suivent le planning validé', poste: 'Paie', detail: 'RG-11.'),
            ]),
            ParcoursDef('Superviser les soins', 'clipboard-check', action: 'Vérifier', detail: 'Contrôler l’exécution, sans exécuter.', [
              EtapeDef('Vérifier les documents de transfusion', ecran: 'm3-transfusion', detail: 'Activité 2 de votre description de poste.'),
              EtapeDef('Contrôler les registres', ecran: 'm3-surveillance'),
              EtapeDef('Transmettre les statistiques à la zone sanitaire', ecran: 'rapports-bibliotheque', detail: '100 % à bonne date.'),
            ]),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-assistant-comptable (« Assistant de Direction ») — activités 7 et 8 : recouvrer les créances, « SURTOUT les assureurs ».
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashAssistantDirection extends StatelessWidget with EcranMaquette {
  const EcranDashAssistantDirection({super.key});

  @override
  String get titre => 'Tableau de bord — Assistant de Direction';

  @override
  String get description => 'Créances assureur, obligations fiscales, point de caisse et inventaires.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['factures', 'echeancesFiscales', 'ecritures', 'produits'],
        construire: (c) => TbbDisposition(
          releve: tbbAssistantDirection(
              factures: lire(c, 'factures'),
              echeances: lire(c, 'echeancesFiscales'),
              ecritures: lire(c, 'ecritures'),
              produits: lire(c, 'produits'),
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m9-creances', 'hourglass', 'Créances', 'Recouvrement — activités 7 et 8'),
            raccourci('m12-echeances', 'calendar-clock', 'Échéances fiscales', 'Impôts, CNSS, CCIB — activité 13'),
            raccourci('m8-caisse', 'banknote', 'Point de caisse', 'Activité 25 — lecture seule'),
            raccourci('m12-ecritures', 'book-open', 'Écritures comptables', 'Livres de compte — activité 1'),
          ],
          parcours: const [
            ParcoursDef('Recouvrer les créances', 'hourglass', action: 'Créances', detail: 'Activités 7 et 8 de votre description de poste.', [
              EtapeDef('Voir les créances assureur', ecran: 'm9-creances'),
              EtapeDef('Émettre la facture mère', ecran: 'm9-facture-mere', detail: 'Elle n’est émise que si elle se recoupe exactement avec ses filles.'),
              EtapeDef('Relancer les compagnies', ecran: 'm9-relances'),
              EtapeDef('Enregistrer le règlement', ecran: 'm9-facture-mere'),
            ]),
            ParcoursDef('Tenir les obligations', 'calendar-clock', action: 'Échéances', detail: 'Activité 13 — Impôts, CNSS, CCIB.', [
              EtapeDef('Suivre le calendrier fiscal', ecran: 'm12-echeances'),
              EtapeDef('Déclarer à bonne date', ecran: 'm12-echeances'),
              EtapeDef('Payer et classer la quittance', ecran: 'm12-echeances'),
            ]),
            ParcoursDef('Point de caisse et inventaires', 'banknote', action: 'Point de caisse', detail: 'Activités 23 et 25.', [
              EtapeDef('Faire le point journalier de la caisse', ecran: 'm8-caisse', detail: 'En lecture : vous constatez, vous n’encaissez pas.'),
              EtapeDef('Inventorier réactifs et médicaments d’urgence', ecran: 'm5-reactifs'),
              EtapeDef('Rendre compte à la Direction', poste: 'DAF'),
            ]),
          ],
        ),
      );
}
