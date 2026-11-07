import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'surv_commun.dart';

/// `m3-administrations` — « Administration des traitements » : les administrations dues au service d'hospitalisation, à partir du DEUXIÈME passage.
/// La règle de relais vit dans le domaine (`hosSecteurAdministrateur`, `hosSoinsDuSecteur`, `hosAdministrer`) : le RANG du passage décide du secteur,
/// jamais l'organisation du service. Une prescription non réglée reste visible mais non exécutable ; un exécutant qui n'exécute pas est refusé en le nommant.
/// E368 : le message « Aucune administration due… » de la maquette n'est jamais affiché (clé `empty` au lieu de `emptyMessage`) — porté fidèlement.
class EcranAdministrations extends StatelessWidget with EcranMaquette {
  const EcranAdministrations({super.key});

  @override
  String get titre => 'Administration des traitements';

  @override
  String get description =>
      'Administrations dues au service d’hospitalisation, à partir du deuxième passage.';

  @override
  String get regle =>
      'La première administration d’un traitement hospitalier revient à la salle de soins ; les suivantes à l’hospitalisation. Un traitement ambulatoire ne passe jamais par ce poste. Une prescription non réglée reste visible mais non exécutable.';

  static const secteur = 'hospitalisation';

  /// Les lignes dues, à plat (une par ligne de prescription), prêtes pour le tableau.
  static List<Fiche> lignesDues(Magasin m) => [
        for (final d in hosSoinsDuSecteur(secteur, m.collection('prescriptions').actives,
            m.collection('administrations').actives))
          {
            'prescription': d.prescription,
            'ligneIndex': d.index,
            'reference': d.prescription['reference'],
            'patient': d.prescription['patient'],
            'patientCode': d.prescription['patientCode'],
            'libelle': d.ligne['libelle'],
            'rang': d.rang,
            'total': d.total,
            'motif': d.motif,
            'bloque': d.bloque,
          }
      ];

  static List<Fiche> faites(Magasin m) =>
      m.collection('administrations').actives.where((a) => a['secteur'] == secteur).toList();

  /// `PR.administrer` : le moteur du domaine rend un refus NOMMÉ ou la fiche à écrire ; la prescription se termine quand toutes ses lignes sont servies.
  static HosAdministration administrer(Magasin m, Fiche ligne, Map<String, Object?> v, DateTime maintenant) {
    final adm = m.collection('administrations');
    final pres = ligne['prescription'] as Fiche;
    final res = hosAdministrer(pres, adm.actives,
        soignants: soignantsActifs(m),
        ligneIndex: ligne['ligneIndex'] as int,
        secteur: secteur,
        executantId: '${v['executantId']}',
        observation: '${v['observation'] ?? ''}',
        dateHeure: maintenant,
        reference: referenceSuivante('ADM-', 5, adm.toutes));
    if (res.ok) {
      adm.inserer({'statut': 'actif', ...res.fiche!}, prefixe: 'ADM');
      if (res.termine) m.collection('prescriptions').mettreAJour(pres['id'], {'statut': 'termine'});
    }
    return res;
  }

  void _administrer(BuildContext ecran, ContexteEcran c, Fiche r) {
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'executantId',
          libelle: 'Exécutant',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          aide: 'Infirmiers et sages-femmes. Le médecin prescrit, il n’exécute pas les soins.',
          options: optionsSoignants(
              c.magasin, (x) => x['execute'] == true && ((x['secteurs'] as List?) ?? const []).contains(secteur))),
      const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ]);
    afficherModale<void>(ecran,
            titre: 'Administrer — ${r['libelle']}',
            sousTitre: '${r['patient']} — passage ${r['rang']} sur ${r['total']}',
            corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              NoteSigh('${r['motif']}', ton: TonSigh.info, icone: LucideIcons.route),
              const SizedBox(height: 12),
              FormulaireSigh(controleur: ctl),
            ]),
            pied: (fermer) => [
                  BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
                  BoutonSigh(
                      libelle: 'Confirmer l’administration',
                      icone: LucideIcons.check,
                      onPressed: () {
                        final v = ctl.valider();
                        if (v == null) {
                          ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                          return;
                        }
                        try {
                          final res = administrer(c.magasin, r, v, c.aujourdhui);
                          if (!res.ok) {
                            ToastsSigh.afficher(ecran, '${res.motif}', type: TypeToast.erreur);
                            return;
                          }
                          fermer();
                          ToastsSigh.afficher(ecran, 'Administration n° ${res.rang} enregistrée.',
                              type: TypeToast.succes, detail: '${r['libelle']} — ${r['patient']}');
                        } on HosErreur catch (e) {
                          ToastsSigh.afficher(ecran, e.message, type: TypeToast.erreur);
                        }
                      }),
                ])
        .whenComplete(ctl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final prescriptions = c.magasin.collection('prescriptions');
    final administrations = c.magasin.collection('administrations');
    return ListenableBuilder(
      listenable: Listenable.merge([prescriptions, administrations]),
      builder: (context, _) {
        final dues = lignesDues(c.magasin);
        final deja = faites(c.magasin);
        final patients = {for (final d in dues) (d['prescription'] as Fiche)['id']}.length;
        final bloquees = dues.where((d) => d['bloque'] == true).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Patients concernés', valeur: nombre(patients), icone: LucideIcons.users, ton: TonSigh.navy),
            KpiSigh(libelle: 'Administrations dues', valeur: nombre(dues.length), icone: LucideIcons.pill, ton: TonSigh.info),
            KpiSigh(libelle: 'Déjà administrées ici', valeur: nombre(deja.length), icone: LucideIcons.checkCheck, ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Bloquées faute de règlement',
                valeur: nombre(bloquees),
                icone: LucideIcons.lock,
                ton: bloquees > 0 ? TonSigh.attention : TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Ce poste ne voit pas les premières administrations : elles appartiennent à la salle de soins. C’est le relais décrit par la Direction — le rang du passage décide du secteur, et non l’inverse.',
              ton: TonSigh.info,
              icone: LucideIcons.route),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'dues',
                libelle: 'À administrer',
                compte: dues.length,
                construire: (ctx) => TableauSigh(
                      lignes: dues,
                      nomExport: 'administrations-dues',
                      colonnes: [
                        const ColonneTableau(cle: 'reference', libelle: 'Prescription'),
                        ColonneTableau(
                            cle: 'patient',
                            libelle: 'Patient',
                            texte: (r) => '${r['patient']} — ${r['patientCode']}'),
                        const ColonneTableau(cle: 'libelle', libelle: 'Acte ou produit'),
                        ColonneTableau(
                            cle: 'rang',
                            libelle: 'Passage',
                            texte: (r) => '${r['rang']} / ${r['total']}'),
                        ColonneTableau(
                            cle: 'motif',
                            libelle: 'Pourquoi ce poste',
                            texte: (r) => '${r['motif']}',
                            rendu: (_, r) => Text('${r['motif']}',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 16 / 12))),
                        ColonneTableau(
                            cle: 'bloque',
                            libelle: 'État',
                            texte: (r) => r['bloque'] == true ? 'Non réglée' : 'Exécutable',
                            rendu: (_, r) => r['bloque'] == true
                                ? const BadgeSigh('Non réglée', ton: TonSigh.attention)
                                : const BadgeSigh('Exécutable', ton: TonSigh.succes)),
                      ],
                      actionsLigne: (ctx, r) => [
                        if (r['bloque'] == true)
                          BoutonIcone(
                              icone: LucideIcons.lock,
                              libelle: 'Bloquée : la prescription n’est pas réglée',
                              onPressed: () => ToastsSigh.afficher(
                                  context, 'Administration bloquée — la prescription ${r['reference']} n’est pas réglée.',
                                  type: TypeToast.attention))
                        else if (c.droit.editer)
                          BoutonSigh(
                              libelle: 'Administrer',
                              icone: LucideIcons.check,
                              taille: TailleBouton.sm,
                              onPressed: () => _administrer(context, c, r)),
                      ],
                    )),
            OngletDef(
                id: 'faites',
                libelle: 'Historique',
                compte: deja.length,
                construire: (ctx) => TableauSigh(
                      lignes: trierPar(deja, (r) => r['dateHeure']).reversed.toList(),
                      nomExport: 'administrations',
                      colonnes: [
                        const ColonneTableau(cle: 'reference', libelle: 'Référence'),
                        ColonneTableau(
                            cle: 'dateHeure',
                            libelle: 'Date et heure',
                            texte: (r) => dateHeureTexte(r['dateHeure'])),
                        const ColonneTableau(cle: 'patient', libelle: 'Patient'),
                        const ColonneTableau(cle: 'libelle', libelle: 'Acte ou produit'),
                        ColonneTableau(
                            cle: 'rang',
                            libelle: 'Passage',
                            texte: (r) => '${r['rang']} / ${r['total']}'),
                        const ColonneTableau(cle: 'executant', libelle: 'Exécutant'),
                        ColonneTableau(
                            cle: 'observation',
                            libelle: 'Observation',
                            texte: (r) => vrai(r['observation']) ? '${r['observation']}' : '—'),
                      ],
                    )),
          ]),
        ]);
      },
    );
  }
}
