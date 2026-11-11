import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/verrou_secours_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../auth/acc_registre_sessions.dart';
import 'commun_m14.dart';

/// `m14-sessions` : « Sessions actives », connexions en cours, postes de travail, délai d'inactivité, et « Clôturer » qui CHANGE LE STATUT (retour de la
/// Direction du 01/11/2026).
///
/// Le registre `sessionsUtilisateur` tient une fiche par session : `active`, `suspendue` ou `cloturee`. « Clôturer » écrit la clôture sur la fiche (date, heure,
/// auteur, RG-12) par la règle du domaine (`secCloturerSession`) ; le poste visé retombe sur la connexion à son prochain geste. Une session clôturée ne
/// se rouvre pas et ne s'efface pas (RG-14) : elle reste au registre, filtrable. Clôturer SA PROPRE session demande une confirmation qui le dit, puis
/// déconnecte aussitôt.
///
/// Les douze premières fiches sont le jeu de DÉMONSTRATION (graine 3413), amorcées par l'écran comme la maquette. L'inactivité n'est relevée que pour elles :
/// le poste ne mesure pas l'activité de ses propres sessions, il pose le verrou.
class EcranSessions extends StatefulWidget with EcranMaquette {
  const EcranSessions({super.key});

  @override
  String get description =>
      'Connexions en cours, postes de travail et délai d’inactivité avant verrouillage.';

  @override
  String get regle =>
      'Le registre tient une fiche par session : active, suspendue ou clôturée. Une session ne se crée ni ne se modifie ici : elle se clôture (statut, date, heure et auteur écrits, RG-12). Une session clôturée ne se rouvre pas et ne s’efface pas (RG-14) ; le poste retombe sur la connexion à son prochain geste.';

  @override
  State<EcranSessions> createState() => _EtatSessions();
}

class _EtatSessions extends State<EcranSessions> {
  bool _amorce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    final c = ContexteEcran.of(context);
    RegistreSessions.de(c.magasin).amorcerDemonstration(c.magasin.collection('utilisateurs').actives, c.aujourdhui);
  }

  Future<void> _cloturer(BuildContext ctx, ContexteEcran c, Map<String, Object?> r) async {
    final reg = RegistreSessions.de(c.magasin);
    final id = '${r['id']}';
    final propre = reg.sessionCourante == id;
    final conf = secConfirmationCloture(nomComplet: '${r['nomComplet']}', poste: '${r['poste']}', propre: propre);
    final ok = await confirmerSigh(ctx, titre: conf.titre, message: conf.message, libelleOk: conf.libelleOk, dangereux: true);
    if (!ok || !ctx.mounted) return;
    final a = c.agent;
    final res = reg.cloturer(id,
        acteur: SecActeurSession(
            role: c.role, identifiant: a.identifiant.isEmpty ? c.role : a.identifiant, nom: a.nom.isEmpty ? c.role : a.nom, sessionId: reg.sessionCourante),
        droitEditer: c.droit.editer,
        maintenant: c.aujourdhui,
        confirmePropre: propre);
    if (!res.ok) {
      ToastsSigh.afficher(ctx, res.refus!.motif, type: TypeToast.erreur, detail: res.refus!.geste);
      return;
    }
    ToastsSigh.afficher(ctx, 'Session clôturée.', type: TypeToast.succes, detail: '${r['nomComplet']} (${r['poste']})');
    // Sa propre session : le poste retombe aussitôt sur la connexion.
    if (res.patch['cloturePropre'] == true) reg.surCloturePropre?.call();
  }

  /// LE VERROU D'UN POSTE DE SECOURS (lot ORG2, P3, 11/11/2026) : délai en base (5 minutes, À VALIDER), poste désigné à ce poste même. Les deux commandes sont ABSENTES pour qui
  /// ne règle pas (administrateur et Directrice Administrative seuls) ; le domaine refait le contrôle.
  Widget _carteSecours(BuildContext ctx, ContexteEcran c) {
    final vs = VerrouSecoursPoste(c.magasin, auteur: () => acteur(c).nom, role: c.role, horloge: () => c.aujourdhui);
    final secours = vs.posteDeSecours();
    Widget valeur(String libelle, Widget v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(libelle, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
      v,
    ]));
    const gras = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800);
    return CarteSigh(
        titre: 'Verrou d’un poste de secours',
        actions: [
          if (vs.peutRegler && c.droit.editer) ...[
            BoutonSigh(
                libelle: 'Régler le délai de secours',
                icone: LucideIcons.slidersHorizontal,
                variante: VarianteBouton.secondaire,
                taille: TailleBouton.sm,
                onPressed: () => _reglerDelai(ctx, c, vs)),
            BoutonSigh(
                libelle: secours ? 'Retirer la désignation de ce poste' : 'Désigner ce poste comme poste de secours',
                icone: LucideIcons.monitor,
                variante: VarianteBouton.secondaire,
                taille: TailleBouton.sm,
                onPressed: () async {
                  final r = await vs.definirPoste(!secours);
                  if (!ctx.mounted) return;
                  if (r['ok'] != true) {
                    ToastsSigh.afficher(ctx, '${r['motif']}', type: TypeToast.erreur, detail: '${r['geste']}');
                    return;
                  }
                  _appliquerAuVerrou(c, vs);
                  ToastsSigh.afficher(ctx, r['secours'] == true ? 'Ce poste est un poste de secours : verrou à ${r['delaiMinutes']} min.' : 'Ce poste est un poste ordinaire : verrou à ${r['delaiMinutes']} min.',
                      type: TypeToast.succes);
                  setState(() {});
                }),
          ],
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Un poste partagé de secours, où un agent sans téléphone ouvre sa propre session, se verrouille plus vite qu’un poste ordinaire. Le délai de secours est une valeur d’attente proposée par l’équipe, à valider par la Direction : aucun document ne la fixe. Le délai ordinaire (CDCT 12.2) ne change pas.',
              ton: TonSigh.info,
              icone: LucideIcons.timer),
          const SizedBox(height: 12),
          Row(children: [
            valeur('Poste ordinaire', Text('${vs.delaiOrdinaire()} min', style: gras)),
            valeur('Poste de secours', Row(children: [Text('${vs.delaiSecours()} min', style: gras), const SizedBox(width: 8), const BadgeSigh('À valider', ton: TonSigh.attention)])),
            valeur('Ce poste', Text('${secours ? 'Poste de secours' : 'Poste ordinaire'} : verrou à ${vs.delaiPoste()} min', style: gras)),
          ]),
        ]));
  }

  /// Le verrou de la session ouverte suit aussitôt le réglage ou la désignation.
  void _appliquerAuVerrou(ContexteEcran c, VerrouSecoursPoste vs) =>
      RegistreSessions.de(c.magasin).appliquerDelaiVerrou?.call(Duration(minutes: vs.delaiOrdinaire()));

  void _reglerDelai(BuildContext ctx, ContexteEcran c, VerrouSecoursPoste vs) {
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'minutes',
          libelle: 'Délai de verrou d’un poste de secours (minutes)',
          type: TypeChamp.nombre,
          requis: true,
          col: ColChamp.plein,
          aide: 'Entier de $delaiVerrouSecoursMin à $delaiVerrouSecoursMax. Valeur d’attente de $delaiVerrouSecoursDefautMin minutes, à valider par la Direction.'),
      const ChampDef(nom: 'motif', libelle: 'Motif (facultatif)', col: ColChamp.plein),
    ], {'minutes': '${vs.delaiSecours()}'});
    afficherModale<void>(ctx,
        titre: 'Délai de verrou d’un poste de secours',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r = vs.definirDelai(v['minutes'], motif: '${v['motif'] ?? ''}'.isEmpty ? null : '${v['motif']}');
                    if (r['ok'] != true) {
                      ToastsSigh.afficher(ctx, '${r['motif']}', type: TypeToast.erreur, detail: '${r['geste']}');
                      return;
                    }
                    fermer();
                    _appliquerAuVerrou(c, vs);
                    ToastsSigh.afficher(ctx, 'Délai de secours réglé à ${r['minutes']} min.', type: TypeToast.succes);
                    setState(() {});
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final reg = RegistreSessions.de(m);
    return ListenableBuilder(
        listenable: m.collection('sessionsUtilisateur'),
        builder: (context, _) {
          final rows = secLignesSessions(reg.fiches);
          final k = secKpisSessions(rows);
          final lignes = <Map<String, Object?>>[
            for (final r in rows) {...r, 'role': libelleRole(m, r['role'])}
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Sessions ouvertes', valeur: nombre(k.ouvertes), icone: LucideIcons.monitor, ton: TonSigh.navy),
              KpiSigh(libelle: 'Postes distincts', valeur: nombre(k.postes), icone: LucideIcons.network, ton: TonSigh.info),
              KpiSigh(libelle: 'Verrouillées pour inactivité', valeur: nombre(k.suspendues), icone: LucideIcons.lock, ton: TonSigh.attention),
              KpiSigh(
                  libelle: 'Clôturées', valeur: nombre(k.cloturees), icone: LucideIcons.logOut, ton: TonSigh.neutre, indice: 'Conservées au registre'),
              const KpiSigh(
                  libelle: 'Délai de verrouillage',
                  valeur: '$secDelaiVerrouillageMin min',
                  icone: LucideIcons.timer,
                  ton: TonSigh.neutre,
                  indice: 'Postes partagés'),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Sur les postes partagés (accueil et caisse), un délai d’inactivité de 15 minutes entraîne le verrouillage automatique de l’écran. Clôturer une session va plus loin : elle est fermée, et l’agent doit se reconnecter.',
                ton: TonSigh.info,
                icone: LucideIcons.lock),
            const SizedBox(height: 16),
            _carteSecours(context, c),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Sessions',
              lignes: lignes,
              taillePage: 15,
              nomExport: 'sessions',
              filtres: [
                FiltreTableau(
                    nom: 'etat',
                    libelle: 'État',
                    options: const [
                      OptionChamp('active', 'Actives'),
                      OptionChamp('suspendue', 'Suspendues'),
                      OptionChamp('cloturee', 'Clôturées'),
                      OptionChamp('ouverte', 'Ouvertes (actives et suspendues)'),
                    ],
                    correspond: (r, v) => v == 'ouverte' ? '${r['etat']}' != 'cloturee' : '${r['etat']}' == v),
              ],
              colonnes: [
                ColonneTableau(
                    cle: 'identifiant',
                    libelle: 'Identifiant',
                    sansCoupure: true,
                    rendu: (_, r) => Text('${r['identifiant']}',
                        style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
                const ColonneTableau(cle: 'nomComplet', libelle: 'Utilisateur'),
                ColonneTableau(cle: 'role', libelle: 'Rôle', rendu: (_, r) => BadgeSigh('${r['role']}', ton: TonSigh.navy)),
                ColonneTableau(cle: 'poste', libelle: 'Poste', sansCoupure: true, rendu: (_, r) => Text('${r['poste']}', style: styleMono)),
                ColonneTableau(
                    cle: 'adresseIp',
                    libelle: 'Adresse réseau',
                    sansCoupure: true,
                    texte: (r) => '${r['adresseIp'] ?? '—'}',
                    rendu: (_, r) => Text('${r['adresseIp'] ?? '—'}', style: styleMono.copyWith(color: JetonsShell.slate500))),
                ColonneTableau(
                    cle: 'debut',
                    libelle: 'Ouverture',
                    sansCoupure: true,
                    texte: (r) => heure(DateTime.parse('${r['debut']}')),
                    rendu: (_, r) => Text(heure(DateTime.parse('${r['debut']}')),
                        style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
                ColonneTableau(
                    cle: 'inactivite',
                    libelle: 'Inactivité',
                    droite: true,
                    texte: (r) => r['inactivite'] == null ? '—' : '${r['inactivite']} min',
                    rendu: (_, r) {
                      final n = r['inactivite'] as int?;
                      if (n == null) return const Text('—', style: TextStyle(color: JetonsShell.slate400));
                      return Text('$n min',
                          style: TextStyle(
                              color: n >= secDelaiVerrouillageMin ? JetonsShell.warning600 : JetonsShell.slate600,
                              fontWeight: n >= secDelaiVerrouillageMin ? FontWeight.w600 : FontWeight.w400,
                              fontFeatures: const [FontFeature.tabularFigures()]));
                    }),
                ColonneTableau(
                    cle: 'etat',
                    libelle: 'État',
                    texte: (r) => secLibelleEtatSession('${r['etat']}'),
                    rendu: (_, r) {
                      final e = '${r['etat']}';
                      return BadgeSigh(secLibelleEtatSession(e), ton: e == 'cloturee' ? TonSigh.neutre : (e == 'suspendue' ? TonSigh.attention : TonSigh.succes));
                    }),
                ColonneTableau(
                    cle: 'clotureLe',
                    libelle: 'Clôture',
                    sansCoupure: true,
                    texte: (r) => r['clotureLe'] == null ? '—' : '${dateHeure(DateTime.parse('${r['clotureLe']}').toLocal())} ${r['cloturePar'] ?? ''}',
                    rendu: (_, r) {
                      if (r['clotureLe'] == null) return const Text('—', style: TextStyle(color: JetonsShell.slate400));
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(dateHeure(DateTime.parse('${r['clotureLe']}').toLocal()), style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12)),
                        Text('par ${r['cloturePar'] ?? ''}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                      ]);
                    }),
              ],
              // « Clôturer » est une ÉCRITURE : ABSENTE sans le droit d'éditer (E593), et absente d'une session déjà clôturée (elle ne se rouvre pas ni ne se reclôture).
              actionsLigne: (context, r) => [
                if (c.droit.editer && '${r['etat']}' != 'cloturee')
                  BoutonSigh(
                      libelle: 'Clôturer',
                      icone: LucideIcons.logOut,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.danger,
                      onPressed: () => _cloturer(context, c, r)),
              ],
            ),
          ]);
        });
  }
}
