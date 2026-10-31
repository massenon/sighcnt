import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';

/// Ce que partagent les huit écrans de M13 (administration & ambulance) : indicateurs, cellules, saisie en modale et archivage annulable des tableaux
/// construits à la main (`K.creer` / `K.actionsLigne` de la maquette). Les règles sont dans `packages/domaine/lib/src/administration`.

IconData admIcone(String nom) => switch (nom) {
      'mail' => LucideIcons.mail,
      'mail-open' => LucideIcons.mailOpen,
      'send' => LucideIcons.send,
      'inbox' => LucideIcons.inbox,
      'users' => LucideIcons.users,
      'calendar-clock' => LucideIcons.calendarClock,
      'file-clock' => LucideIcons.fileClock,
      'user-check' => LucideIcons.userCheck,
      'calendar-heart' => LucideIcons.calendarHeart,
      'bell' => LucideIcons.bell,
      'layers' => LucideIcons.layers,
      'list-checks' => LucideIcons.listChecks,
      'check-circle-2' => LucideIcons.circleCheck,
      'circle-check' => LucideIcons.circleCheck,
      'loader' => LucideIcons.loader,
      'file-text' => LucideIcons.fileText,
      'settings-2' => LucideIcons.settings2,
      'calendar-check' => LucideIcons.calendarCheck,
      'users-round' => LucideIcons.usersRound,
      'ambulance' => LucideIcons.ambulance,
      'calendar' => LucideIcons.calendar,
      'route' => LucideIcons.route,
      'wallet' => LucideIcons.wallet,
      'phone-off' => LucideIcons.phoneOff,
      'clock-alert' => LucideIcons.clockAlert,
      'wrench' => LucideIcons.wrench,
      'triangle-alert' => LucideIcons.triangleAlert,
      'circle-help' => LucideIcons.circleQuestionMark,
      _ => LucideIcons.info,
    };

/// L'indicateur du domaine devient un `KpiSigh`.
KpiSigh admKpi(AdmKpi k) => KpiSigh(libelle: k.libelle, valeur: k.valeur, icone: admIcone(k.icone), ton: matTon(k.ton), indice: k.indice);

Widget admKpis(List<AdmKpi> kpis) => KpiGrilleSigh(kpis: [for (final k in kpis) admKpi(k)]);

Widget admBadge(String texte, String ton) => BadgeSigh(texte, ton: matTon(ton));

/// Les agents actifs triés par nom, « NOM Prénom — poste » (`optionsAgents()` de la maquette).
List<OptionChamp> admOptionsAgents(Magasin m) => [
      for (final e in trierPar(m.collection('personnel').actives, (e) => e['nomComplet'])) OptionChamp('${e['nomComplet']}', '${e['nomComplet']} — ${e['poste']}')
    ];

List<OptionChamp> admOptions(Iterable<String> l) => [for (final o in l) OptionChamp(o)];

/// Un champ « heure » (`type="time"`) : le kit n'en a pas, texte `hh:mm` contrôlé (écart E422).
ChampDef admChampHeure(String nom, String libelle, {bool requis = true}) => ChampDef(
    nom: nom,
    libelle: libelle,
    requis: requis,
    indicatif: 'hh:mm',
    valider: (v, _) {
      final t = '$v'.trim();
      if (t.isEmpty) return null;
      return RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(t) ? null : 'Heure attendue au format HH:MM.';
    });

/// `Number(v)` d'une saisie : vide → absent.
num? admNombre(Object? v) {
  if (v is num) return v;
  final t = '${v ?? ''}'.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return num.tryParse(t);
}

Fiche admSansNuls(Fiche f) => matSansNuls(f);

/// La saisie d'une fiche en modale (`K.creer` / `modifier` de la maquette) : champs obligatoires contrôlés, refus nommé de l'appelant, annulation visible.
/// [fiche] reçoit les valeurs saisies et la fiche existante (`transform(v, record)`).
void admSaisir(BuildContext ctx,
    {required CollectionMagasin col,
    required List<ChampDef> champs,
    required Fiche Function(Map<String, Object?> saisie, Fiche? existante) fiche,
    Fiche? existante,
    required String titreCreation,
    required String entite,
    Map<String, Object?> initiales = const {},
    String libelleCreer = 'Créer',
    TailleModale taille = TailleModale.lg,
    String prefixeId = 'ID',
    String? Function(Fiche)? detailToast,
    void Function(Fiche creee)? apres}) {
  final c = ContexteEcran.of(ctx);
  final ctl = ControleurFormulaire(champs, existante != null ? {for (final e in existante.entries) e.key: e.value is num ? '${e.value}' : e.value} : initiales);
  afficherModale<void>(ctx,
      titre: existante == null ? titreCreation : 'Modifier l’enregistrement',
      sousTitre: existante == null ? 'Les champs marqués d’un astérisque sont obligatoires.' : '${existante['reference'] ?? existante['id']}',
      taille: taille,
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: existante == null ? libelleCreer : 'Enregistrer',
                icone: existante == null ? LucideIcons.plus : LucideIcons.save,
                onPressed: () {
                  final saisie = ctl.valider();
                  if (saisie == null) {
                    ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                    return;
                  }
                  final f = fiche(saisie, existante);
                  fermer();
                  if (existante == null) {
                    final r = col.inserer({'statut': 'actif', ...f, '_creePar': c.utilisateur, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: prefixeId);
                    ToastsSigh.afficher(ctx, '$entite créé.', type: TypeToast.succes, detail: detailToast?.call(r.fiche), annuler: r.annuler);
                    apres?.call(r.fiche);
                  } else {
                    final annuler = col.mettreAJour(existante['id'], f);
                    ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                  }
                }),
          ]);
}

/// Archivage d'une ligne (`K.actionsLigne`) : MOTIF obligatoire, annulable, jamais de suppression (RG-14).
void admArchiver(BuildContext ctx, CollectionMagasin col, Fiche f) async {
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver cet enregistrement ?',
      message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
      libelleOk: 'Archiver',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  final annuler = col.archiver(f['id']);
  ToastsSigh.afficher(ctx, 'Enregistrement archivé.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
}

/// Les commandes d'une ligne de tableau construit à la main : Modifier (droit d'écrire) puis Archiver (droit d'annuler) — ABSENTES sans le droit.
List<Widget> admActionsLigne(BuildContext ctx, ContexteEcran c, CollectionMagasin col, Fiche f, {required void Function(Fiche) modifier, List<Widget> avant = const []}) => [
      ...avant,
      if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => modifier(f)),
      if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => admArchiver(ctx, col, f)),
    ];

Widget admLectureSeule(ContexteEcran c) => (!c.droit.editer && c.droit.voir)
    ? Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NoteSigh('Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.', ton: TonSigh.attention))
    : const SizedBox.shrink();
