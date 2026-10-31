import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m14.dart';

/// `m14-audit` — « Journal d'audit » : traçabilité intégrale (RG-12 : aucune action anonyme). Lecture seule par nature : le journal ne se corrige pas.
///
/// Le journal du poste est celui du magasin (`audit`, plafonné à 400 entrées comme la maquette). Les entrées du jeu portent leurs valeurs en TEXTE
/// (`ancienneValeur` / `nouvelleValeur`), celles que le poste écrit en objets (`avant` / `apres`) : le tiroir lit les deux et les indente sans les réécrire.
class EcranAudit extends StatelessWidget with EcranMaquette {
  const EcranAudit({super.key});

  @override
  String get description =>
      'Traçabilité intégrale : création, modification, validation, archivage et connexions.';

  @override
  String get regle =>
      'RG-12 — toute action de création, modification, validation ou suppression est journalisée avec l’identité de l’utilisateur, la date, l’heure et l’entité concernée. Aucune action anonyme n’est permise.';

  @override
  Widget build(BuildContext context) => const _VueAudit();
}

class _VueAudit extends StatefulWidget {
  const _VueAudit();
  @override
  State<_VueAudit> createState() => _VueAuditState();
}

class _VueAuditState extends State<_VueAudit> {
  CollectionMagasin? _col;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final col = ContexteEcran.of(context).magasin.collection('audit');
    if (!identical(col, _col)) {
      _col?.removeListener(_maj);
      _col = col..addListener(_maj);
    }
  }

  @override
  void dispose() {
    _col?.removeListener(_maj);
    super.dispose();
  }

  void _maj() => setState(() {});

  static TonSigh _ton(String t) => switch (t) {
        'success' => TonSigh.succes,
        'info' => TonSigh.info,
        'warning' => TonSigh.attention,
        'danger' => TonSigh.danger,
        'navy' => TonSigh.navy,
        _ => TonSigh.neutre,
      };

  static bool _echec(Fiche a) => a['succes'] == false;

  static int _ms(Fiche a) => secHorodatage(a['dateHeure'])?.millisecondsSinceEpoch ?? 0;

  void _detail(BuildContext ctx, Fiche a) {
    final dh = secHorodatage(a['dateHeure']);
    final avant = secAncienneValeur(a);
    final apres = secNouvelleValeur(a);
    Widget valeur(String libelle, Object? v) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(libelle,
                  style: const TextStyle(
                      color: JetonsShell.slate500,
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: JetonsShell.slate50, borderRadius: BorderRadius.circular(4)),
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(secJsonLisible(v),
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              color: JetonsShell.slate700,
                              fontSize: 11,
                              height: 1.5)))),
            ]);
    final succes = !_echec(a);
    afficherTiroir<void>(ctx,
        titre: '${a['action']} — ${a['entite']}',
        sousTitre: dh == null ? '' : dateHeure(dh),
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Horodatage', dh == null ? '—' : dateHeure(dh)),
            ('Utilisateur', a['utilisateur']),
            ('Action', BadgeSigh('${a['action']}', ton: TonSigh.navy)),
            ('Module', a['module']),
            ('Entité concernée', a['entite']),
            ('Référence', a['reference'] ?? '—'),
            ('Poste de travail', a['poste'] ?? '—'),
            (
              'Résultat',
              succes
                  ? const BadgeSigh('Succès', ton: TonSigh.succes)
                  : const BadgeSigh('Échec', ton: TonSigh.danger)
            ),
          ]),
          const SizedBox(height: 16),
          if (secVrai(avant) || secVrai(apres))
            CarteSigh(
                titre: 'Valeurs',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (secVrai(avant)) valeur('Ancienne valeur', avant),
                  if (secVrai(avant) && secVrai(apres)) const SizedBox(height: 12),
                  if (secVrai(apres)) valeur('Nouvelle valeur', apres),
                ]))
          else
            const VideSigh('Aucune valeur détaillée conservée pour cette action.',
                icone: LucideIcons.file),
        ]));
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, List<Fiche> rows, ({int actions, int utilisateurs, int modules, int echecs}) s) {
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Journal d’audit',
          sousTitre: 'Traçabilité des actions — situation au ${dateFR(c.aujourdhui)}',
          reference: referenceImpression(c),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Actions journalisées', nombre(s.actions)),
            ('Utilisateurs tracés', nombre(s.utilisateurs)),
            ('Tentatives infructueuses', nombre(s.echecs)),
            ('Date d’édition', dateFR(c.aujourdhui)),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(
                  libelle: 'Horodatage',
                  valeur: (a) {
                    final d = secHorodatage(a['dateHeure']);
                    return d == null ? '' : dateHeure(d);
                  }),
              ColonneEtat(libelle: 'Utilisateur', valeur: (a) => '${a['utilisateur'] ?? ''}'),
              ColonneEtat(libelle: 'Action', valeur: (a) => '${a['action'] ?? ''}'),
              ColonneEtat(libelle: 'Module', valeur: (a) => '${a['module'] ?? ''}'),
              ColonneEtat(libelle: 'Entité', valeur: (a) => '${a['entite'] ?? ''}'),
              ColonneEtat(libelle: 'Référence', valeur: (a) => '${a['reference'] ?? ''}'),
              ColonneEtat(libelle: 'Poste', valeur: (a) => '${a['poste'] ?? ''}'),
              ColonneEtat(libelle: 'Résultat', valeur: (a) => _echec(a) ? 'Échec' : 'Succès'),
            ], lignes: rows.take(100).toList())
          ],
          signatures: const [
            Signature('L’Administrateur système'),
            Signature('La Direction', nom: 'BASSONGUI Chabi Séko'),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    // Le journal du poste : l'entrée la plus récente est EN TÊTE ; l'état imprime les cent premières telles que le journal les tient.
    final rows = _col!.toutes;
    final s = secStatsAudit(rows);
    final parModule = secGrouper(rows, 'module');
    final parAction = secGrouper(rows, 'action');
    List<OptionChamp> options(String cle) =>
        [for (final k in (secGrouper(rows, cle).keys.toList()..sort())) OptionChamp(k)];
    Widget deux(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
          final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(width: l, child: a),
            SizedBox(width: l, child: b),
          ]);
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Actions journalisées',
            valeur: nombre(s.actions),
            icone: LucideIcons.scrollText,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Utilisateurs tracés',
            valeur: nombre(s.utilisateurs),
            icone: LucideIcons.users,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Modules concernés',
            valeur: nombre(s.modules),
            icone: LucideIcons.layers,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Tentatives infructueuses',
            valeur: nombre(s.echecs),
            icone: LucideIcons.shieldAlert,
            ton: s.echecs > 0 ? TonSigh.danger : TonSigh.neutre),
      ]),
      if (s.echecs > 0) ...[
        const SizedBox(height: 16),
        NoteSigh(
            '${s.echecs} tentative(s) d’accès infructueuse(s) enregistrée(s). Ces événements doivent faire l’objet d’une revue périodique par l’Administrateur et la Direction.',
            ton: TonSigh.attention,
            icone: LucideIcons.shieldAlert),
      ],
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Journal d’audit',
        lignes: rows,
        taillePage: 25,
        triInitial: 'dateHeure',
        sensInitial: 'desc',
        nomExport: 'journal-audit',
        filtres: [
          FiltreTableau(nom: 'action', libelle: 'Action', options: options('action')),
          FiltreTableau(nom: 'module', libelle: 'Module', options: options('module')),
          FiltreTableau(nom: 'utilisateur', libelle: 'Utilisateur', options: options('utilisateur')),
          FiltreTableau(
              nom: 'succes',
              libelle: 'Résultat',
              options: const [OptionChamp('ok', 'Réussies'), OptionChamp('ko', 'Échouées')],
              correspond: (a, v) => v == 'ok' ? !_echec(a) : _echec(a)),
        ],
        alClicLigne: (a) => _detail(context, a),
        actions: [
          BoutonSigh(
              libelle: 'Imprimer le journal',
              icone: LucideIcons.printer,
              taille: TailleBouton.sm,
              onPressed: () => _imprimer(context, c, rows, s)),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'dateHeure',
              libelle: 'Horodatage',
              sansCoupure: true,
              valeur: _ms,
              texte: (a) {
                final d = secHorodatage(a['dateHeure']);
                return d == null ? '' : dateHeure(d);
              },
              rendu: (_, a) {
                final d = secHorodatage(a['dateHeure']);
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d == null ? '' : dateHeure(d),
                          style: const TextStyle(
                              color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                      Text(d == null ? '' : secIlYA(d, c.aujourdhui),
                          style: const TextStyle(
                              color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                    ]);
              }),
          const ColonneTableau(cle: 'utilisateur', libelle: 'Utilisateur'),
          ColonneTableau(
              cle: 'action',
              libelle: 'Action',
              rendu: (_, a) => BadgeSigh('${a['action'] ?? ''}',
                  ton: _ton(secTonAction('${a['action'] ?? ''}', succes: !_echec(a))))),
          ColonneTableau(
              cle: 'module',
              libelle: 'Module',
              rendu: (_, a) => BadgeSigh('${a['module'] ?? ''}')),
          const ColonneTableau(cle: 'entite', libelle: 'Entité concernée'),
          ColonneTableau(
              cle: 'reference',
              libelle: 'Référence',
              sansCoupure: true,
              texte: (a) => '${a['reference'] ?? '—'}',
              rendu: (_, a) => Text('${a['reference'] ?? '—'}',
                  style: styleMono.copyWith(color: JetonsShell.slate500))),
          ColonneTableau(
              cle: 'poste',
              libelle: 'Poste',
              sansCoupure: true,
              texte: (a) => '${a['poste'] ?? '—'}',
              rendu: (_, a) => Text('${a['poste'] ?? '—'}',
                  style: styleMono.copyWith(color: JetonsShell.slate500))),
          ColonneTableau(
              cle: 'succes',
              libelle: 'Résultat',
              texte: (a) => _echec(a) ? 'Échec' : 'Succès',
              rendu: (_, a) => _echec(a)
                  ? const BadgeSigh('Échec', ton: TonSigh.danger)
                  : const BadgeSigh('Succès', ton: TonSigh.succes)),
        ],
      ),
      const SizedBox(height: 16),
      deux(
        CarteSigh(
            titre: 'Actions par module',
            child: GraphiqueBarres(etiquettes: parModule.keys.toList(), series: [
              SerieGraphique('Actions', [for (final l in parModule.values) l.length])
            ])),
        CarteSigh(
            titre: 'Répartition par type d’action',
            child: GraphiqueAnneau(
                etiquettes: parAction.keys.toList(),
                valeurs: [for (final l in parAction.values) l.length])),
      ),
      const SizedBox(height: 16),
      const NoteSigh(
          'La durée de conservation du journal d’audit est fixée contractuellement à cinq ans minimum pour les données financières et médicales.',
          ton: TonSigh.info,
          icone: LucideIcons.archive),
    ]);
  }
}
