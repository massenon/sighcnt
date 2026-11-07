import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_crud.dart';
import 'rhb_commun.dart';
import 'rhc_badge_carte.dart';
import 'rhc_badges.dart';

/// `m10-badges-modeles` — les GABARITS : format, orientation, zones imprimées, mentions du verso. Le badge ne porte aucune couleur en dur : il suit la charte de
/// l'établissement. L'en-tête officiel ne s'y applique pas tel quel (ni IFU ni RCCM : mentions FISCALES). Les mentions du verso sont une proposition à valider.
///
/// E745 — la maquette ne retire pas l'ancien modèle « par défaut » quand on en désigne un autre : deux modèles peuvent l'être, le premier de la collection l'emporte
/// (`rhcModeleParDefaut`). Porté fidèlement, signalé.
class EcranBadgesModeles extends StatelessWidget with EcranMaquette {
  const EcranBadgesModeles({super.key});

  @override
  String get titre => 'Modèles de badge';
  @override
  String get description => 'Les gabarits : format, orientation, zones imprimées et mentions du verso.';
  @override
  String get regle =>
      'Le badge ne porte aucune couleur en dur : il suit la charte de l’établissement, si bien qu’une autre clinique n’a rien à retoucher. L’en-tête officiel ne s’y applique pas tel quel — un badge n’est pas un état administratif : logo, dénomination et devise, mais ni IFU ni RCCM, qui sont des mentions fiscales. Les mentions du verso sont une proposition à valider : elles engagent la clinique envers le porteur.';

  static const _zones = [
    OptionChamp('photo', 'Photographie'),
    OptionChamp('nom', 'Nom de l’agent'),
    OptionChamp('fonction', 'Fonction / poste'),
    OptionChamp('service', 'Service'),
    OptionChamp('qr', 'Code QR de contrôle'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    rhcAmorcerModele(c);
    final col = c.magasin.collection('modelesBadge');
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) => CrudMat(
              collection: col,
              entite: 'modèle de badge',
              entiteP: 'modèles de badge',
              prefixeId: 'MOD',
              triInitial: 'libelle',
              taillePage: 8,
              kpis: (ctx, rows) => const [],
              colonnes: [
                const ColonneTableau(cle: 'libelle', libelle: 'Modèle'),
                const ColonneTableau(cle: 'format', libelle: 'Format'),
                const ColonneTableau(cle: 'orientation', libelle: 'Orientation'),
                ColonneTableau(
                    cle: 'zones',
                    libelle: 'Zones imprimées',
                    texte: (m) => ((m['zones'] as List?) ?? const []).isEmpty ? '—' : (m['zones'] as List).join(' · '),
                    rendu: (_, m) => Text(((m['zones'] as List?) ?? const []).isEmpty ? '—' : (m['zones'] as List).join(' · '),
                        style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
                ColonneTableau(
                    cle: 'defaut',
                    libelle: 'Par défaut',
                    texte: (m) => m['defaut'] == true ? 'Modèle par défaut' : '—',
                    rendu: (_, m) => m['defaut'] == true ? const BadgeSigh('Modèle par défaut', ton: TonSigh.succes) : const Text('—', style: TextStyle(color: JetonsShell.slate300))),
                ColonneTableau(
                    cle: 'aValider',
                    libelle: 'Statut',
                    texte: (m) => m['aValider'] == true ? 'Proposition à valider' : 'Arrêté',
                    rendu: (_, m) => m['aValider'] == true ? const BadgeSigh('Proposition à valider', ton: TonSigh.attention) : const BadgeSigh('Arrêté', ton: TonSigh.succes)),
              ],
              champs: (m) => [
                const ChampDef(nom: 'libelle', libelle: 'Intitulé du modèle', requis: true, col: ColChamp.plein),
                const ChampDef(
                    nom: 'format',
                    libelle: 'Format de carte',
                    type: TypeChamp.select,
                    requis: true,
                    options: [OptionChamp('CR80 (85,6 × 54 mm)', 'CR80 — 85,6 × 54 mm (standard)')],
                    aide: 'Le format des imprimantes à cartes et des porte-badges du commerce.'),
                const ChampDef(nom: 'orientation', libelle: 'Orientation', type: TypeChamp.select, requis: true, options: [OptionChamp('paysage', 'Paysage'), OptionChamp('portrait', 'Portrait')]),
                const ChampDef(nom: 'zones', libelle: 'Zones imprimées au recto', type: TypeChamp.multiselect, requis: true, col: ColChamp.plein, options: _zones),
                const ChampDef(nom: 'mentionsVerso', libelle: 'Mentions du verso — une par ligne', type: TypeChamp.textarea, lignes: 5, col: ColChamp.plein),
                const ChampDef(nom: 'defaut', libelle: 'Modèle proposé par défaut', type: TypeChamp.case_),
              ],
              valeursInitiales: () => {'format': 'CR80 (85,6 × 54 mm)', 'orientation': 'paysage', 'zones': ['photo', 'nom', 'fonction', 'service', 'qr']},
              transformer: (ctx, v) => {
                'libelle': v['libelle'],
                'format': v['format'],
                'orientation': v['orientation'],
                'zones': v['zones'],
                'mentionsVerso': v['mentionsVerso'] ?? '',
                'defaut': v['defaut'] == true,
              },
              detail: (ctx, m) {
                final modeles = rhbActives(ContexteEcran.of(ctx), 'modelesBadge');
                final norm = rhcModeleNormalise(m, modeles);
                final auj = ContexteEcran.of(ctx).aujourdhui;
                // Le spécimen : un badge imaginaire, jamais un agent réel.
                final faux = <String, Object?>{
                  'numero': 'BDG-00000-${auj.year}',
                  'matricule': '00',
                  'agent': 'SPÉCIMEN — Aperçu',
                  'poste': 'Fonction de l’agent',
                  'service': 'Service',
                  'expireLe': rhcExpirationDepuis(auj),
                };
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NoteSigh('Aperçu à l’échelle : le badge est composé en millimètres, pas en pixels — c’est ce qui permet de l’imprimer tel quel sur une carte.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 16, runSpacing: 16, children: [
                    CarteBadgeSigh(badge: faux, modele: norm),
                    CarteBadgeSigh(badge: faux, modele: norm, verso: true),
                  ]),
                  const SizedBox(height: 12),
                  DescListeSigh([('Mentions du verso', '${norm.mentionsVerso.length} ligne(s)'), ('Source', m['source'] ?? '—')]),
                ]);
              },
              titreDetail: (m) => '${m['libelle']}',
              sousTitreDetail: (m) => null,
            ));
  }
}
