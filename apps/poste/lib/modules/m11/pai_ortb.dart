import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';

/// `m11-ortb` — « Redevance ORTB » : DEUX redevances qui SE CUMULENT (Direction, 20/08/2026) — Radio 1 000 F, tous les salariés sans exception, en mars ;
/// Télé 3 000 F, salaire brut supérieur à 60 000 F, en juin, EN SUS. Un agent au-dessus du seuil acquitte donc 4 000 F sur l'exercice. L'écran montre,
/// agent par agent, la part radio, la part télé, ce qui est déjà prélevé et ce qui reste à prélever — la question du comptable au moment de reverser.
/// Chacune n'apparaît que sur le bulletin de son mois : les porter chaque mois majorerait les retenues de onze douzièmes.
class EcranOrtb extends StatefulWidget with EcranMaquette {
  const EcranOrtb({super.key});

  @override
  String get titre => 'Redevance ORTB';

  @override
  String get description =>
      'Redevances audiovisuelles prélevées sur les salaires : catégorie Radio et catégorie Télé, mois de prélèvement et suivi de l’exercice.';

  @override
  String get regle =>
      'Deux redevances distinctes qui se cumulent : ORTB Radio, 1 000 F, tous les salariés sans exception, prélevés en mars ; ORTB Télé, 3 000 F, salaire brut supérieur à 60 000 F, prélevés en juin, en sus de la radio. Un agent au-dessus du seuil acquitte donc 4 000 F sur l’exercice. Chacune n’apparaît que sur le bulletin de son mois — les porter chaque mois majorerait les retenues de onze douzièmes.';

  @override
  State<EcranOrtb> createState() => _EtatOrtb();
}

class _EtatOrtb extends State<EcranOrtb> {
  ControleurFormulaire? _mois;

  static final _radio = paiRedevances.firstWhere((r) => r.id == 'radio');
  static final _tele = paiRedevances.firstWhere((r) => r.id == 'tele');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mois != null) return;
    _mois = selecteurMois(ContexteEcran.of(context), 'Mois de paie', optionsMoisBrut(paiAnnee));
    _mois!.addListener(_maj);
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mois?.removeListener(_maj);
    _mois?.dispose();
    super.dispose();
  }

  int get _m => moisChoisi(_mois!);

  List<PaiLigneOrtbAgent> _lignes(ContexteEcran c) =>
      paiLignesOrtbAgents(c.magasin.collection('personnel').actives, paiAnnee, _m, entreesPaie(c.magasin), c.aujourdhui);

  static Map<String, Object?> _ligne(PaiLigneOrtbAgent r) => {
        'id': r.id,
        'matricule': r.matricule,
        'agent': r.agent,
        'poste': r.poste,
        'brut': r.brut,
        'radio': r.radio,
        'tele': r.tele,
        'categorie': r.categorie,
        'totalAnnuel': r.totalAnnuel,
        'duCeMois': r.duCeMois,
        'prelevee': r.prelevee,
        'aPrelever': r.aPrelever,
        '_r': r,
      };

  static PaiLigneOrtbAgent _r(Map<String, Object?> l) => l['_r'] as PaiLigneOrtbAgent;
  static String _mf(num v) => money(v, avecDevise: false);

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final rows = trierPar(_lignes(c).where((r) => r.categorie != 'aucune').toList(), (r) => r.agent);
    num somme(num Function(PaiLigneOrtbAgent) f) => rows.fold<num>(0, (a, r) => a + f(r));
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'État des redevances ORTB',
            sousTitre: '${paiMois[_m]} $paiAnnee',
            cartouche: [
              ('Période', '${paiMois[_m]} $paiAnnee'),
              ('Agents redevables', nombre(rows.length)),
              ('ORTB Radio', '${nombre(rows.where((r) => r.radio > 0).length)} agents — ${_mf(_radio.montant)} en ${_radio.moisLabel}'),
              ('ORTB Télé', '${nombre(rows.where((r) => r.tele > 0).length)} agents — ${_mf(_tele.montant)} en ${_tele.moisLabel}'),
              ('Dû sur le mois', money(somme((r) => r.duCeMois))),
              ('Total de l’exercice', money(somme((r) => r.totalAnnuel))),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Matricule', valeur: (r) => r['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['agent']),
                // On ne totalise PAS le salaire brut : ce n'est pas une redevance, et un total de bruts sur un état ORTB se lirait comme un montant dû.
                ColonneEtat(libelle: 'Salaire brut', droite: true, valeur: (r) => _mf(n(r['brut']))),
                ColonneEtat(libelle: 'ORTB Radio', droite: true, valeur: (r) => n(r['radio']) != 0 ? _mf(n(r['radio'])) : '—', somme: (r) => n(r['radio'])),
                ColonneEtat(libelle: 'ORTB Télé', droite: true, valeur: (r) => n(r['tele']) != 0 ? _mf(n(r['tele'])) : '—', somme: (r) => n(r['tele'])),
                ColonneEtat(libelle: 'Total annuel', droite: true, valeur: (r) => _mf(n(r['totalAnnuel'])), somme: (r) => n(r['totalAnnuel'])),
                ColonneEtat(libelle: 'Dû ce mois', droite: true, valeur: (r) => n(r['duCeMois']) != 0 ? _mf(n(r['duCeMois'])) : '—', somme: (r) => n(r['duCeMois'])),
              ], lignes: [
                for (final r in rows) _ligne(r)
              ], libelleTotal: 'TOTAL')
            ],
            signatures: const [signComptable, signDaf]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoutePaie(c),
      builder: (context, _) {
        final rows = _lignes(c);
        final avecTele = rows.where((r) => r.tele > 0).toList();
        final duCeMois = rows.fold<num>(0, (a, r) => a + r.duCeMois);
        final totalExercice = rows.fold<num>(0, (a, r) => a + r.totalAnnuel);
        final lignes = [for (final r in rows) _ligne(r)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            commande(_mois!, largeur: 224),
            BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c)),
            BoutonSigh(libelle: 'Obligations', icone: LucideIcons.bookOpenCheck, variante: VarianteBouton.secondaire, onPressed: () => c.aller('cfg-comptabilite')),
          ])),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'ORTB Radio — tous les salariés',
                valeur: nombre(rows.length),
                icone: LucideIcons.radioTower,
                indice: '${money(rows.length * _radio.montant)} en ${_radio.moisLabel}'),
            KpiSigh(
                libelle: 'ORTB Télé — au-delà de ${_mf(paiSeuilTele)}',
                valeur: nombre(avecTele.length),
                icone: LucideIcons.tv,
                ton: TonSigh.info,
                indice: '${money(avecTele.length * _tele.montant)} en ${_tele.moisLabel}'),
            KpiSigh(
                libelle: 'Cumul par agent au-delà du seuil',
                valeur: money(paiCumulMaximum),
                icone: LucideIcons.layers,
                ton: TonSigh.neutre,
                indice: '${_mf(_radio.montant)} radio + ${_mf(_tele.montant)} télé'),
            KpiSigh(
                libelle: 'Dû sur ${paiMois[_m]}',
                valeur: money(duCeMois),
                icone: LucideIcons.coins,
                ton: duCeMois != 0 ? TonSigh.attention : TonSigh.succes,
                indice: duCeMois != 0 ? 'Prélèvement du mois' : 'Aucun prélèvement ce mois'),
          ]),
          const SizedBox(height: 16),
          NoteSigh(
              'La radio et la télé sont deux redevances distinctes qui se cumulent : un salaire supérieur à ${_mf(paiSeuilTele)} n’est pas dispensé de la radio, il acquitte les deux. '
              'Total dû sur l’exercice $paiAnnee : ${money(totalExercice)} — ${money(rows.length * _radio.montant)} en ${_radio.moisLabel} (radio) et '
              '${money(avecTele.length * _tele.montant)} en ${_tele.moisLabel} (télé).',
              ton: TonSigh.info,
              icone: LucideIcons.landmark),
          const SizedBox(height: 16),
          TableauSigh(
            key: ValueKey('ortb:$_m'),
            titre: 'Redevances par agent — ${paiMois[_m]} $paiAnnee',
            lignes: lignes,
            nomExport: 'redevance-ortb',
            taillePage: 20,
            triInitial: 'agent',
            filtres: [
              const FiltreTableau(nom: 'categorie', libelle: 'Catégories', options: [
                OptionChamp('les_deux', 'Radio + Télé'),
                OptionChamp('radio', 'Radio seule'),
                OptionChamp('aucune', 'Non redevable'),
              ]),
              FiltreTableau(
                  nom: 'etat',
                  libelle: 'État sur l’exercice',
                  options: const [OptionChamp('du', 'Dû ce mois'), OptionChamp('prelevee', 'Déjà prélevée'), OptionChamp('attente', 'À prélever')],
                  correspond: (r, v) => switch (v) {
                        'du' => n(r['duCeMois']) > 0,
                        'prelevee' => n(r['prelevee']) > 0,
                        _ => n(r['aPrelever']) > 0,
                      }),
            ],
            colonnes: [
              ColonneTableau(cle: 'matricule', libelle: 'Matricule', sansCoupure: true, rendu: (_, l) => monoTexte(l['matricule'])),
              ColonneTableau(cle: 'agent', libelle: 'Agent', texte: (l) => '${l['agent']}', rendu: (_, l) => cellAgent('${l['agent']}', '${l['poste']}')),
              ColonneTableau(cle: 'brut', libelle: 'Salaire brut', droite: true, texte: (l) => '${l['brut']}', rendu: (_, l) => cellMontant(n(l['brut']))),
              ColonneTableau(
                  cle: 'radio',
                  libelle: 'ORTB Radio',
                  droite: true,
                  texte: (l) => '${l['radio']}',
                  rendu: (_, l) => n(l['radio']) == 0 ? cellTexte('—', couleur: JetonsShell.slate400, taille: 12) : cellMontant(n(l['radio']))),
              ColonneTableau(
                  cle: 'tele',
                  libelle: 'ORTB Télé',
                  droite: true,
                  texte: (l) => '${l['tele']}',
                  rendu: (_, l) => n(l['tele']) == 0 ? cellSecondaire('non redevable') : cellMontant(n(l['tele']))),
              ColonneTableau(
                  cle: 'categorie',
                  libelle: 'Catégories',
                  texte: (l) => _r(l).categorieLabel,
                  rendu: (_, l) => l['categorie'] == 'aucune'
                      ? cellSecondaire('Non redevable')
                      : BadgeSigh(_r(l).categorieLabel, ton: l['categorie'] == 'les_deux' ? TonSigh.navy : TonSigh.info)),
              ColonneTableau(cle: 'totalAnnuel', libelle: 'Total annuel', droite: true, texte: (l) => '${l['totalAnnuel']}', rendu: (_, l) => cellMontant(n(l['totalAnnuel']), fort: true)),
              ColonneTableau(
                  cle: 'duCeMois',
                  libelle: 'Dû ce mois',
                  droite: true,
                  texte: (l) => '${l['duCeMois']}',
                  rendu: (_, l) {
                    final r = _r(l);
                    if (r.duCeMois != 0) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        cellTexte(_mf(r.duCeMois), couleur: JetonsShell.warning700, poids: FontWeight.w600),
                        cellSecondaire(r.libelleDuCeMois),
                      ]);
                    }
                    if (r.aPrelever != 0) return cellSecondaire('à prélever · ${r.resume}');
                    if (r.prelevee != 0) return const BadgeSigh('Déjà prélevée', ton: TonSigh.succes);
                    return cellTexte('—');
                  }),
            ],
          ),
        ]);
      },
    );
  }
}
