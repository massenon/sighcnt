import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/stock_commun.dart' show cellule, dateFiche, typographieMono;

/// `m5-banque-sang` — « Banque de sang » : poches par groupe, dates de péremption, disponibilité par groupe et bon de demande de sang.
///
/// Une poche est DISPONIBLE si elle n'est ni périmée ni réservée. Les indicateurs lisent l'ÉTAT enregistré de la poche (`actif` / `alerte` /
/// `perime`), pas sa date : corriger une date de péremption ne recalcule pas l'état (écart E201, porté fidèlement et signalé). La colonne « Reste »,
/// elle, se calcule à la date du jour.
///
/// La banque de sang est une activité FERMÉE à la clinique dans la maquette (`modulesActifs`, motif « La clinique ne pratique pas la banque de
/// sang ») : l'écran est porté tel quel ; le mécanisme de fermeture d'activité n'est pas porté ici (il appartient à `cfg-modules`). Les poches ne sont
/// pas semées : la maquette ne les amorce qu'à l'ouverture de l'écran, donc le jeu n'en contient pas.
class EcranBanqueSang extends StatelessWidget with EcranMaquette {
  const EcranBanqueSang({super.key});

  @override
  String get titre => 'Banque de sang';

  @override
  String get description =>
      'Gestion des poches de sang par groupe, dates de péremption et demandes de transfusion.';

  static List<ChampDef> get _champs => [
        ChampDef(
            nom: 'groupe',
            libelle: 'Groupe sanguin',
            type: TypeChamp.select,
            requis: true,
            options: [for (final g in sangGroupes) OptionChamp(g, g)]),
        const ChampDef(nom: 'volume', libelle: 'Volume (ml)', type: TypeChamp.nombre),
        const ChampDef(
            nom: 'datePrelevement',
            libelle: 'Date de prélèvement',
            type: TypeChamp.date),
        const ChampDef(
            nom: 'datePeremption',
            libelle: 'Date de péremption',
            type: TypeChamp.date,
            requis: true),
        const ChampDef(nom: 'donneur', libelle: 'Donneur'),
        const ChampDef(
            nom: 'observations',
            libelle: 'Observations',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
      ];

  static Map<String, Object?> _enTexte(Fiche f) => {
        for (final e in f.entries) e.key: e.value is num ? '${e.value}' : e.value
      };

  /// `modifier(col, champs, record)` de `K.actionsLigne` : « Modifier l’enregistrement », refus du formulaire incomplet, annulation visible.
  void _modifier(BuildContext ctx, CollectionMagasin col, Fiche poche) {
    final ctl = ControleurFormulaire(_champs, _enTexte(poche));
    afficherModale<void>(ctx,
        titre: 'Modifier l’enregistrement',
        sousTitre: '${poche['reference'] ?? poche['id']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final annuler =
                        col.mettreAJour(poche['id'], sangFichePoche(saisie));
                    fermer();
                    ToastsSigh.afficher(ctx, 'Modifications enregistrées.',
                        type: TypeToast.succes, annuler: annuler);
                  }),
            ]);
  }

  void _archiver(BuildContext ctx, CollectionMagasin col, Fiche poche) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver cet enregistrement ?',
        message:
            'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = col.archiver(poche['id']);
    ToastsSigh.afficher(ctx, 'Enregistrement archivé.',
        type: TypeToast.succes, annuler: annuler);
  }

  /// `Bon de demande de sang` : la pièce à remplir par le prescripteur, avec la disponibilité du jour.
  void _bon(BuildContext ctx, List<Fiche> poches) {
    final c = ContexteEcran.of(ctx);
    final auj = c.aujourdhui;
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'Bon de demande de sang',
            cartouche: [
              ('Service demandeur', ''),
              ('Date', dateFR(auj)),
              ('Patient', ''),
              ('Groupe requis', ''),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Groupe sanguin', valeur: (_) => ''),
                ColonneEtat(
                    libelle: 'Nombre de poches demandées', valeur: (_) => ''),
                ColonneEtat(libelle: 'Indication', valeur: (_) => ''),
              ], lignes: const [{}, {}])),
              BlocTexte(
                  'Disponibilité au ${dateFR(auj)} : ${sangLigneDisponibilite(poches)}'),
            ],
            signatures: const [
              Signature('Le Médecin prescripteur'),
              Signature('Le Laborantin', nom: 'KINNOU Addoul Ganiou'),
              Signature('Le Directeur Médical', mention: 'Agrément'),
            ],
            reference:
                PieceA4.reference_(auj, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: auj));
  }

  Widget _carteGroupe(String groupe, int dispo) {
    final ton = switch (sangTonGroupe(dispo)) {
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      _ => TonSigh.succes,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ton.bordure200),
          boxShadow: JetonsShell.ombreCarte),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(groupe,
            style: TextStyle(
                color: ton.texteBadge,
                fontSize: 18,
                height: 28 / 18,
                fontWeight: FontWeight.w700)),
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$dispo',
                style: const TextStyle(
                    color: JetonsShell.slate900,
                    fontSize: 24,
                    height: 32 / 24,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()]))),
        Text(sangMotPoche(dispo),
            style: const TextStyle(
                color: JetonsShell.slate400, fontSize: 10, height: 14 / 10)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('poches');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final poches = col.actives;
        final k = sangKpisBanque(poches);
        final auj = c.aujourdhui;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Poches en stock',
                    valeur: nombre(k.enStock),
                    icone: LucideIcons.droplet,
                    ton: TonSigh.navy),
                KpiSigh(
                    libelle: 'Disponibles',
                    valeur: nombre(k.disponibles),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Péremption sous 7 jours',
                    valeur: nombre(k.alerte),
                    icone: LucideIcons.clock,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Périmées à détruire',
                    valeur: nombre(k.perimees),
                    icone: LucideIcons.trash2,
                    ton: TonSigh.danger),
              ]),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Disponibilité par groupe sanguin',
                  actions: [
                    BoutonSigh(
                        libelle: 'Bon de demande de sang',
                        icone: LucideIcons.printer,
                        taille: TailleBouton.sm,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => _bon(context, poches)),
                  ],
                  child: LayoutBuilder(builder: (_, w) {
                    final n = w.maxWidth >= 1024 ? 8 : (w.maxWidth >= 640 ? 4 : 2);
                    final l = (w.maxWidth - 12 * (n - 1)) / n;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final g in sangGroupes)
                        SizedBox(
                            width: l,
                            child: _carteGroupe(
                                g, sangDisponiblesGroupe(poches, g))),
                    ]);
                  })),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Poches de sang',
                lignes: poches,
                taillePage: 15,
                nomExport: 'banque-sang',
                triInitial: 'datePeremption',
                filtres: [
                  FiltreTableau(
                      nom: 'groupe',
                      libelle: 'Groupe',
                      options: [for (final g in sangGroupes) OptionChamp(g, g)]),
                  const FiltreTableau(
                      nom: 'etat',
                      libelle: 'État',
                      options: [
                        OptionChamp('actif', 'Disponible'),
                        OptionChamp('alerte', 'Péremption proche'),
                        OptionChamp('perime', 'Périmée'),
                      ]),
                ],
                actionsLigne: (ctx, p) => [
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier',
                        onPressed: () => _modifier(context, col, p)),
                  if (c.droit.annuler)
                    BoutonIcone(
                        icone: LucideIcons.archive,
                        libelle: 'Archiver',
                        onPressed: () => _archiver(context, col, p)),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° poche',
                      sansCoupure: true,
                      texte: (p) => '${p['reference'] ?? ''}',
                      rendu: (_, p) => Text('${p['reference'] ?? ''}',
                          style: typographieMono)),
                  ColonneTableau(
                      cle: 'groupe',
                      libelle: 'Groupe',
                      texte: (p) => '${p['groupe'] ?? ''}',
                      rendu: (_, p) =>
                          BadgeSigh('${p['groupe'] ?? ''}', ton: TonSigh.danger)),
                  ColonneTableau(
                      cle: 'volume',
                      libelle: 'Volume',
                      droite: true,
                      texte: (p) => '${p['volume'] ?? ''} ml',
                      rendu: (_, p) =>
                          cellule('${p['volume'] ?? ''} ml', droite: true)),
                  ColonneTableau(
                      cle: 'datePrelevement',
                      libelle: 'Prélèvement',
                      sansCoupure: true,
                      texte: (p) => dateFiche(p['datePrelevement'])),
                  ColonneTableau(
                      cle: 'datePeremption',
                      libelle: 'Péremption',
                      sansCoupure: true,
                      texte: (p) => dateFiche(p['datePeremption'])),
                  ColonneTableau(
                      cle: 'restant',
                      libelle: 'Reste',
                      droite: true,
                      valeur: (p) => sangResteJours(auj, p),
                      texte: (p) {
                        final j = sangResteJours(auj, p);
                        return j == null ? '—' : (j < 0 ? 'Périmée' : '$j j');
                      },
                      rendu: (_, p) {
                        final j = sangResteJours(auj, p);
                        if (j == null) return cellule('—', droite: true);
                        if (j < 0) {
                          return const BadgeSigh('Périmée', ton: TonSigh.danger);
                        }
                        return cellule('$j j',
                            droite: true,
                            couleur: j < sangResteOrange
                                ? JetonsShell.warning600
                                : JetonsShell.slate700,
                            poids: j < sangResteOrange
                                ? FontWeight.w600
                                : FontWeight.w400);
                      }),
                  const ColonneTableau(cle: 'donneur', libelle: 'Donneur'),
                  ColonneTableau(
                      cle: 'reserve',
                      libelle: 'Réservée',
                      texte: (p) => p['reserve'] == true ? 'Oui' : 'Non',
                      rendu: (_, p) => p['reserve'] == true
                          ? const BadgeSigh('Réservée', ton: TonSigh.attention)
                          : const Text('—',
                              style: TextStyle(
                                  color: JetonsShell.slate400,
                                  fontSize: 12,
                                  height: 16 / 12))),
                ],
              ),
            ]);
      },
    );
  }
}
