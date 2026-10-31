import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';
import 'pai_pieces.dart';

/// `m11-bulletins` — « Bulletins de paie » : le registre des bulletins GÉNÉRÉS, en lecture seule (`readonly: true` de la maquette) — ils sont produits par le
/// moteur de calcul, une correction passe par la reprise du calcul de la période. Aucune commande « Nouveau », « Modifier » ni « Archiver » (ce que
/// `readonly` retire dans la maquette, pour TOUS les profils : un bulletin émis ne se réécrit ni ne s'efface). Le détail ORTB et les participations imputées voyagent avec le bulletin stocké (E682).
class EcranBulletins extends StatelessWidget with EcranMaquette {
  const EcranBulletins({super.key});

  @override
  String get titre => 'Bulletins de paie';

  @override
  String get description => 'Bulletins générés, statut de validation et édition avec l’entête officielle de la clinique.';

  static (String, TonSigh) statut(Object? s) => switch ('$s') {
        'a_valider' => ('À valider', TonSigh.attention),
        'valide' => ('Validé', TonSigh.succes),
        'diffuse' => ('Diffusé', TonSigh.navy),
        _ => ('—', TonSigh.neutre),
      };

  Widget _detail(Fiche b) {
    final v = vueDeFiche(b);
    ColonneMini col(String lib, String k, {bool droite = false}) => ColonneMini(lib, (r) => '${r[k] ?? ''}', droite: droite);
    String mf(num x) => money(x, avecDevise: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(colonnes: 2, kpis: [
        KpiSigh(libelle: 'Salaire brut', valeur: money(v.brut), icone: LucideIcons.banknote),
        KpiSigh(libelle: 'Net à payer', valeur: money(v.net), icone: LucideIcons.wallet, ton: TonSigh.succes),
      ]),
      const SizedBox(height: 16),
      DescListeSigh([
        ('Référence', v.reference),
        ('Période', v.periode),
        ('Agent', v.employe),
        ('Matricule', v.matricule),
        ('Fonction', paiFonctionLibelle(v.fonction)),
        ('Service', v.service),
        ('Catégorie', v.categorie),
        ('N° CNSS', v.cnss),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Gains',
          child: MiniTableauSigh(colonnes: [
            col('Rubrique', 'k'),
            col('Montant', 'm', droite: true)
          ], lignes: [
            {'k': 'Salaire de base', 'm': mf(v.salaireBase)},
            {'k': 'Prime d’ancienneté', 'm': mf(v.primeAnciennete)},
            {'k': 'Primes NS 132', 'm': mf(v.totalPrimes)},
            if (v.heuresSupMontant != 0) {'k': 'Heures supplémentaires', 'm': mf(v.heuresSupMontant)},
            {'k': 'TOTAL BRUT', 'm': mf(v.brut)},
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Retenues',
          child: MiniTableauSigh(colonnes: [
            col('Rubrique', 'k'),
            col('Montant', 'm', droite: true)
          ], lignes: [
            if (v.sanction != 0) {'k': 'Sanction NS 131 (${paiNum(v.pctSanction)} %)', 'm': mf(v.sanction)},
            {'k': 'CNSS part ouvrière', 'm': mf(v.cnssOuvriere)},
            {'k': 'ITS', 'm': mf(v.its)},
            for (final l in paiLignesOrtb(v.detailOrtb)) {'k': l.libelle, 'm': l.montant},
            if (v.avances != 0) {'k': 'Avance sur salaire', 'm': mf(v.avances)},
            if (v.prets != 0) {'k': 'Échéance de prêt', 'm': mf(v.prets)},
            if (v.participations != 0) {'k': 'Participation aux événements', 'm': mf(v.participations)},
          ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return CrudSigh(
      collection: c.magasin.collection('bulletins'),
      entite: 'bulletin',
      entiteP: 'bulletins',
      taillePage: 15,
      readonly: true,
      triInitial: 'periode',
      sensInitial: 'desc',
      intro: (_) => const NoteSigh(
          'Les bulletins sont produits par le moteur de calcul : ils ne sont pas modifiables directement. Toute correction passe par la reprise du calcul de la période.',
          ton: TonSigh.info),
      kpis: (rows) => [
        KpiSigh(libelle: 'Bulletins générés', valeur: nombre(rows.length), icone: LucideIcons.fileText),
        KpiSigh(libelle: 'Masse salariale brute', valeur: money(rows.fold<num>(0, (a, b) => a + n(b['brut']))), icone: LucideIcons.banknote, ton: TonSigh.info),
        KpiSigh(libelle: 'Net à payer', valeur: money(rows.fold<num>(0, (a, b) => a + n(b['net']))), icone: LucideIcons.wallet, ton: TonSigh.succes),
        KpiSigh(
            libelle: 'En attente de validation',
            valeur: nombre(rows.where((b) => b['statutBulletin'] == 'a_valider').length),
            icone: LucideIcons.hourglass,
            ton: TonSigh.attention),
      ],
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, b) => monoTexte(b['reference'])),
        const ColonneTableau(cle: 'periode', libelle: 'Période', sansCoupure: true),
        const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
        const ColonneTableau(cle: 'employe', libelle: 'Agent'),
        const ColonneTableau(cle: 'service', libelle: 'Service'),
        ColonneTableau(cle: 'brut', libelle: 'Brut', droite: true, texte: (b) => m(b['brut']), rendu: (_, b) => cellMontant(n(b['brut']))),
        ColonneTableau(
            cle: 'sanction',
            libelle: 'Sanction',
            droite: true,
            texte: (b) => m(n(b['sanction'])),
            rendu: (_, b) => n(b['sanction']) != 0 ? cellTexte('− ${m(b['sanction'])}', couleur: JetonsShell.danger600) : cellTexte('—')),
        ColonneTableau(cle: 'totalRetenues', libelle: 'Retenues', droite: true, texte: (b) => m(b['totalRetenues']), rendu: (_, b) => cellMontant(n(b['totalRetenues']))),
        ColonneTableau(cle: 'net', libelle: 'Net à payer', droite: true, texte: (b) => m(b['net']), rendu: (_, b) => cellTexte(m(b['net']), couleur: JetonsShell.navy900, poids: FontWeight.w700)),
        ColonneTableau(
            cle: 'statutBulletin',
            libelle: 'Statut',
            texte: (b) => statut(b['statutBulletin']).$1,
            rendu: (_, b) {
              final s = statut(b['statutBulletin']);
              return BadgeSigh(s.$1, ton: s.$2);
            }),
      ],
      filtres: [
        FiltreTableau(nom: 'periode', libelle: 'Période', options: [for (var i = 0; i < 12; i++) OptionChamp(paiPeriodeLibelle(paiAnnee, i))]),
        FiltreTableau(nom: 'service', libelle: 'Service', options: [for (final s in paiServices) OptionChamp(s)]),
        const FiltreTableau(nom: 'statutBulletin', libelle: 'Statut', options: [
          OptionChamp('a_valider', 'À valider'),
          OptionChamp('valide', 'Validé'),
          OptionChamp('diffuse', 'Diffusé'),
        ]),
      ],
      detail: _detail,
      titreDetail: (b) => '${b['reference']}',
      sousTitreDetail: (b) => '${b['reference']}',
      etat: (ctx, b) => imprimerBulletin(ctx, vueDeFiche(b)),
    );
  }
}
