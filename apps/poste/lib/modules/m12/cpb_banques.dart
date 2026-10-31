import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cpb_commun.dart';

/// `m12-banques` — « Banques & rapprochements » : les comptes de trésorerie de la clinique (référentiel administrable — ouvrir un compte n'attend pas une
/// livraison logicielle) et les états de rapprochement avec la comptabilité. Un compte s'ARCHIVE, il ne se supprime pas (RG-14) ; « Nouveau » et
/// « Modifier » exigent le droit d'écrire, « Archiver » le droit d'annuler — sinon la commande est ABSENTE.
///
/// Écart E775 : le filtre « Banque » des rapprochements propose les NOMS DES COMPTES de trésorerie (Caisse, BOA, Orabank…) alors que les rapprochements
/// portent d'autres libellés (« ECOBANK Bénin », « Bank Of Africa Bénin »…) : choisir une banque ne retrouve AUCUN rapprochement. Porté fidèlement et dit ;
/// à trancher (aligner les libellés, ou lier le rapprochement au compte).
/// Écart E780 : les rapprochements du jeu sont amorcés par l'écran (aucune saisie de rapprochement n'existe) ; l'écran les LIT et les imprime.
class EcranBanques extends StatefulWidget with EcranMaquette {
  const EcranBanques({super.key});

  @override
  String get titre => 'Banques & rapprochements';

  @override
  String get description => 'Comptes bancaires, relevés et rapprochement avec la comptabilité.';

  @override
  State<EcranBanques> createState() => _EtatBanques();
}

class _EtatBanques extends State<EcranBanques> {
  static List<ChampDef> _champs() => const [
        ChampDef(nom: 'banque', libelle: 'Établissement bancaire', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'intitule', libelle: 'Intitulé du compte', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'numeroCompte', libelle: 'Numéro de compte', requis: true),
        ChampDef(
            nom: 'compteComptable',
            libelle: 'Compte comptable (SYSCOHADA)',
            requis: true,
            aide: 'Classe 52 — banques. Sert à l’imputation automatique des mouvements.'),
        ChampDef(nom: 'devise', libelle: 'Devise', type: TypeChamp.select, options: [OptionChamp('FCFA'), OptionChamp('EUR'), OptionChamp('USD')]),
        ChampDef(
            nom: 'statutCompte',
            libelle: 'État du compte',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp('actif', 'Actif'), OptionChamp('cloture', 'Clôturé')]),
      ];

  void _formulaire(BuildContext ctx, Fiche? record) {
    final col = ContexteEcran.of(ctx).magasin.collection('banques');
    final edition = record != null;
    final champs = _champs();
    final initial = edition
        ? {for (final k in champs) k.nom: '${record[k.nom] ?? ''}'}
        : <String, Object?>{'devise': 'FCFA', 'statutCompte': 'actif', 'compteComptable': '521'};
    final ctl = ControleurFormulaire(champs, initial);
    afficherModale<void>(ctx,
        titre: edition ? 'Modifier l’enregistrement' : 'Nouveau compte bancaire',
        sousTitre: edition ? '${record['banque']}' : 'Les champs marqués d’un astérisque sont obligatoires.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: edition ? 'Enregistrer' : 'Créer',
                  icone: edition ? LucideIcons.save : LucideIcons.plus,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final VoidCallback annuler;
                    if (edition) {
                      annuler = col.mettreAJour(record['id'], saisie);
                    } else {
                      annuler = col.inserer({...saisie, 'statut': 'actif'}, prefixe: 'BQ').annuler;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, edition ? 'Modifications enregistrées.' : 'Compte créé.', type: TypeToast.succes, annuler: annuler);
                  }),
            ]);
  }

  /// Archivage AVEC MOTIF, journalisé (RG-12), annulable et visible ; rien n'est supprimé (RG-14).
  Future<void> _archiver(BuildContext ctx, Fiche f) async {
    final c = ContexteEcran.of(ctx);
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver cet enregistrement ?',
        message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = c.magasin.collection('banques').archiver(f['id']);
    c.magasin.journaliser('Motif d’archivage', 'M12', 'compte bancaire', '${f['banque']}', null, {'motif': motif});
    ToastsSigh.afficher(ctx, 'Enregistrement archivé.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
  }

  static void _imprimerRapprochement(BuildContext ctx, ContexteEcran c, Fiche r) {
    final ecart = n(r['ecart']).toDouble();
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'État de rapprochement bancaire',
            sousTitre: '${r['banque']} — ${r['periode']}',
            cartouche: [
              ('Banque', '${r['banque']}'),
              ('Compte comptable', '${r['compte']}'),
              ('Période', '${r['periode']}'),
              ('Référence', '${r['reference']}'),
              ('Effectué par', '${r['operateur']}'),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
                ColonneEtat(libelle: 'Montant', droite: true, valeur: (x) => x['v']),
              ], lignes: [
                {'k': 'Solde du compte en comptabilité', 'v': m(r['soldeComptable'])},
                {'k': 'Solde du relevé bancaire', 'v': m(r['soldeReleve'])},
                {'k': 'ÉCART CONSTATÉ', 'v': m(r['ecart'])},
              ])),
              BlocTexte(cpbPhraseRapprochement(ecart), italique: true),
            ],
            signatures: [Signature('Le Comptable', nom: '${r['operateur']}'), signDafCompta]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.magasin.collection('banques'), c.magasin.collection('rapprochements')]),
      builder: (context, _) {
        final banques = c.magasin.collection('banques').actives;
        final rapp = c.magasin.collection('rapprochements').actives;
        final b = cpbBilanRapprochements(rapp);
        final nomsBanques = [for (final x in banques) '${x['banque']}'];
        return pile([
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Comptes bancaires', valeur: nombre(banques.length), icone: LucideIcons.landmark, ton: TonSigh.navy),
            KpiSigh(libelle: 'Rapprochements effectués', valeur: nombre(b.effectues), icone: LucideIcons.circleCheck, ton: TonSigh.info),
            KpiSigh(libelle: 'Sans écart', valeur: nombre(b.sansEcart), icone: LucideIcons.scale, ton: TonSigh.succes),
            KpiSigh(libelle: 'Avec écart', valeur: nombre(b.avecEcart), icone: LucideIcons.scale3d, ton: TonSigh.danger),
          ]),
          TableauSigh(
            key: const ValueKey('comptes-bancaires'),
            titre: 'Comptes bancaires de la clinique',
            lignes: banques,
            nomExport: 'comptes-bancaires',
            taillePage: 10,
            messageVide: 'Aucun compte bancaire enregistré.',
            actions: [
              if (c.droit.editer) BoutonSigh(libelle: 'Nouveau', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _formulaire(context, null)),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'banque',
                  libelle: 'Établissement',
                  texte: (x) => '${x['banque']}',
                  rendu: (_, x) => Text('${x['banque']}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500))),
              const ColonneTableau(cle: 'intitule', libelle: 'Intitulé du compte'),
              ColonneTableau(
                  cle: 'numeroCompte',
                  libelle: 'N° de compte',
                  sansCoupure: true,
                  texte: (x) => '${x['numeroCompte'] ?? ''}',
                  rendu: (_, x) => Text('${x['numeroCompte'] ?? ''}', style: mono)),
              ColonneTableau(
                  cle: 'compteComptable',
                  libelle: 'Compte SYSCOHADA',
                  sansCoupure: true,
                  texte: (x) => '${x['compteComptable']}',
                  rendu: (_, x) => BadgeSigh('${x['compteComptable']}', ton: TonSigh.navy)),
              const ColonneTableau(cle: 'devise', libelle: 'Devise', sansCoupure: true),
              ColonneTableau(
                  cle: 'statutCompte',
                  libelle: 'État',
                  texte: (x) => x['statutCompte'] == 'actif' ? 'Actif' : 'Clôturé',
                  rendu: (_, x) => x['statutCompte'] == 'actif' ? const BadgeSigh('Actif', ton: TonSigh.succes) : const BadgeSigh('Clôturé')),
            ],
            // Modifier : droit d'écrire ; Archiver : droit d'annuler — la commande interdite est ABSENTE.
            actionsLigne: (ctx, x) => [
              if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _formulaire(ctx, x)),
              if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(ctx, x)),
            ],
          ),
          TableauSigh(
            key: const ValueKey('rapprochements'),
            titre: 'États de rapprochement bancaire',
            lignes: rapp,
            nomExport: 'rapprochements',
            taillePage: 15,
            triInitial: 'periode',
            sensInitial: 'desc',
            filtres: [
              FiltreTableau(nom: 'banque', libelle: 'Banque', options: [for (final x in nomsBanques) OptionChamp(x)]),
              const FiltreTableau(nom: 'statutRappro', libelle: 'Résultat', options: [OptionChamp('rapproche', 'Sans écart'), OptionChamp('ecart', 'Avec écart')]),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'reference',
                  libelle: 'N°',
                  sansCoupure: true,
                  texte: (r) => '${r['reference']}',
                  rendu: (_, r) => Text('${r['reference']}', style: mono)),
              const ColonneTableau(cle: 'banque', libelle: 'Banque'),
              ColonneTableau(cle: 'compte', libelle: 'Compte', sansCoupure: true, texte: (r) => '${r['compte']}', rendu: (_, r) => Text('${r['compte']}', style: mono)),
              const ColonneTableau(cle: 'periode', libelle: 'Période', sansCoupure: true),
              ColonneTableau(cle: 'soldeComptable', libelle: 'Solde comptable', droite: true, texte: (r) => m(r['soldeComptable'])),
              ColonneTableau(cle: 'soldeReleve', libelle: 'Solde relevé', droite: true, texte: (r) => m(r['soldeReleve'])),
              ColonneTableau(
                  cle: 'ecart',
                  libelle: 'Écart',
                  droite: true,
                  texte: (r) => m(r['ecart']),
                  rendu: (_, r) => n(r['ecart']) == 0
                      ? const BadgeSigh('Rapproché', ton: TonSigh.succes)
                      : Text('${n(r['ecart']) > 0 ? '+' : ''}${m(r['ecart'])}',
                          style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
              const ColonneTableau(cle: 'operateur', libelle: 'Effectué par'),
            ],
            actionsLigne: (ctx, r) => [
              BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer l’état', onPressed: () => _imprimerRapprochement(ctx, c, r)),
            ],
          ),
        ]);
      },
    );
  }
}
