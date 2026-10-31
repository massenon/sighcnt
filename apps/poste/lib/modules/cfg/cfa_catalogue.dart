import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// `cfg-catalogue` — « Catalogue tarifaire (deux prix) » : les six grilles officielles, chaque acte porte DEUX prix — non assuré et assuré. C'est la validité
/// de la carte à la date de facturation (RG-09) qui décide lequel s'applique. Trois états dans la colonne assurée : un montant, NON COUVERT, ou un TIRET
/// qui n'est ni un zéro ni une exclusion mais une valeur manquante : la ligne n'est alors pas facturable. Jamais de prix présumé nul.
class EcranCatalogue extends StatelessWidget with EcranMaquette {
  const EcranCatalogue({super.key});
  @override
  String get titre => 'Catalogue tarifaire (deux prix)';
  @override
  String get description => 'Les six grilles officielles : consultations, imageries, analyses, AMI, gynéco-obstétrique, certificats.';
  @override
  String get regle =>
      'Chaque acte porte deux prix — non assuré et assuré. C’est la validité de la carte à la date de facturation qui décide lequel s’applique (RG-09), et non le fait de posséder une carte. Un acte NON COUVERT reste facturé au patient au tarif non assuré, motif à l’appui. Un prix absent bloque la ligne : il n’est jamais présumé nul.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('catalogueTarifs');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = col.actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisCatalogue(rows)),
            for (final n in cfaNotesCatalogue(rows)) ...[
              const SizedBox(height: 16),
              NoteSigh(n.texte, ton: cfaTonNote(n.ton), icone: n.ton == 'danger' ? LucideIcons.triangleAlert : n.ton == 'attention' ? LucideIcons.scale : LucideIcons.gavel),
            ],
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              for (final f in cfaFamillesTarif)
                OngletDef(
                    id: f.$1.toLowerCase(),
                    libelle: f.$2,
                    compte: rows.where((r) => r['famille'] == f.$1).length,
                    construire: (_) => _TableauFamille(f.$1)),
            ]),
          ]);
        });
  }
}

Widget _nonRenseigne() => const Text('non renseigné', style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.danger600));

class _TableauFamille extends StatelessWidget {
  const _TableauFamille(this.famille);
  final String famille;

  List<ChampDef> _champs() => [
        const ChampDef(nom: 'code', libelle: 'Code', requis: true),
        const ChampDef(nom: 'libelle', libelle: 'Désignation', requis: true),
        ChampDef(nom: 'famille', libelle: 'Famille', type: TypeChamp.select, requis: true, options: [for (final f in cfaFamillesTarif) OptionChamp(f.$1, f.$2)]),
        const ChampDef(nom: 'prixNonAssure', libelle: 'Prix non assuré (FCFA)', type: TypeChamp.nombre),
        const ChampDef(nom: 'prixAssure', libelle: 'Prix assuré (FCFA)', type: TypeChamp.nombre, aide: 'Laisser vide si le document ne le renseigne pas — un vide n’est pas un zéro.'),
        const ChampDef(nom: 'nonCouvert', libelle: 'NON COUVERT par les assurances', type: TypeChamp.case_),
        const ChampDef(nom: 'source', libelle: 'Document d’origine'),
      ];

  Widget _detail(BuildContext ctx, Fiche r) {
    String prix(Object? v) => v == null ? 'non renseigné' : cfaMoney(v, devise: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DescListeSigh([
        ('Code', '${r['code'] ?? ''}'),
        ('Désignation', '${r['libelle'] ?? ''}'),
        ('Famille', '${r['famille'] ?? ''}'),
        ('Prix non assuré', prix(r['prixNonAssure'])),
        ('Prix assuré', cfaVrai(r['nonCouvert']) ? 'NON COUVERT' : prix(r['prixAssure'])),
        ('Couverture', cfaCouverture(r)),
        ('Document d’origine', cfaOuTiret(r['source'])),
      ]),
      if (cfaVrai(r['motifPrix'])) ...[const SizedBox(height: 16), NoteSigh('${r['motifPrix']}', ton: TonSigh.danger, icone: LucideIcons.triangleAlert)],
      if (cfaVrai(r['aArbitrer'])) ...[const SizedBox(height: 16), NoteSigh('${r['aArbitrer']}', ton: TonSigh.attention, icone: LucideIcons.scale)],
      if (cfaVrai(r['arbitrage'])) ...[const SizedBox(height: 16), NoteSigh('${r['arbitrage']}', ton: TonSigh.info, icone: LucideIcons.gavel)],
      if (cfaVrai(r['nonCouvert'])) ...[
        const SizedBox(height: 16),
        const NoteSigh(
            'Cet acte est NON COUVERT : l’assuré le règle au tarif non assuré, et la facture en porte le motif. Tous les actes de planification familiale sont dans ce cas.',
            ton: TonSigh.attention,
            icone: LucideIcons.shieldOff),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return CfaTableau(
      collection: 'catalogueTarifs',
      entite: 'Acte',
      libelleNouveau: 'Nouvel acte',
      titreCreation: 'Ajouter un acte au catalogue',
      prefixeId: 'TAR',
      messageVide: 'Aucun acte dans cette famille.',
      nomExport: 'catalogue-$famille',
      lignes: (a) => trierPar([for (final r in a) if (r['famille'] == famille) r], (r) => r['code']),
      colonnes: [
        const ColonneTableau(cle: 'code', libelle: 'Code'),
        const ColonneTableau(cle: 'libelle', libelle: 'Désignation'),
        ColonneTableau(
            cle: 'prixNonAssure',
            libelle: 'Prix non assuré',
            droite: true,
            texte: (r) => r['prixNonAssure'] == null ? 'non renseigné' : cfaMoney(r['prixNonAssure'], devise: true),
            rendu: (_, r) => r['prixNonAssure'] == null
                ? _nonRenseigne()
                : Text(cfaMoney(r['prixNonAssure'], devise: true), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))),
        ColonneTableau(
            cle: 'prixAssure',
            libelle: 'Prix assuré',
            droite: true,
            texte: (r) {
              if (cfaVrai(r['nonCouvert'])) return 'NON COUVERT';
              if (r['assurable'] == 'sos') return 'SOS seule — ${cfaMoney(r['prixAssure'], devise: true)}';
              if (r['prixAssure'] == null) return 'non renseigné';
              return cfaMoney(r['prixAssure'], devise: true) + (cfaVrai(r['arbitrage']) ? ' arbitré' : '');
            },
            rendu: (_, r) {
              if (cfaVrai(r['nonCouvert'])) return const BadgeSigh('NON COUVERT', ton: TonSigh.attention);
              if (r['assurable'] == 'sos') return BadgeSigh('SOS seule — ${cfaMoney(r['prixAssure'], devise: true)}', ton: TonSigh.info);
              if (r['prixAssure'] == null) return _nonRenseigne();
              // Un tarif arbitré porte sa marque : sinon un assuré payant moins qu'un non-assuré se lit comme une inversion de saisie.
              if (cfaVrai(r['arbitrage'])) {
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(cfaMoney(r['prixAssure'], devise: true), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                  const SizedBox(width: 4),
                  const BadgeSigh('arbitré', ton: TonSigh.info),
                ]);
              }
              return Text(cfaMoney(r['prixAssure'], devise: true), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700));
            }),
        ColonneTableau(
            cle: 'ecart',
            libelle: 'Écart',
            droite: true,
            texte: cfaEcartTarif,
            rendu: (_, r) {
              final t = cfaEcartTarif(r);
              if (t == '—') return const Text('—', style: TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700));
              final e = (cfaNombre(r['prixAssure']) ?? 0) - (cfaNombre(r['prixNonAssure']) ?? 0);
              return Text(t, style: TextStyle(fontSize: 14, height: 20 / 14, color: e > 0 ? JetonsShell.success700 : JetonsShell.slate500));
            }),
        ColonneTableau(
            cle: 'source',
            libelle: 'Document d’origine',
            texte: (r) => cfaOuTiret(r['source']),
            rendu: (_, r) => Text(cfaOuTiret(r['source']), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
      ],
      champs: (e) => _champs(),
      fiche: (s, e) => e == null ? cfaFicheTarif(s) : {...s, 'prixNonAssure': cfaNombre(s['prixNonAssure']), 'prixAssure': cfaNombre(s['prixAssure'])},
      detail: _detail,
      titreDetail: (r) => '${r['code']} — ${r['libelle']}',
    );
  }
}
