import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Aides communes des écrans de FLUX de M6 (pharmacies, dispensation, étiquetage, reprise).
num n(Object? v) => nombreOuZero(v);
String m(Object? v) => money(v, avecDevise: false);
String dateDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Une cellule en police fixe (référence, code…), comme `font-mono text-xs`.
Widget cellMono(String texte,
        {double taille = 12, FontWeight poids = FontWeight.w400, Color couleur = JetonsShell.slate700}) =>
    Text(texte,
        style: TextStyle(fontFamily: 'LiberationMono', fontSize: taille, fontWeight: poids, color: couleur));

/// Applique à `taches` ce que l'alerte de stock a décidé : tâches de réapprovisionnement créées ou mises à jour (jamais de doublon).
void appliquerAlertes(Magasin magasin, ResultatAlertes r) {
  final col = magasin.collection('taches');
  for (final t in r.creees) {
    col.inserer(t, prefixe: 'T');
  }
  for (final x in r.miseAJour) {
    col.mettreAJour(x.id, x.patch);
  }
}

/// Les produits ACTIFS indexés par identifiant (la forme que lit `alerterStock`).
Map<Object?, Map<String, Object?>> produitsParId(Magasin magasin) =>
    {for (final p in magasin.collection('produits').actives) p['id']: p};

/// Modale de saisie générique (`K.creer` / `K.modifier` / `saisirValorisation` de la maquette) : un formulaire dans une modale, deux boutons.
/// Un formulaire en erreur dit « Le formulaire comporte des erreurs. » et reste ouvert ; sinon [surValider] reçoit les valeurs (les champs numériques
/// sont déjà des nombres, comme ceux de `U.form`).
Future<void> modaleSaisie(
  BuildContext ecran, {
  required String titre,
  String? sousTitre,
  required List<ChampDef> champs,
  Map<String, Object?> initial = const {},
  required String libelleOk,
  required IconData icone,
  required bool Function(Map<String, Object?> valeurs) surValider,
  TailleModale taille = TailleModale.lg,
  Widget? entete,
}) async {
  // Les champs numériques se saisissent en texte : une valeur déjà numérique est présentée sans « .0 ».
  final depart = {
    ...initial,
    for (final c in champs)
      if (c.type == TypeChamp.nombre && initial[c.nom] is num)
        c.nom: (initial[c.nom] as num) == (initial[c.nom] as num).truncate()
            ? '${(initial[c.nom] as num).truncate()}'
            : '${initial[c.nom]}',
  };
  final ctl = ControleurFormulaire(champs, depart);
  await afficherModale<void>(ecran,
      titre: titre,
      sousTitre: sousTitre,
      taille: taille,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (entete != null) ...[entete, const SizedBox(height: 12)],
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: libelleOk,
                icone: icone,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                    return;
                  }
                  for (final c in champs) {
                    if (c.type == TypeChamp.nombre && v.containsKey(c.nom)) v[c.nom] = nombreOuZero(v[c.nom]);
                  }
                  if (surValider(v)) fermer();
                }),
          ]);
  ctl.dispose();
}

/// `U.confirm({requireMotif})` tel que la maquette le tient : le motif est DEMANDÉ (« consigné dans le journal d'audit ») mais un motif VIDE est accepté
/// (écart E47, porté fidèlement). Renvoie `null` si l'agent renonce, sinon le motif saisi (éventuellement vide).
Future<String?> confirmerArchivage(BuildContext ecran) async {
  final t = TextEditingController();
  final r = await afficherModale<String?>(ecran,
      titre: 'Archiver cet enregistrement ?',
      taille: TailleModale.sm,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
            style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
        const SizedBox(height: 12),
        const LibelleChamp('Motif (consigné dans le journal d’audit)'),
        TextField(
            key: const Key('kit:motif-archivage'),
            controller: t,
            minLines: 2,
            maxLines: 4,
            style: styleSaisie,
            decoration: decorationChamp(indicatif: 'Préciser le motif…')),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Archiver',
                variante: VarianteBouton.danger,
                onPressed: () => Navigator.of(ecran, rootNavigator: true).pop(t.text)),
          ]);
  t.dispose();
  return r;
}

/// `K.actionsLigne` : consulter (facultatif) / modifier / archiver sur une fiche d'une collection, selon les droits DE L'ÉCRAN — une commande interdite
/// est ABSENTE. Rend les boutons de la ligne.
List<Widget> actionsFiche(
  BuildContext ctx, {
  required CollectionMagasin collection,
  required Fiche fiche,
  required List<ChampDef> Function(Fiche) champs,
  bool archivable = true,
  Map<String, Object?> Function(Map<String, Object?>)? transformer,
}) {
  final c = ContexteEcran.of(ctx);
  return [
    if (c.droit.editer)
      BoutonIcone(
          icone: LucideIcons.pencil,
          libelle: 'Modifier',
          onPressed: () => modaleSaisie(ctx,
                  titre: 'Modifier l’enregistrement',
                  sousTitre: '${fiche['reference'] ?? fiche['numero'] ?? fiche['code'] ?? fiche['id']}',
                  champs: champs(fiche),
                  initial: fiche,
                  libelleOk: 'Enregistrer',
                  icone: LucideIcons.save,
                  surValider: (v) {
                    final annuler = collection.mettreAJour(fiche['id'], transformer != null ? transformer(v) : v);
                    ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                    return true;
                  })),
    if (archivable && c.droit.annuler)
      BoutonIcone(
          icone: LucideIcons.archive,
          libelle: 'Archiver',
          onPressed: () async {
            final motif = await confirmerArchivage(ctx);
            if (motif == null || !ctx.mounted) return;
            final annuler = collection.archiver(fiche['id']);
            if (motif.isNotEmpty) collection.mettreAJour(fiche['id'], {'_motifArchivage': motif});
            ToastsSigh.afficher(ctx, 'Enregistrement archivé.',
                type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
          }),
  ];
}

/// `K.source` : la pièce dont l'écran tire ses chiffres.
class SourceFlux extends StatelessWidget {
  const SourceFlux(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
        const SizedBox(width: 6),
        Flexible(
            child: Text('Source : $texte',
                style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
      ]));
}
