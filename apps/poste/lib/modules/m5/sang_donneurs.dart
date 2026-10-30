import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/stock_commun.dart' show cellule, dateFiche, typographieMono;
import 'sang_crud.dart';

/// `m5-donneurs` — « Donneurs & transfusions » : registre des donneurs de sang, dons réalisés, éligibilité (délai de 90 jours entre deux dons) et carte
/// de donneur. `K.crud` de la maquette : KPI, onglets « Tous les donneurs » / « Archivés », tableau trié / filtré, fiche en tiroir, création et
/// modification en modale, archivage ANNULABLE (RG-14).
///
/// Une référence `DON-NNNN` est attribuée à la création, au rang suivant le plus haut déjà écrit (archivées comprises) — écart E200 : la maquette
/// utilisait un compteur de page et créait un doublon de DON-0001. L'activité est FERMÉE à la clinique dans la maquette (`modulesActifs`) ; le
/// mécanisme de fermeture n'est pas porté ici. Les donneurs ne sont pas semés : la maquette ne les amorce qu'à l'ouverture de l'écran.
class EcranDonneurs extends StatelessWidget with EcranMaquette {
  const EcranDonneurs({super.key});

  @override
  String get titre => 'Donneurs & transfusions';

  @override
  String get description =>
      'Registre des donneurs de sang, dons réalisés et transfusions effectuées avec leur agrément.';

  static TonSigh _ton(String t) => switch (t) {
        'danger' => TonSigh.danger,
        'warning' => TonSigh.attention,
        _ => TonSigh.succes,
      };

  static void _carte(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    final auj = c.aujourdhui;
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'Carte de donneur de sang',
            cartouche: [
              ('Donneur', '${r['nom'] ?? ''}'),
              ('Référence', '${r['reference'] ?? ''}'),
              ('Groupe sanguin', '${r['groupe'] ?? ''}'),
              ('Type de don', '${r['type'] ?? ''}'),
              ('Dons réalisés', '${r['nbDons'] ?? ''}'),
              ('Dernier don', dateFiche(r['dernierDon'])),
            ],
            blocs: const [
              BlocTexte(
                  'La CLINIQUE NASSIERA TOO SARL remercie chaleureusement ce donneur pour son engagement au service de la collectivité.'),
            ],
            signatures: const [
              Signature('Le Laborantin', nom: 'KINNOU Addoul Ganiou'),
              Signature('Le Directeur Médical'),
            ],
            reference:
                PieceA4.reference_(auj, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: auj));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    final col = c.magasin.collection('donneurs');

    return CrudSang(
      collection: col,
      entite: 'donneur',
      entiteP: 'donneurs',
      prefixeId: 'DON',
      triInitial: 'dernierDon',
      sensInitial: 'desc',
      taillePage: 12,
      largeurTiroir: 672,
      colonnes: [
        ColonneTableau(
            cle: 'reference',
            libelle: 'N°',
            sansCoupure: true,
            texte: (r) => '${r['reference'] ?? ''}',
            rendu: (_, r) =>
                Text('${r['reference'] ?? ''}', style: typographieMono)),
        const ColonneTableau(cle: 'nom', libelle: 'Donneur'),
        ColonneTableau(
            cle: 'groupe',
            libelle: 'Groupe',
            texte: (r) => '${r['groupe'] ?? ''}',
            rendu: (_, r) =>
                BadgeSigh('${r['groupe'] ?? ''}', ton: TonSigh.danger)),
        const ColonneTableau(
            cle: 'telephone', libelle: 'Téléphone', sansCoupure: true),
        ColonneTableau(
            cle: 'type',
            libelle: 'Type de don',
            texte: (r) => '${r['type'] ?? ''}',
            rendu: (_, r) =>
                BadgeSigh('${r['type'] ?? ''}', ton: TonSigh.navy)),
        ColonneTableau(
            cle: 'nbDons',
            libelle: 'Dons',
            droite: true,
            texte: (r) => '${r['nbDons'] ?? ''}',
            rendu: (_, r) => cellule('${r['nbDons'] ?? ''}', droite: true)),
        ColonneTableau(
            cle: 'dernierDon',
            libelle: 'Dernier don',
            sansCoupure: true,
            texte: (r) => dateFiche(r['dernierDon'])),
        ColonneTableau(
            cle: 'eligible',
            libelle: 'Éligibilité',
            texte: (r) => r['eligible'] == true ? 'Éligible' : 'Non éligible',
            rendu: (_, r) {
              final e = sangEligibilite(auj, r);
              return BadgeSigh(e.libelle, ton: _ton(e.ton));
            }),
      ],
      filtres: [
        FiltreTableau(
            nom: 'groupe',
            libelle: 'Groupe',
            options: [for (final g in sangGroupes) OptionChamp(g, g)]),
        FiltreTableau(
            nom: 'type',
            libelle: 'Type de don',
            options: [for (final t in sangTypesDon) OptionChamp(t, t)]),
      ],
      kpis: (ctx, rows) {
        final k = sangKpisDonneurs(auj, rows);
        return [
          KpiSigh(
              libelle: 'Donneurs enregistrés',
              valeur: nombre(k.donneurs),
              icone: LucideIcons.users,
              ton: TonSigh.navy),
          KpiSigh(
              libelle: 'Éligibles',
              valeur: nombre(k.eligibles),
              icone: LucideIcons.circleCheck,
              ton: TonSigh.succes),
          KpiSigh(
              libelle: 'Dons cumulés',
              valeur: nombre(k.dons),
              icone: LucideIcons.droplet,
              ton: TonSigh.danger),
          KpiSigh(
              libelle: 'Donneurs bénévoles',
              valeur: nombre(k.benevoles),
              icone: LucideIcons.heart,
              ton: TonSigh.info),
        ];
      },
      champs: (m) => [
        const ChampDef(
            nom: 'nom',
            libelle: 'Nom et prénoms',
            requis: true,
            col: ColChamp.plein),
        const ChampDef(
            nom: 'telephone',
            libelle: 'Téléphone',
            type: TypeChamp.tel,
            requis: true),
        ChampDef(
            nom: 'groupe',
            libelle: 'Groupe sanguin',
            type: TypeChamp.select,
            requis: true,
            options: [for (final g in sangGroupes) OptionChamp(g, g)]),
        ChampDef(
            nom: 'type',
            libelle: 'Type de don',
            type: TypeChamp.select,
            requis: true,
            options: [for (final t in sangTypesDon) OptionChamp(t, t)]),
        const ChampDef(
            nom: 'dernierDon',
            libelle: 'Date du dernier don',
            type: TypeChamp.date),
        const ChampDef(
            nom: 'nbDons',
            libelle: 'Nombre total de dons',
            type: TypeChamp.nombre),
        const ChampDef(
            nom: 'eligible',
            libelle: 'Donneur éligible',
            type: TypeChamp.case_),
      ],
      valeursInitiales: () => sangValeursInitialesDonneur(auj),
      transformer: (ctx, v) => sangFicheDonneur(v,
          existants:
              ContexteEcran.of(ctx).magasin.collection('donneurs').toutes),
      transformerExistante: (ctx, v, existante) => sangFicheDonneur(v,
          existants:
              ContexteEcran.of(ctx).magasin.collection('donneurs').toutes,
          ancienne: existante),
      referenceToast: (f) => '${f['reference'] ?? ''}',
      etat: _carte,
      titreDetail: (r) => '${r['reference'] ?? 'Détail'}',
      sousTitreDetail: (r) => '${r['reference'] ?? ''}',
      detail: (ctx, r) {
        final e = sangEligibilite(auj, r);
        return DescListeSigh([
          ('N°', Text('${r['reference'] ?? ''}', style: typographieMono)),
          ('Donneur', '${r['nom'] ?? ''}'),
          ('Groupe', BadgeSigh('${r['groupe'] ?? ''}', ton: TonSigh.danger)),
          ('Téléphone', '${r['telephone'] ?? ''}'),
          ('Type de don', BadgeSigh('${r['type'] ?? ''}', ton: TonSigh.navy)),
          ('Dons', '${r['nbDons'] ?? ''}'),
          ('Dernier don', dateFiche(r['dernierDon'])),
          ('Éligibilité', BadgeSigh(e.libelle, ton: _ton(e.ton))),
        ]);
      },
    );
  }
}
