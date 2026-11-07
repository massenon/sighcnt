import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'commun.dart';

/// `m9-historique` — « Historique par assureur » : retrouver, compagnie par compagnie, le détail de ce qui a été consommé — pour répondre à une
/// contestation, préparer une renégociation ou extraire librement les données d'un assuré. Cet écran EXTRAIT, il ne modifie rien.
class EcranHistoriqueAssureur extends StatefulWidget with EcranMaquette {
  const EcranHistoriqueAssureur({super.key});

  @override
  String get titre => 'Historique par assureur';

  @override
  String get description =>
      'Détail des prestations consommées par compagnie, souscripteur et assuré, sur une plage libre.';

  @override
  String get regle =>
      'Cet écran extrait, il ne modifie rien. Il répond à la demande d’extraction libre des données des assurés : filtrer, consulter le détail d’une prestation, exporter la sélection.';

  @override
  State<EcranHistoriqueAssureur> createState() => _EtatHistorique();
}

class _EtatHistorique extends State<EcranHistoriqueAssureur> {
  ControleurFormulaire? _compagnie, _du, _au;

  List<ControleurFormulaire> get _tous => [_compagnie!, _du!, _au!];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_compagnie != null) return;
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    final jour = DateTime(auj.year, auj.month, auj.day);
    ChampDef def(String nom, String libelle, TypeChamp type,
            {List<OptionChamp> options = const []}) =>
        ChampDef(
            nom: nom,
            libelle: libelle,
            type: type,
            options: options,
            col: ColChamp.plein);
    _compagnie = champUnique(
        def('compagnie', 'Compagnie', TypeChamp.select, options: [
          const OptionChamp('', 'Toutes les compagnies'),
          for (final a in actives(c, 'assureurs'))
            OptionChamp('${a['code']}', '${a['nom']}')
        ]),
        '');
    _du = champUnique(def('du', 'Du', TypeChamp.date),
        iso(jour.subtract(const Duration(days: 180))));
    _au = champUnique(def('au', 'Au', TypeChamp.date), iso(jour));
    for (final k in _tous) {
      k.addListener(_surChangement);
    }
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_compagnie != null) {
      for (final k in _tous) {
        k.removeListener(_surChangement);
        k.dispose();
      }
    }
    super.dispose();
  }

  void _detail(BuildContext ctx, Fiche f) {
    final lignes = (f['lignes'] as List?)
            ?.map((x) => (x as Map).cast<String, Object?>())
            .toList() ??
        const <Fiche>[];
    afficherTiroir<void>(ctx,
        titre: '${f['numero']}',
        sousTitre: '${f['patient']} — ${dateDe(f['date'])}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Assuré', f['patient']),
            ('Dossier', f['patientCode'] ?? '—'),
            ('Compagnie', f['assureurNom']),
            ('Souscripteur', f['souscripteurNom']),
            ('N° de police', f['police']),
            ('Nature', f['type']),
            ('Montant', money(f['montantTTC'])),
            ('Part assureur', money(f['partAssurance'])),
            ('Part patient', money(f['partPatient'])),
            ('Reste dû', money(f['reliquat'])),
          ]),
          const SizedBox(height: 16),
          if (lignes.isNotEmpty)
            CarteSigh(
                titre: 'Lignes de la prestation',
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Désignation', (l) => '${l['designation'] ?? ''}'),
                  ColonneMini('Qté', (l) => '${l['quantite'] ?? ''}', droite: true),
                  ColonneMini(
                      'Montant',
                      (l) => m(l['montant'] ??
                          n(l['quantite']) * n(l['prixUnitaire'])),
                      droite: true),
                  ColonneMini('Part ass.', (l) => m(l['partAssureur'] ?? 0),
                      droite: true),
                  ColonneMini('Motif', (l) => '${l['motifCouverture'] ?? '—'}'),
                ], lignes: lignes))
          else
            const NoteSigh(
                'Cette facture est antérieure au détail par ligne : seul son total est connu.',
                icone: LucideIcons.lock),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['assureurs', 'patients', 'factures', 'souscripteurs']),
      builder: (context, _) {
        final rows = assHistorique(
            facturesAssurance: assFacturesAssurance(actives(c, 'factures')),
            patients: actives(c, 'patients'),
            souscripteurs: actives(c, 'souscripteurs'),
            assureurs: actives(c, 'assureurs'),
            code: '${_compagnie!['compagnie'] ?? ''}',
            du: '${_du!['du'] ?? ''}',
            au: '${_au!['au'] ?? ''}');
        final parCompagnie = <String, num>{};
        for (final r in rows) {
          parCompagnie['${r['assureurNom']}'] =
              (parCompagnie['${r['assureurNom']}'] ?? 0) + n(r['partAssurance']);
        }
        final classement = parCompagnie.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        List<OptionChamp> distincts(String cle) {
          final v = {for (final r in rows) '${r[cle]}'}.toList()..sort();
          return [for (final x in v) OptionChamp(x)];
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                    commande(_compagnie!, largeur: 280),
                    commande(_du!, largeur: 170),
                    commande(_au!, largeur: 170),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Prestations',
                    valeur: nombre(rows.length),
                    indice:
                        '${dateDe(_du!['du'])} → ${dateDe(_au!['au'])}',
                    icone: LucideIcons.history),
                KpiSigh(
                    libelle: 'Assurés distincts',
                    valeur: nombre({for (final r in rows) r['patientId']}.length),
                    icone: LucideIcons.users,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Total facturé',
                    valeur: money(assSomme(rows, 'montantTTC')),
                    icone: LucideIcons.receipt,
                    ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Part assureurs',
                    valeur: money(assSomme(rows, 'partAssurance')),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
              ]),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const VideSigh('Aucune prestation assurée sur la plage choisie.',
                    icone: LucideIcons.history)
              else ...[
                CarteSigh(
                    titre: 'Répartition par compagnie',
                    child: ClassementSigh([
                      for (final e in classement)
                        (libelle: e.key, valeur: e.value)
                    ])),
                const SizedBox(height: 16),
                TableauSigh(
                  titre: 'Détail des prestations',
                  lignes: rows,
                  taillePage: 20,
                  nomExport: 'historique-assureur',
                  triInitial: 'date',
                  sensInitial: 'desc',
                  alClicLigne: (f) => _detail(context, f),
                  filtres: [
                    FiltreTableau(
                        nom: 'souscripteurNom',
                        libelle: 'Souscripteur',
                        options: distincts('souscripteurNom')),
                    FiltreTableau(
                        nom: 'type',
                        libelle: 'Nature',
                        options: distincts('type')),
                    FiltreTableau(
                        nom: 'reglement',
                        libelle: 'Règlement',
                        options: [
                          OptionChamp('soldee', 'Soldée'),
                          OptionChamp('due', 'Reste dû')
                        ],
                        correspond: (f, v) => v == 'soldee'
                            ? n(f['reliquat']) == 0
                            : n(f['reliquat']) > 0),
                  ],
                  colonnes: [
                    ColonneTableau(
                        cle: 'date',
                        libelle: 'Date',
                        sansCoupure: true,
                        valeur: (f) => f['date'],
                        texte: (f) => dateDe(f['date'])),
                    ColonneTableau(
                        cle: 'numero',
                        libelle: 'Pièce',
                        sansCoupure: true,
                        texte: (f) => '${f['numero'] ?? ''}',
                        rendu: (_, f) => monoTexte(f['numero'])),
                    ColonneTableau(
                        cle: 'patient',
                        libelle: 'Assuré',
                        texte: (f) => '${f['patient'] ?? ''} ${f['patientCode'] ?? ''}',
                        rendu: (_, f) => _deuxLignes(
                            '${f['patient'] ?? ''}', '${f['patientCode'] ?? '—'}')),
                    ColonneTableau(
                        cle: 'souscripteurNom',
                        libelle: 'Souscripteur',
                        texte: (f) => '${f['souscripteurNom']} ${f['police']}',
                        rendu: (_, f) =>
                            _deuxLignes('${f['souscripteurNom']}', '${f['police']}')),
                    ColonneTableau(
                        cle: 'assureurNom',
                        libelle: 'Compagnie',
                        texte: (f) => '${f['assureur']}',
                        rendu: (_, f) =>
                            BadgeSigh('${f['assureur']}', ton: TonSigh.navy)),
                    const ColonneTableau(cle: 'type', libelle: 'Nature'),
                    ColonneTableau(
                        cle: 'montantTTC',
                        libelle: 'Montant',
                        droite: true,
                        texte: (f) => m(f['montantTTC'])),
                    ColonneTableau(
                        cle: 'partAssurance',
                        libelle: 'Part assureur',
                        droite: true,
                        texte: (f) => m(f['partAssurance']),
                        rendu: (_, f) => montantFort(n(f['partAssurance']))),
                  ],
                ),
              ],
            ]);
      },
    );
  }

  static Widget _deuxLignes(String haut, String bas) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(haut,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: JetonsShell.slate800, fontSize: 14, height: 20 / 14)),
            Text(bas, style: mono.copyWith(color: JetonsShell.slate400)),
          ]);
}
