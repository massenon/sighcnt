import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rap_commun.dart';

/// `rapports-bibliotheque` — « Bibliothèque des états » : le catalogue de tous les états et rapports éditables (CDCT §21), chacun avec l'accès direct à
/// l'écran qui sait le produire, plus les mentions de l'en-tête officiel UNIQUE et le pied de page normalisé.
///
/// La bibliothèque IMPRIME sans rien écrire : elle reste ouverte à tous les profils (vague 67 — le catalogue n'a aucune écriture). Les trois écrans qui
/// PRODUISENT (États de la Direction, générateur, historique) sont fermés aux rôles qui n'écrivent pas, par la matrice.
class EcranRapBibliotheque extends StatelessWidget with EcranMaquette {
  const EcranRapBibliotheque({super.key});

  @override
  String get titre => 'Bibliothèque des états';

  @override
  String get description =>
      'Catalogue de tous les états et rapports éditables par le système, avec accès direct à l’écran producteur.';

  @override
  String get regle =>
      'Tous les états reprennent automatiquement le papier à en-tête officiel de la clinique : logo, dénomination, adresse, téléphones, autorisation d’ouverture, IFU et RCCM, ainsi qu’un pied de page normalisé (pagination, date et heure d’impression, utilisateur générateur, identifiant unique).';

  @override
  Widget build(BuildContext context) {
    final st = rapStatsBibliotheque();
    final cat = rapCatalogue();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'États au catalogue',
            valeur: nombre(st.etats),
            icone: LucideIcons.library,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Domaines couverts',
            valeur: nombre(st.domaines),
            icone: LucideIcons.layers,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Éditables dans le prototype',
            valeur: nombre(st.editables),
            icone: LucideIcons.printer,
            ton: TonSigh.succes),
        const KpiSigh(
            libelle: 'Modèle d’entête',
            valeur: 'Unique',
            icone: LucideIcons.fileBadge,
            ton: TonSigh.neutre,
            indice: 'Brand Configuration Center'),
      ]),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, k) {
        final mentions = _Mentions(
            onModifier: () => rapOuvrir(context, 'cfg-branding',
                libelle: 'Paramètres d’identité'));
        final pied = CarteSigh(
            titre: 'Pied de page normalisé',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, t) in rapMentionsPied.indexed)
                    Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(LucideIcons.check,
                                      size: 14, color: Color(0xFF16A34A))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(t,
                                      style: const TextStyle(
                                          color: JetonsShell.slate600,
                                          fontSize: 12,
                                          height: 16 / 12))),
                            ])),
                ]));
        if (k.maxWidth < 1024) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [mentions, const SizedBox(height: 16), pied]);
        }
        final unite = (k.maxWidth - 32) / 3;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: unite * 2 + 16, child: mentions),
          const SizedBox(width: 16),
          SizedBox(width: unite, child: pied),
        ]);
      }),
      for (final (dom, etats) in rapCatalogueEtats) ...[
        const SizedBox(height: 16),
        CarteSigh(
            titre: '$dom — ${etats.length} état(s)',
            child: RapGrille(enfants: [
              for (final e in cat
                  .where((x) => x.domaine == dom && etats.contains(x.etat)))
                _Tuile(e),
            ])),
      ],
    ]);
  }
}

class _Mentions extends StatelessWidget {
  const _Mentions({required this.onModifier});
  final VoidCallback onModifier;

  @override
  Widget build(BuildContext context) => CarteSigh(
      titre: 'Mentions portées sur tous les états',
      actions: [
        BoutonSigh(
            libelle: 'Modifier l’identité',
            icone: LucideIcons.settings,
            variante: VarianteBouton.secondaire,
            taille: TailleBouton.sm,
            onPressed: onModifier),
      ],
      child: DescListeSigh([
        ('Dénomination', IdentiteClinique.nom),
        ('Adresse postale', IdentiteClinique.bp),
        ('Téléphones', IdentiteClinique.telephones.join('  /  ')),
        ('Adresse électronique', IdentiteClinique.email),
        ('Autorisation d’ouverture', IdentiteClinique.autorisation),
        (
          'IFU',
          Text(IdentiteClinique.ifu,
              style: rapMono.copyWith(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600,
                  color: JetonsShell.slate900))
        ),
        (
          'RCCM',
          Text(IdentiteClinique.rccm,
              style: rapMono.copyWith(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600,
                  color: JetonsShell.slate900))
        ),
        ('Devise', devise),
      ]));
}

/// Un état du catalogue : pastille, intitulé et « Éditer » (écran producteur) ou « À venir ».
class _Tuile extends StatelessWidget {
  const _Tuile(this.e);
  final RapEtat e;

  @override
  Widget build(BuildContext context) {
    final ok = e.disponible;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JetonsShell.slate200)),
      child: Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: ok ? TonSigh.succes.fond50 : JetonsShell.slate100,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(ok ? LucideIcons.printer : LucideIcons.file,
                size: 16,
                color: ok ? TonSigh.succes.icone600 : JetonsShell.slate400)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(e.etat,
                style: const TextStyle(
                    color: JetonsShell.slate700,
                    fontSize: 14,
                    height: 20 / 14))),
        const SizedBox(width: 12),
        if (ok)
          BoutonSigh(
              libelle: 'Éditer',
              variante: VarianteBouton.secondaire,
              taille: TailleBouton.sm,
              onPressed: () => rapOuvrir(context, e.ecran!, libelle: e.etat))
        else
          const BadgeSigh('À venir'),
      ]),
    );
  }
}
