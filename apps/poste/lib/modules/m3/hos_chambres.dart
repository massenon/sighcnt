import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/stock_commun.dart' show cellule, dateFiche;

/// `m3-chambres` — « Chambres & lits » : référentiel des lits (nomenclature A1 LIT1), tarif journalier par catégorie et occupation, qui découle
/// des admissions. Écran en lecture seule. Les règles (lits, types, occupation) sont dans `packages/domaine/lib/src/hospitalisation`.
class EcranChambres extends StatelessWidget with EcranMaquette {
  const EcranChambres({super.key});

  @override
  String get titre => 'Chambres & lits';

  @override
  String get description =>
      'Référentiel des chambres, nomenclature des lits et tarification journalière par catégorie.';

  @override
  String get regle =>
      'Écran en lecture seule. La nomenclature des lits et les tarifs par catégorie sont un référentiel : ils se modifient dans « Référentiel tarifaire » (Configuration). L’occupation, elle, découle des admissions.';

  static List<Fiche> lignes(Iterable<Fiche> admissions) => [
        for (final l in hosTousLits())
          () {
            final adm = hosLitOccupePar(l.label, admissions);
            final tarif = hosTypesChambre.firstWhere((t) => t.id == l.chambre.type).tarif;
            return <String, Object?>{
              'id': l.label.replaceAll(' ', '_'),
              'code': l.label,
              'chambre': l.chambre.code,
              'aile': l.chambre.aile,
              'type': l.chambre.type,
              'tarif': tarif,
              'statut': adm != null ? 'occupe' : 'libre',
              'occupant': adm?['patient'],
              'depuis': adm?['dateEntree'],
            };
          }()
      ];

  static void imprimer(BuildContext context, List<Fiche> rows) {
    final c = ContexteEcran.of(context);
    final occ = rows.where((r) => r['statut'] == 'occupe').length;
    afficherApercu(
        context,
        PieceA4(
            titre: 'Plan d’occupation des lits',
            sousTitre: 'Situation au ${dateFR(c.aujourdhui)}',
            cartouche: [
              ('Capacité', '${nombre(rows.length)} lits'),
              ('Occupés', nombre(occ)),
              ('Libres', nombre(rows.length - occ)),
              ('Taux d’occupation', pourcent(occ / rows.length * 100, 1)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Lit', valeur: (r) => r['code']),
                ColonneEtat(libelle: 'Chambre', valeur: (r) => r['chambre']),
                ColonneEtat(libelle: 'Aile', valeur: (r) => r['aile']),
                ColonneEtat(
                    libelle: 'Catégorie',
                    valeur: (r) => hosLibelleTypeChambre(r['type'])),
                ColonneEtat(
                    libelle: 'État',
                    valeur: (r) => r['statut'] == 'occupe' ? 'Occupé' : 'Libre'),
                ColonneEtat(libelle: 'Occupant', valeur: (r) => r['occupant'] ?? ''),
              ], lignes: rows),
            ],
            signatures: const [Signature('Le Surveillant Général', nom: 'GARBA Yahouza')],
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: c.aujourdhui));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('admissions');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = lignes(col.actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            for (final t in hosTypesChambre)
              () {
                final l = rows.where((r) => r['type'] == t.id);
                final occ = l.where((r) => r['statut'] == 'occupe').length;
                return KpiSigh(
                    libelle: 'Lits ${t.label}',
                    valeur: nombre(l.length),
                    icone: LucideIcons.bed,
                    ton: t.id == 'vvip'
                        ? TonSigh.navy
                        : (t.id == 'vip' ? TonSigh.info : TonSigh.neutre),
                    indice: '${money(t.tarif)} / jour — $occ occupé(s)');
              }(),
            KpiSigh(
                libelle: 'Capacité totale',
                valeur: nombre(rows.length),
                icone: LucideIcons.building,
                ton: TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Référentiel des lits',
            lignes: rows,
            taillePage: 20,
            nomExport: 'chambres-lits',
            filtres: [
              FiltreTableau(nom: 'type', libelle: 'Catégorie', options: [
                for (final t in hosTypesChambre) OptionChamp(t.id, t.label)
              ]),
              const FiltreTableau(nom: 'statut', libelle: 'État', options: [
                OptionChamp('libre', 'Libre'),
                OptionChamp('occupe', 'Occupé')
              ]),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'code',
                  libelle: 'Lit',
                  sansCoupure: true,
                  rendu: (_, r) => cellule('${r['code']}',
                      poids: FontWeight.w600)),
              const ColonneTableau(cle: 'chambre', libelle: 'Chambre'),
              const ColonneTableau(cle: 'aile', libelle: 'Aile / service'),
              ColonneTableau(
                  cle: 'type',
                  libelle: 'Catégorie',
                  texte: (r) => hosLibelleTypeChambre(r['type']),
                  rendu: (_, r) => BadgeSigh(hosLibelleTypeChambre(r['type']),
                      ton: r['type'] == 'standard' ? TonSigh.neutre : TonSigh.navy)),
              ColonneTableau(
                  cle: 'tarif',
                  libelle: 'Tarif / jour',
                  droite: true,
                  texte: (r) => money(r['tarif'], avecDevise: false),
                  rendu: (_, r) => cellule(money(r['tarif'], avecDevise: false),
                      droite: true)),
              ColonneTableau(
                  cle: 'statut',
                  libelle: 'État',
                  texte: (r) => r['statut'] == 'occupe' ? 'Occupé' : 'Libre',
                  rendu: (_, r) => statutBadge(r['statut'])),
              ColonneTableau(
                  cle: 'occupant',
                  libelle: 'Occupant',
                  rendu: (_, r) => cellule('${r['occupant'] ?? '—'}')),
              ColonneTableau(
                  cle: 'depuis',
                  libelle: 'Depuis',
                  texte: (r) => dateFiche(r['depuis']),
                  rendu: (_, r) => cellule(
                      r['depuis'] == null ? '—' : dateFiche(r['depuis']))),
            ],
            actions: [
              BoutonSigh(
                  libelle: 'Imprimer le plan',
                  icone: LucideIcons.printer,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => imprimer(context, rows)),
            ],
          ),
        ]);
      },
    );
  }
}
