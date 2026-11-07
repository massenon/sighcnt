import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-receptionniste` — « Tableau de bord — Accueil » : RG-09 — la validité de la carte est la PREMIÈRE question posée au guichet, et elle décide
/// de la facturation. Vient ensuite la file. Les onze chaînes dictées par la Direction montrent chacune la SUITE : l'accueil doit savoir quel poste
/// prend le relais, faute de quoi le patient arrive à la caisse sans que la caisse sache pourquoi.
class EcranDashReception extends StatelessWidget with EcranMaquette {
  const EcranDashReception({super.key});

  @override
  String get titre => 'Tableau de bord — Accueil';

  @override
  String get description =>
      'Création de dossiers, rendez-vous du jour, visites et orientation des patients.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['fileAttente', 'patients', 'consultations']),
      builder: (context, _) {
        final d = tbaReception(
            fileAttente: tbaActives(c, 'fileAttente'),
            patients: tbaActives(c, 'patients'),
            consultations: tbaActives(c, 'consultations'),
            auj: c.aujourdhui);
        return TbaDash(
          premier: d.premier,
          rapides: [
            // Les six boutons du Bug 2 des Instructions, posés AVANT les parcours : l'ordre demandé est structurel.
            tbaAccesRapides(c, const [
              ('m1-patients', 'users', 'Répertoire patient', null),
              ('m1-constantes', 'activity', 'Constantes à l’accueil', null),
              ('m2-rendezvous', 'calendar-plus', 'Agenda et rendez-vous', null),
              ('m3-visites-patients', 'door-open', 'Visites aux hospitalisés', null),
              ('m2-file-attente', 'list-ordered', 'File d’attente', null),
              ('m2-affichage', 'monitor', 'Écran d’appel des patients', null),
            ]),
            tbaCarte('Ce que vous faites ici — les parcours de l’accueil', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Rendez-vous et consultations du jour',
                d.rendezVousDuJour.isEmpty
                    ? const VideSigh('Aucun rendez-vous programmé aujourd’hui.', icone: LucideIcons.calendar)
                    : tbaMiniTableau([
                        ColonneMini('Heure', (x) => tbaHeure(x['date'])),
                        ColonneMini('Dossier', (x) => '${x['patientCode'] ?? ''}', rendu: (x) => tbaMono(x['patientCode'])),
                        ColonneMini('Patient', (x) => '${x['patient'] ?? ''}'),
                        ColonneMini('Motif', (x) => '${x['motif'] ?? ''}'),
                        ColonneMini('Praticien', (x) => '${x['medecin'] ?? ''}'),
                        ColonneMini('Statut', (x) => '', rendu: (x) => statutBadge(x['statut'])),
                      ], d.rendezVousDuJour),
                actions: [tbaLien(c, 'm2-agenda', 'Agenda complet', 'calendar')],
                sansRemplissage: d.rendezVousDuJour.isNotEmpty),
          ],
        );
      },
    );
  }
}

const _parcours = [
  ParcoursTba('Nouveau patient', 'user-plus', 'Ouvrir un dossier', 'Le patient n’a jamais été reçu à la clinique.', [
    EtapeTba('Créer le dossier patient',
        ecran: 'm1-patients', detail: 'Code CNT/[n°]/[année] attribué automatiquement — RG-01, non modifiable ensuite.'),
    EtapeTba('Relever les constantes',
        ecran: 'm1-constantes', detail: 'Température, TA, pouls, SpO₂, poids, taille. Elles alimentent la feuille de surveillance.'),
    EtapeTba('Inscrire à la file d’attente', ecran: 'm2-file-attente'),
    // Le dossier de consultation est la ZONE 2 : il appartient au soignant (14/09/2026). L'étape est nommée, pas offerte.
    EtapeTba('Le soignant ouvre le dossier de consultation', poste: 'Consultation'),
  ]),
  ParcoursTba('Rendez-vous de consultation', 'calendar-plus', 'Prendre le rendez-vous', 'Le patient appelle ou se présente pour une date à venir.', [
    EtapeTba('Prendre le rendez-vous',
        ecran: 'm2-rendezvous', detail: 'Généraliste et sage-femme sept jours sur sept ; chirurgien-gynécologue les lundi et jeudi.'),
    EtapeTba('Vérifier ou créer le dossier', ecran: 'm1-patients'),
    EtapeTba('Le jour venu : constantes puis file d’attente', ecran: 'm1-constantes'),
    EtapeTba('Le soignant reçoit', poste: 'Consultation'),
    EtapeTba('Règlement', poste: 'Caisse'),
  ]),
  ParcoursTba('Rendez-vous de contrôle', 'calendar-check', 'Programmer le contrôle', 'Le patient revient après un traitement ou un examen.', [
    EtapeTba('Programmer le contrôle', ecran: 'm2-rendezvous', detail: 'Le motif « contrôle » distingue la venue d’une première consultation.'),
    EtapeTba('Vérifier que les résultats sont rendus',
        ecran: 'm5-resultats', detail: 'Un contrôle sans son résultat fait revenir le patient pour rien.'),
    EtapeTba('Relever les constantes à l’arrivée', ecran: 'm1-constantes'),
    EtapeTba('Le soignant reçoit', poste: 'Consultation'),
  ]),
  ParcoursTba('Patient référé par un autre centre', 'download', 'Enregistrer la référence', 'Le patient arrive avec sa fiche de référence.', [
    EtapeTba('Enregistrer la fiche de référence entrante',
        ecran: 'm1-reference', detail: 'La pièce d’origine est conservée et numérisée : elle porte ce que le centre a déjà fait.'),
    EtapeTba('Créer le dossier local', ecran: 'm1-patients', detail: 'Sans effacer la pièce d’origine ni sa couverture d’assurance.'),
    EtapeTba('Numériser la fiche reçue', ecran: 'm1-documents'),
    EtapeTba('Relever les constantes', ecran: 'm1-constantes'),
    EtapeTba('Le soignant reçoit', poste: 'Consultation'),
    EtapeTba('Renvoyer la contre-référence au centre d’origine',
        ecran: 'm1-contre-reference', detail: 'Elle dit ce qu’il est advenu du patient — c’est ce que le centre attend.'),
  ]),
  ParcoursTba('File d’attente et écran d’appel', 'list-ordered', 'Gérer la file', 'L’ordre d’arrivée gouverne, sauf urgence.', [
    EtapeTba('Inscrire et appeler les patients',
        ecran: 'm2-file-attente', detail: 'Le rang est calculé : priorité d’abord, heure d’arrivée ensuite. Il ne se saisit pas.'),
    EtapeTba('Afficher l’écran d’appel en salle d’attente', ecran: 'm2-affichage', detail: 'Numéros seuls — jamais le nom ni le motif du patient.'),
  ]),
  ParcoursTba('Sortie d’hospitalisation', 'log-out', 'Préparer la sortie', 'Le séjour est terminé, le patient rentre chez lui.', [
    EtapeTba('Vérifier que le solde est apuré', ecran: 'm8-reliquats', detail: 'RG-06 — aucune sortie tant qu’un reliquat subsiste.'),
    EtapeTba('Établir la fiche de sortie', ecran: 'm3-sorties', detail: 'RG-07 — signature du patient, de l’infirmier et constat du gardien.'),
    EtapeTba('Remettre le traitement de sortie', poste: 'Pharmacie'),
    EtapeTba('Programmer le contrôle', ecran: 'm2-rendezvous'),
  ]),
  ParcoursTba('Sortie contre avis médical', 'triangle-alert', 'Enregistrer la sortie', 'Le patient part malgré l’avis du médecin.', [
    EtapeTba('Recueillir la décharge de responsabilité',
        ecran: 'm3-sortie-avis-medical', detail: 'RG-08 — le motif est obligatoire, l’avis du Procureur consigné le cas échéant.'),
    EtapeTba('Faire signer le patient ou son accompagnant', ecran: 'm3-sortie-avis-medical'),
    EtapeTba('Régulariser le solde', ecran: 'm8-reliquats', detail: 'La sortie contre avis n’efface pas la dette.'),
  ]),
  ParcoursTba('Registre des appels', 'phone-call', 'Ouvrir le registre', 'Appels entrants et sortants du standard.', [
    EtapeTba('Consigner l’appel', ecran: 'm2-registre-appels', detail: 'Objet, interlocuteur, suite donnée.'),
    EtapeTba('Prendre le rendez-vous si l’appel le demande', ecran: 'm2-rendezvous'),
    EtapeTba('Appeler l’ambulance si l’appel est une urgence', ecran: 'm13-repertoire-ambulances'),
  ]),
  ParcoursTba('Visites aux hospitalisés', 'users-round', 'Enregistrer une visite', 'Les proches se présentent pour un patient hospitalisé.', [
    EtapeTba('Vérifier les heures de visite et enregistrer', ecran: 'm3-visites-patients'),
    EtapeTba('Orienter vers la chambre', ecran: 'm3-plan-lits'),
  ]),
  ParcoursTba('Annuaire des ambulances', 'ambulance', 'Consulter l’annuaire', 'Une évacuation est nécessaire.', [
    EtapeTba('Appeler un moyen disponible', ecran: 'm13-repertoire-ambulances', detail: 'Les disponibles remontent en tête ; le numéro est cliquable.'),
    EtapeTba('Établir la fiche de référence sortante',
        ecran: 'm1-reference', detail: 'Elle part avec le patient et porte ses constantes et ses traitements reçus.'),
    EtapeTba('Consigner l’intervention', ecran: 'm13-ambulance', poste: 'Ambulance'),
  ]),
  ParcoursTba('Certificats et attestations', 'stamp', 'Délivrer une pièce', 'Le patient réclame un certificat.', [
    EtapeTba('Délivrer la pièce', ecran: 'm1-pieces', detail: 'Numérotée par sigle et par année. Les certificats ne sont couverts que par SOS.'),
    EtapeTba('Encaisser', poste: 'Caisse'),
  ]),
];
