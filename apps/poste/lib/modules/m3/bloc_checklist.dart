import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show bandeauLectureSeule;
import 'bloc_commun.dart';
import 'bloc_registre.dart';

/// `m3-bloc-checklist` — « Check-listes du bloc » : les vérifications avant l'incision (entrée) et avant la sortie de salle (sortie).
///
/// DEUX listes SÉPARÉES, à deux moments distincts : les fondre ferait cocher après l'intervention ce qui devait l'être avant. Les points ont été
/// ARRÊTÉS par les praticiens du bloc le 01/09/2026 (validation écrite) ; la provenance reste dite. Une check-liste INCOMPLÈTE est SIGNALÉE, jamais
/// refusée : refuser l'enregistrement pousserait à tout cocher pour pouvoir avancer.
///
/// Écart E421 : la commande « Modifier » de chaque ligne est absente — la maquette la déclare sans aucun champ (`K.actionsLigne(col, null, …)`) et elle
/// lève une erreur au clic ; une commande qui ne mène nulle part promet une porte fermée.
class EcranChecklistBloc extends StatelessWidget with EcranMaquette {
  const EcranChecklistBloc({super.key});

  @override
  String get titre => 'Check-listes du bloc';

  @override
  String get description => 'Vérifications avant l’incision (entrée) et avant la sortie de salle (sortie).';

  @override
  String get regle =>
      'Deux listes séparées, à deux moments distincts : les fondre ferait cocher après l’intervention ce qui devait l’être avant. Les items proposés ne viennent d’aucun document remis par la clinique — proposés à ce titre, puis arrêtés par les praticiens du bloc le 01/09/2026 (validation écrite). Ils restent administrables.';

  static Widget detail(BuildContext ctx, Fiche r) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', r['reference']),
          ('Moment', r['moment'] == 'entree' ? 'Entrée' : 'Sortie'),
          ('Date et heure', dateHeureBloc(r['dateHeure'])),
          ('Patient', r['patient']),
          ('Responsable', r['responsable']),
        ]),
        sectionBloc(
            'Points vérifiés',
            MiniTableauSigh(colonnes: [
              ColonneMini('Point', (l) => '${l['label']}'),
              ColonneMini('Vérifié', (l) => l['coche'] == true ? 'Oui' : 'NON'),
            ], lignes: [
              for (final it in (r['items'] as List? ?? const [])) (it as Map).cast<String, Object?>()
            ])),
      ]);

  /// `remplir(moment, sousTitre, items)` : la modale de la check-liste, un point coché par case.
  static void remplir(BuildContext ctx, String moment, String sousTitre, List<String> items) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final defs = [
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient',
          type: TypeChamp.select,
          requis: true,
          options: optionsPatientsBloc(m)),
      ChampDef(
          nom: 'responsableId',
          libelle: 'Responsable de la vérification',
          type: TypeChamp.select,
          requis: true,
          options: optionsSoignantsBloc(m)),
      ChampDef.section(sousTitre),
      for (final (i, l) in items.indexed) ChampDef(nom: 'it$i', libelle: l, type: TypeChamp.case_),
    ];
    final ctl = ControleurFormulaire(defs, const {});
    afficherModale<void>(ctx,
        titre: 'Check-liste ${moment == 'entree' ? 'd’entrée' : 'de sortie'}',
        sousTitre: '$sousTitre — cocher chaque point vérifié.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final pt = patientParCodeBloc(m, v['patientCode']);
                    final l = blocLignesChecklist(items, v);
                    final col = m.collection('checklistsBloc');
                    final r = col.inserer({
                      'statut': 'actif',
                      'reference': blocReferenceSuivante('CKL-', 4, col.toutes),
                      'moment': moment,
                      'dateHeure': c.aujourdhui.toUtc().toIso8601String(),
                      'patientId': pt?['id'],
                      'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : v['patientCode'],
                      'responsableId': v['responsableId'],
                      'responsable': nomSoignantBloc(m, v['responsableId']),
                      'items': l.items,
                      'coches': l.coches,
                      'total': l.total,
                    }, prefixe: 'CKL');
                    fermer();
                    // Une check-liste incomplète n'est pas refusée — elle est SIGNALÉE.
                    final msg = blocMessageChecklist(l.coches, l.total);
                    ToastsSigh.afficher(ctx, msg.message,
                        type: msg.complete ? TypeToast.succes : TypeToast.attention,
                        detail: '${r.fiche['reference']}',
                        annuler: r.annuler,
                        messageAnnulation: 'Check-liste annulée — la fiche est archivée.');
                  }),
            ]);
  }

  Widget _panneau(BuildContext context, ContexteEcran c, String moment, String sousTitre, List<String> items) {
    final col = c.magasin.collection('checklistsBloc');
    return RegistreBloc(
      collection: col,
      entite: 'Check-liste',
      prefixeId: 'CKL',
      modifiable: false,
      messageVide: 'Aucune check-liste ${moment == 'entree' ? 'd’entrée' : 'de sortie'} enregistrée.',
      lignes: (a) =>
          trierPar([for (final r in a) if (r['moment'] == moment) r], (r) => r['dateHeure']).reversed.toList(),
      detail: detail,
      titreDetail: (r) => '${r['reference']}',
      actionsBarre: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Remplir la check-liste',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => remplir(context, moment, sousTitre, items)),
      ],
      colonnes: [
        const ColonneTableau(cle: 'reference', libelle: 'Référence'),
        ColonneTableau(
            cle: 'dateHeure',
            libelle: 'Date et heure',
            texte: (r) => dateHeureBloc(r['dateHeure']),
            valeur: (r) => '${r['dateHeure'] ?? ''}'),
        const ColonneTableau(cle: 'patient', libelle: 'Patient'),
        const ColonneTableau(cle: 'responsable', libelle: 'Responsable'),
        ColonneTableau(
            cle: 'coches',
            libelle: 'Vérifié',
            texte: (r) => '${r['coches']} / ${r['total']}',
            rendu: (_, r) => BadgeSigh('${r['coches']} / ${r['total']}',
                ton: r['coches'] == r['total'] ? TonSigh.succes : TonSigh.attention)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('checklistsBloc');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final k = blocKpisChecklist(rows);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bandeauLectureSeule(c),
          kpisBloc([
            KpiSigh(libelle: 'Check-listes remplies', valeur: nombre(k.total), icone: LucideIcons.listChecks),
            KpiSigh(libelle: 'Entrée', valeur: nombre(k.entree), icone: LucideIcons.logIn, ton: TonSigh.info),
            KpiSigh(libelle: 'Sortie', valeur: nombre(k.sortie), icone: LucideIcons.logOut, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Incomplètes',
                valeur: nombre(k.incompletes),
                icone: LucideIcons.triangleAlert,
                ton: k.incompletes > 0 ? TonSigh.attention : TonSigh.succes),
          ]),
          Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: NoteSigh(
                  'Check-listes arrêtées par les praticiens du bloc le ${dateBloc(blocChecklistArreteLe)} (validation écrite). Proposées à l’origine faute de document remis — la provenance reste dite.',
                  icone: LucideIcons.circleCheck)),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'entree',
                libelle: 'Check-liste d’entrée',
                compte: k.entree,
                construire: (ctx) => _panneau(ctx, c, 'entree', 'Avant l’incision', blocChecklistEntree)),
            OngletDef(
                id: 'sortie',
                libelle: 'Check-liste de sortie',
                compte: k.sortie,
                construire: (ctx) => _panneau(ctx, c, 'sortie', 'Avant la sortie de salle', blocChecklistSortie)),
          ]),
        ]);
      },
    );
  }
}
