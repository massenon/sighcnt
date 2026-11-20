import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tbb_commun.dart';

/// `dash-maternite` — le poste, pas la spécialité. La sage-femme de garde arrive avec trois questions : QUI est en travail, QUELS termes tombent cette
/// semaine, QUELLES grossesses sont à risque. Le premier regard est le travail en cours (un partogramme non clos est une femme dans la salle) ;
/// un terme DÉPASSÉ n'est pas une erreur de saisie, c'est la femme qu'il faut rappeler. Tout est CALCULÉ depuis les registres.
class EcranDashMaternite extends StatelessWidget with EcranMaquette {
  const EcranDashMaternite({super.key});

  @override
  String get titre => 'Tableau de bord — Maternité';

  @override
  String get description =>
      'Travail en cours, termes de la semaine, grossesses à risque, accouchements et nouveau-nés du mois.';

  static Widget _mono(String s) => Text(s,
      style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate700));

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['dossiersObstetricaux', 'partogrammes', 'accouchements', 'naissances'],
        construire: (c) {
          final auj = c.aujourdhui;
          final dossiers = lire(c, 'dossiersObstetricaux');
          final accouchements = lire(c, 'accouchements');
          final travaux = tbbTravauxEnCours(lire(c, 'partogrammes'));
          final termes = tbbTermesProches(dossiers, 15, auj).take(12).toList();
          final gar = tbbGrossessesARisque(dossiers).take(10).toList();
          final parType = tbbAccouchementsParType(accouchements, auj);
          final facteurs = tbbFacteursFrequents(dossiers);

          return TbbDisposition(
            releve: tbbMaternite(
                dossiers: dossiers,
                partogrammes: lire(c, 'partogrammes'),
                accouchements: accouchements,
                naissances: lire(c, 'naissances'),
                auj: auj),
            raccourcis: [
              raccourci('m4-dossier-obstetrical', 'folder-open', 'Dossier obstétrical', 'Le cahier de la parturiente'),
              raccourci('m4-partogramme', 'activity', 'Partogramme', 'Salle de travail'),
              raccourci('m4-accouchements', 'baby', 'Accouchement', 'Délivrance et issue'),
              raccourci('m4-cpon', 'stethoscope', 'CPoN', 'Suites de couches'),
            ],
            parcours: const [
              ParcoursDef('Ouvrir un dossier obstétrical', 'folder-open',
                  action: 'Dossier obstétrical', detail: 'Une femme se présente pour sa première consultation prénatale.', [
                EtapeDef('Vérifier ou créer le dossier patient', ecran: 'm1-patients'),
                EtapeDef('Ouvrir le dossier obstétrical',
                    ecran: 'm4-dossier-obstetrical', detail: 'Numéro repris du registre papier ; la date probable se déduit de la DDR.'),
                EtapeDef('Cocher les facteurs de surveillance',
                    ecran: 'm4-dossier-obstetrical', detail: 'C’est leur CUMUL qui classe à risque, jamais un facteur isolé.'),
                EtapeDef('Enregistrer la première CPN', ecran: 'm4-cpn'),
              ]),
              ParcoursDef('Suivre une CPN', 'clipboard-list',
                  action: 'CPN & carte maternelle', detail: 'La grille se remplit en COLONNES : une par venue, les mêmes lignes à chaque fois.', [
                EtapeDef('Relever l’état général et les examens', ecran: 'm4-cpn'),
                EtapeDef('Administrer le TPI / SP et le déparasitage', ecran: 'm4-cpn'),
                EtapeDef('Prescrire un bilan si nécessaire', ecran: 'm5-demandes', poste: 'Laboratoire'),
                EtapeDef('Fixer le rendez-vous et la classe des mères', ecran: 'm4-cpn'),
              ]),
              ParcoursDef('Conduire un accouchement', 'activity',
                  action: 'Partogramme', detail: 'De l’admission en salle de travail à la surveillance du deuxième jour.', [
                EtapeDef('Ouvrir le partogramme',
                    ecran: 'm4-partogramme', detail: 'Dilatation, descente en travers de doigts, chevauchement, liquide amniotique.'),
                EtapeDef('Enregistrer l’accouchement et la délivrance',
                    ecran: 'm4-accouchements', detail: 'Mode de délivrance, examen du placenta, issue mère et nouveau-né.'),
                EtapeDef('Renseigner le nouveau-né', ecran: 'm4-dossier-bebe', detail: 'PC, PT et Apgar aux trois temps sont OBLIGATOIRES.'),
                EtapeDef('Déclarer la naissance', ecran: 'm4-naissances'),
                EtapeDef('Établir la facture du séjour', poste: 'Caisse'),
              ]),
              ParcoursDef('Suivre les suites de couches', 'stethoscope',
                  action: 'CPoN', detail: 'Trois consultations post-natales, la première dans les 48 heures.', [
                EtapeDef('Enregistrer la CPoN', ecran: 'm4-cpon'),
                EtapeDef('Proposer une méthode de PF', ecran: 'm4-planification'),
                EtapeDef('Clore le dossier obstétrical', ecran: 'm4-dossier-obstetrical'),
              ]),
            ],
            sections: [
              // Le travail en cours — la seule chose qui n'attend pas.
              CarteSigh(
                titre: 'Travail en cours — salle d’accouchement',
                actions: [lienIcone('Partogrammes', 'activity', () => c.aller('m4-partogramme'))],
                sansRemplissage: travaux.isNotEmpty,
                child: travaux.isEmpty
                    ? videCarte('Aucun travail en cours.', 'activity')
                    : MiniTableauSigh(colonnes: [
                        ColonneMini('Parturiente', (p) => tbbCellulesTravail(p)[0]),
                        ColonneMini('Dossier', (p) => tbbCellulesTravail(p)[1], rendu: (p) => _mono(tbbCellulesTravail(p)[1])),
                        ColonneMini('G / P', (p) => tbbCellulesTravail(p)[2]),
                        ColonneMini('Début du travail', (p) => tbbCellulesTravail(p)[3]),
                        ColonneMini('Dilatation', (p) => tbbCellulesTravail(p)[4],
                            droite: true,
                            rendu: (p) => Text(tbbCellulesTravail(p)[4],
                                style: const TextStyle(
                                    color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
                        ColonneMini('Descente', (p) => tbbCellulesTravail(p)[5]),
                        ColonneMini('Accoucheur', (p) => tbbCellulesTravail(p)[6]),
                      ], lignes: travaux),
              ),
              // Les termes de la quinzaine, dépassés compris.
              CarteSigh(
                titre: 'Termes attendus — les quinze prochains jours',
                actions: [lienIcone('Dossiers', 'folder-open', () => c.aller('m4-dossier-obstetrical'))],
                sansRemplissage: termes.isNotEmpty,
                child: termes.isEmpty
                    ? videCarte('Aucun terme dans les quinze prochains jours.', 'calendar-clock')
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Padding(
                            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: NoteSigh(
                                'Un terme DÉPASSÉ n’est pas une erreur de saisie : c’est la femme qu’il faut rappeler. Le dossier reste « suivi » tant '
                                'que l’accouchement n’est pas enregistré.',
                                ton: TonSigh.attention,
                                icone: LucideIcons.phone)),
                        MiniTableauSigh(colonnes: [
                          ColonneMini('N° dossier', (d) => tbbCellulesTerme(d, auj)[0], rendu: (d) => _mono(tbbCellulesTerme(d, auj)[0])),
                          ColonneMini('Parturiente', (d) => tbbCellulesTerme(d, auj)[1]),
                          ColonneMini('Terme prévu', (d) => tbbCellulesTerme(d, auj)[2]),
                          ColonneMini('Échéance', (d) => tbbCellulesTerme(d, auj)[3],
                              droite: true,
                              rendu: (d) {
                                final e = tbbEcheanceTerme(d, auj);
                                return BadgeSigh(e.texte, ton: tonDe(e.ton));
                              }),
                          ColonneMini('Surveillance', (d) => tbbCellulesTerme(d, auj)[4], rendu: (d) {
                            final s = tbbSurveillanceDossier(d);
                            return BadgeSigh(s.texte, ton: tonDe(s.ton));
                          }),
                          ColonneMini('Sage-femme', (d) => tbbCellulesTerme(d, auj)[5]),
                          ColonneMini('Téléphone', (d) => tbbCellulesTerme(d, auj)[6]),
                        ], lignes: termes),
                      ]),
              ),
              CarteSigh(
                titre: 'Grossesses à risque suivies',
                sansRemplissage: gar.isNotEmpty,
                child: gar.isEmpty
                    ? videCarte('Aucune grossesse à risque en cours de suivi.', 'shield-check')
                    : MiniTableauSigh(colonnes: [
                        ColonneMini('N° dossier', (d) => tbbCellulesRisque(d)[0], rendu: (d) => _mono(tbbCellulesRisque(d)[0])),
                        ColonneMini('Parturiente', (d) => tbbCellulesRisque(d)[1]),
                        ColonneMini('Âge', (d) => tbbCellulesRisque(d)[2], droite: true),
                        ColonneMini('G / P', (d) => tbbCellulesRisque(d)[3]),
                        ColonneMini('Facteurs relevés', (d) => tbbCellulesRisque(d)[4]),
                      ], lignes: gar),
              ),
              CarteSigh(
                titre: 'Lecture du mois',
                child: deuxColonnes([
                  CarteSigh(
                      titre: 'Accouchements du mois par type',
                      child: parType.isEmpty
                          ? videCarte('Aucun accouchement ce mois.', 'baby')
                          : GraphiqueBarres(horizontal: true, etiquettes: [
                              for (final t in parType) t.$1
                            ], series: [
                              SerieGraphique('Accouchements', [for (final t in parType) t.$2])
                            ])),
                  CarteSigh(
                      titre: 'Facteurs de surveillance les plus fréquents',
                      child: facteurs.isEmpty
                          ? videCarte('Aucun facteur coché sur les dossiers ouverts.', 'check-circle-2')
                          : ClassementSigh(facteurs)),
                ]),
              ),
            ],
          );
        },
      );
}
