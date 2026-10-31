import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';

/// Ce que partagent les dix écrans de configuration de CFG : indicateurs, tableau adossé à une collection (`K.creer` + `K.actionsLigne` de la maquette),
/// saisie en modale, archivage annulable (RG-14). Les RÈGLES sont dans `packages/domaine/lib/src/configuration/cfa_regles.dart`, rejouées sur les
/// vecteurs de la maquette ; ces fichiers ne font que les mettre en page.

const cfaSignDa = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');
const cfaSignDm = Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko');

IconData cfaIcone(String nom) => switch (nom) {
      'layers' => LucideIcons.layers,
      'network' => LucideIcons.network,
      'users-round' => LucideIcons.usersRound,
      'shield' => LucideIcons.shield,
      'pill' => LucideIcons.pill,
      'flask-conical' => LucideIcons.flaskConical,
      'stethoscope' => LucideIcons.stethoscope,
      'help-circle' => LucideIcons.circleQuestionMark,
      'list-ordered' => LucideIcons.listOrdered,
      'shield-off' => LucideIcons.shieldOff,
      'shield-alert' => LucideIcons.shieldAlert,
      'triangle-alert' => LucideIcons.triangleAlert,
      'stamp' => LucideIcons.stamp,
      'tag' => LucideIcons.tag,
      'file-check' => LucideIcons.fileCheck,
      'file-badge' => LucideIcons.fileBadge,
      'list' => LucideIcons.list,
      'calendar-check' => LucideIcons.calendarCheck,
      'receipt-text' => LucideIcons.receiptText,
      'archive' => LucideIcons.archive,
      'scan-line' => LucideIcons.scanLine,
      'list-checks' => LucideIcons.listChecks,
      'eye-off' => LucideIcons.eyeOff,
      'chevrons-up-down' => LucideIcons.chevronsUpDown,
      'message-square' => LucideIcons.messageSquare,
      'check-check' => LucideIcons.checkCheck,
      'bell-ring' => LucideIcons.bellRing,
      'send' => LucideIcons.send,
      'hash' => LucideIcons.hash,
      'scale' => LucideIcons.scale,
      'printer' => LucideIcons.printer,
      _ => LucideIcons.info,
    };

TonSigh cfaTon(String t) => matTon(t);

KpiSigh cfaKpi(CfaKpi k) => KpiSigh(libelle: k.libelle, valeur: k.valeur, icone: cfaIcone(k.icone), ton: cfaTon(k.ton), indice: k.indice);

Widget cfaKpis(List<CfaKpi> kpis) => KpiGrilleSigh(kpis: [for (final k in kpis) cfaKpi(k)]);

/// `K.note` : tons du domaine (`succes`, `attention`, `danger`, `info`).
TonSigh cfaTonNote(String t) => switch (t) {
      'succes' => TonSigh.succes,
      'attention' => TonSigh.attention,
      'danger' => TonSigh.danger,
      _ => TonSigh.info,
    };

/// Une pile de composants séparés de 12 px (`space-y-3`) ou 16 px (`space-y-4`).
Widget cfaPile(List<Widget> enfants, {double espace = 16}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < enfants.length; i++) ...[if (i > 0) SizedBox(height: espace), enfants[i]]
    ]);

/// Le code en police fixe (`font-mono text-xs`).
Widget cfaCode(Object? t) => Text('${t ?? ''}', style: const TextStyle(fontFamily: matPoliceMono, fontSize: 12, height: 16 / 12, color: JetonsShell.slate900));

Widget cfaGras(String t, {Color couleur = JetonsShell.slate800}) =>
    Text(t, style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: couleur));

Widget cfaDiscret(String t) => Text(t, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400));

/// Le bandeau de lecture seule : le profil consulte sans pouvoir écrire, et le dit.
Widget cfaLectureSeule(ContexteEcran c) => (!c.droit.editer && c.droit.voir)
    ? Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NoteSigh('Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.', ton: TonSigh.attention))
    : const SizedBox.shrink();

/// `K.source` : la mention de provenance au pied d'un tableau.
Widget cfaSource(String t) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
      const SizedBox(width: 6),
      Flexible(child: Text(t, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400))),
    ]));

/// Une valeur de fiche affichée, « — » si vide.
String cfaOuTiret(Object? v) => cfaVrai(v) ? '$v' : '—';

/// Une saisie en modale — création ou modification — avec le contrôle métier [avant] de l'appelant (il refuse EN LE DISANT, rien n'est écrit).
/// [fiche] reçoit la saisie et la fiche existante : c'est le `transform` de `K.creer` / `K.actionsLigne`.
void cfaSaisir(BuildContext ctx,
    {required CollectionMagasin col,
    required List<ChampDef> champs,
    required Fiche Function(Map<String, Object?> saisie, Fiche? existante) fiche,
    Fiche? existante,
    required String titreCreation,
    required String entite,
    Map<String, Object?> initiales = const {},
    TailleModale taille = TailleModale.lg,
    String prefixeId = 'ID',
    bool Function(BuildContext ctx, Map<String, Object?> saisie, Fiche? existante)? avant,
    void Function(Fiche creee)? apres}) {
  final c = ContexteEcran.of(ctx);
  final ctl = ControleurFormulaire(champs, existante != null ? {for (final e in existante.entries) e.key: e.value is num ? '${e.value}' : e.value} : initiales);
  afficherModale<void>(ctx,
      titre: existante == null ? titreCreation : 'Modifier l’enregistrement',
      sousTitre: existante == null
          ? 'Les champs marqués d’un astérisque sont obligatoires.'
          : '${existante['reference'] ?? existante['numero'] ?? existante['code'] ?? existante['id']}',
      taille: taille,
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: existante == null ? 'Créer' : 'Enregistrer',
                icone: existante == null ? LucideIcons.plus : LucideIcons.save,
                onPressed: () {
                  final saisie = ctl.valider();
                  if (saisie == null) {
                    ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                    return;
                  }
                  if (avant != null && !avant(ctx, saisie, existante)) return;
                  final f = fiche(saisie, existante);
                  fermer();
                  if (existante == null) {
                    final r = col.inserer({'statut': 'actif', ...f, '_creePar': c.utilisateur, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: prefixeId);
                    ToastsSigh.afficher(ctx, '$entite créé.',
                        type: TypeToast.succes,
                        detail: cfaVrai(r.fiche['libelle']) ? '${r.fiche['libelle']}' : cfaVrai(r.fiche['designation']) ? '${r.fiche['designation']}' : cfaVrai(r.fiche['code']) ? '${r.fiche['code']}' : null,
                        annuler: r.annuler,
                        messageAnnulation: 'Création annulée — la fiche est archivée.');
                    apres?.call(r.fiche);
                  } else {
                    final annuler = col.mettreAJour(existante['id'], f);
                    ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                  }
                }),
          ]);
}

/// Archivage d'une ligne (`K.actionsLigne`) : MOTIF obligatoire, annulable, jamais de suppression (RG-14).
void cfaArchiver(BuildContext ctx, CollectionMagasin col, Fiche f) async {
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver cet enregistrement ?',
      message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
      libelleOk: 'Archiver',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  final annuler = col.archiver(f['id']);
  ToastsSigh.afficher(ctx, 'Enregistrement archivé.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
}

/// Un tableau adossé à une collection construit à la main : les commandes de `K.creer` et `K.actionsLigne`. Une commande dont le droit manque est
/// ABSENTE (et non grisée), et le bandeau de lecture seule le dit.
class CfaTableau extends StatelessWidget {
  const CfaTableau({
    super.key,
    required this.collection,
    required this.colonnes,
    required this.champs,
    required this.entite,
    this.libelleNouveau = 'Nouveau',
    this.titreCreation = 'Nouvel enregistrement',
    this.prefixeId = 'ID',
    this.titre,
    this.lignes,
    this.fiche,
    this.avant,
    this.detail,
    this.titreDetail,
    this.sousTitreDetail,
    this.valeursInitiales,
    this.filtres = const [],
    this.actions = const [],
    this.actionsLigneSup,
    this.taillePage = 12,
    this.triInitial,
    this.sensInitial = 'asc',
    this.nomExport = 'export',
    this.messageVide = 'Aucun enregistrement.',
    this.archivable = true,
    this.taille = TailleModale.lg,
    this.creer = true,
    this.apres,
    this.largeurTiroir = 672,
  });

  final String collection;
  final List<ColonneTableau> colonnes;
  final List<ChampDef> Function(Fiche? existante) champs;
  final String entite;
  final String libelleNouveau;
  final String titreCreation;
  final String prefixeId;
  final String? titre;

  /// Les lignes affichées (par défaut les fiches actives de la collection).
  final List<Fiche> Function(List<Fiche> actives)? lignes;
  final Fiche Function(Map<String, Object?> saisie, Fiche? existante)? fiche;
  final bool Function(BuildContext, Map<String, Object?>, Fiche?)? avant;
  final Widget Function(BuildContext, Fiche)? detail;
  final String Function(Fiche)? titreDetail;
  final String? Function(Fiche)? sousTitreDetail;
  final Map<String, Object?> Function()? valeursInitiales;
  final List<FiltreTableau> filtres;
  final List<Widget> actions;
  final List<Widget> Function(BuildContext, Fiche)? actionsLigneSup;
  final int taillePage;
  final String? triInitial;
  final String sensInitial;
  final String nomExport;
  final String messageVide;
  final bool archivable;
  final TailleModale taille;
  final bool creer;
  final void Function(Fiche)? apres;
  final double largeurTiroir;

  Fiche _fiche(Map<String, Object?> s, Fiche? e) => fiche != null ? fiche!(s, e) : {...s};

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(collection);
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = lignes != null ? lignes!(col.actives) : col.actives;
          return TableauSigh(
            titre: titre,
            lignes: rows,
            colonnes: colonnes,
            filtres: filtres,
            taillePage: taillePage,
            triInitial: triInitial,
            sensInitial: sensInitial,
            nomExport: nomExport,
            messageVide: messageVide,
            actions: [
              if (creer && c.droit.editer)
                BoutonSigh(
                    libelle: libelleNouveau,
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => cfaSaisir(context,
                        col: col,
                        champs: champs(null),
                        fiche: _fiche,
                        titreCreation: titreCreation,
                        entite: entite,
                        initiales: valeursInitiales?.call() ?? const {},
                        taille: taille,
                        prefixeId: prefixeId,
                        avant: avant,
                        apres: apres)),
              ...actions,
            ],
            actionsLigne: (ctx2, f) => [
              if (detail != null)
                BoutonIcone(
                    icone: LucideIcons.eye,
                    libelle: 'Consulter',
                    onPressed: () => afficherTiroir<void>(ctx2,
                        titre: titreDetail != null ? titreDetail!(f) : '${f['reference'] ?? f['numero'] ?? f['code'] ?? 'Détail'}',
                        sousTitre: sousTitreDetail?.call(f),
                        largeurMax: largeurTiroir,
                        corps: detail!(ctx2, f))),
              ...?actionsLigneSup?.call(ctx2, f),
              if (c.droit.editer)
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: 'Modifier',
                    onPressed: () => cfaSaisir(ctx2, col: col, champs: champs(f), fiche: _fiche, existante: f, titreCreation: titreCreation, entite: entite, taille: taille, avant: avant)),
              if (archivable && c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => cfaArchiver(ctx2, col, f)),
            ],
          );
        });
  }
}

/// La pièce A4 d'un état de CFG (la mise en page est celle de `P.etat`).
void cfaImprimer(BuildContext ctx,
        {required String titre,
        String? sousTitre,
        List<(String, String)> cartouche = const [],
        required List<BlocPiece> blocs,
        List<Signature> signatures = const []}) =>
    matImprimer(ctx, titre: titre, sousTitre: sousTitre, cartouche: cartouche, blocs: blocs, signatures: signatures);

String cfaMoney(Object? v, {bool devise = false}) => money(v, avecDevise: devise);

/// `D.SECTEURS_ACTIVITE` : un référentiel STATIQUE du jeu (liste de chaînes, pas de fiches).
List<String> cfaSecteursActivite(Magasin m) => [for (final s in (m.referentiels['secteursActivite'] as List? ?? const [])) '$s'];

/// Les valeurs distinctes d'une colonne, triées (`Object.keys(C.groupBy(rows, k)).sort()`).
List<String> cfaDistincts(Iterable<Fiche> rows, String cle) => ({for (final r in rows) '${r[cle]}'}.toList()..sort((a, b) => comparerNaturel(a, b)));
