import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'commun.dart';

/// `m9-facture-mere` — « Facture mère assurance » : la pièce unique adressée à une compagnie, qui consolide ses factures par souscripteur.
///
/// Ce qui fait sa valeur est le RAPPROCHEMENT : trois totaux (souscripteurs, factures patients, détail ligne à ligne) doivent coïncider, et l'écart
/// NOMME la pièce en cause. La commande d'émission n'est offerte que si le rapprochement concorde (un bouton grisé inviterait à chercher pourquoi ;
/// un bouton absent dit que la pièce n'est pas en état). Une mère ÉMISE ne se modifie plus : une correction passe par un avoir.
class EcranFactureMere extends StatefulWidget with EcranMaquette {
  const EcranFactureMere({super.key});

  @override
  String get titre => 'Facture mère assurance';

  @override
  String get description =>
      'Pièce unique adressée à une compagnie, consolidant toutes ses factures par souscripteur.';

  @override
  String get regle =>
      'La facture mère consolide les factures filles d’une compagnie. Elle n’est émise que si elle se recoupe exactement avec elles : une mère qui ne concorde pas donnerait à la compagnie un montant que la clinique ne saurait pas justifier le jour du litige. Une mère émise ne se modifie plus — une correction passe par un avoir.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Relevé & facture mensuelle',
          icone: LucideIcons.files,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-factures-assureur')),
      BoutonSigh(
          libelle: 'Créances',
          icone: LucideIcons.hourglass,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-creances')),
    ];
  }

  @override
  State<EcranFactureMere> createState() => _EtatFactureMere();
}

class _EtatFactureMere extends State<EcranFactureMere> {
  ControleurFormulaire? _compagnie, _periode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_compagnie != null) return;
    final c = ContexteEcran.of(context);
    final assureurs = actives(c, 'assureurs');
    _compagnie = champUnique(
        ChampDef(
            nom: 'compagnie',
            libelle: 'Compagnie',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [
              for (final a in assureurs) OptionChamp('${a['code']}', '${a['nom']}')
            ]),
        assureurs.isEmpty ? '' : '${assureurs.first['code']}');
    _periode = champUnique(
        ChampDef(
            nom: 'periode',
            libelle: 'Périodicité',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [for (final p in assPeriodesMere) OptionChamp(p.$1, p.$2)]),
        'mois');
    _compagnie!.addListener(_surChangement);
    _periode!.addListener(_surChangement);
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_compagnie != null) {
      _compagnie!.removeListener(_surChangement);
      _periode!.removeListener(_surChangement);
      _compagnie!.dispose();
      _periode!.dispose();
    }
    super.dispose();
  }

  String get _code => '${_compagnie!['compagnie']}';
  String get _per => '${_periode!['periode']}';

  String _depuis(ContexteEcran c) {
    final jours = assPeriodesMere.firstWhere((p) => p.$1 == _per).$3;
    return iso(c.aujourdhui.subtract(Duration(days: jours)));
  }

  String _nom(ContexteEcran c) => assNomAssureur(_code, actives(c, 'assureurs'));

  List<AssFilleMere> _filles(ContexteEcran c) =>
      assFillesMere(actives(c, 'factures'), _code, _nom(c), _depuis(c));

  // --- Les actes -----------------------------------------------------------------------------------------------------------

  Future<void> _emettre(BuildContext ctx, ContexteEcran c) async {
    final filles = _filles(c);
    final rap = assRapprocher(filles);
    // Second contrôle avant écriture : les pièces ont pu bouger.
    if (!rap.concorde) {
      ToastsSigh.afficher(ctx, 'Émission refusée — le rapprochement ne concorde plus.',
          type: TypeToast.erreur);
      return;
    }
    final ok = await confirmerSigh(ctx,
        titre: 'Émettre la facture mère ?',
        message:
            'La pièce consolidera ${nombre(filles.length)} souscripteur(s) et ${nombre(rap.nbFactures)} facture(s) fille(s), pour ${money(rap.totalFilles)} réclamés à ${_nom(c)}.\n\nUne fois émise, elle ne se modifie plus : une correction passera par un avoir.',
        libelleOk: 'Émettre et transmettre');
    if (!ok || !ctx.mounted) return;
    final col = c.magasin.collection('facturesMere');
    final r = col.inserer(
        assEmettreMere(
            code: _code,
            nom: _nom(c),
            periode: _per,
            filles: filles,
            rap: rap,
            depuis: _depuis(c),
            auj: c.aujourdhui,
            nbExistantes: col.toutes.length,
            emisePar: c.utilisateur),
        prefixe: 'FM');
    ToastsSigh.afficher(ctx, 'Facture mère ${r.fiche['numero']} émise.',
        type: TypeToast.succes,
        detail: '${_nom(c)} — ${money(rap.totalFilles)}',
        annuler: r.annuler,
        messageAnnulation: 'Émission annulée — la pièce est archivée.');
    _imprimer(ctx, c, r.fiche);
  }

  void _regler(BuildContext ctx, ContexteEcran c, Fiche r) {
    final ctl = ControleurFormulaire(const [
      ChampDef(
          nom: 'dateReglement',
          libelle: 'Date du règlement',
          type: TypeChamp.date,
          requis: true),
      ChampDef(
          nom: 'montantRegle',
          libelle: 'Montant réglé (FCFA)',
          type: TypeChamp.nombre,
          requis: true,
          aide:
              'Un règlement partiel se saisit tel quel : le reliquat reste en créance.'),
      ChampDef(
          nom: 'reference',
          libelle: 'Référence du virement ou du chèque',
          requis: true),
    ], {
      'dateReglement': iso(c.aujourdhui),
      'montantRegle': '${r['montantReclame']}',
    });
    afficherModale<void>(ctx,
        titre: 'Règlement de ${r['numero']}',
        sousTitre: '${r['compagnie']} — ${money(r['montantReclame'])} réclamés',
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final montant = num.tryParse('${v['montantRegle']}'.trim()) ?? 0;
                    final patch = assReglerMere(r,
                        date: '${v['dateReglement']}',
                        montant: montant,
                        reference: '${v['reference']}');
                    c.magasin.collection('facturesMere').mettreAJour(r['id'], patch);
                    fermer();
                    final reste = n(patch['reliquat']);
                    ToastsSigh.afficher(
                        ctx,
                        reste <= 0
                            ? 'Facture mère soldée.'
                            : 'Règlement partiel enregistré — ${money(reste)} restent en créance.',
                        type: reste <= 0 ? TypeToast.succes : TypeToast.attention,
                        detail: '${r['numero']}');
                  }),
            ]);
  }

  /// `imprimerMere(r)` : la pièce émise ([r]) ou l'aperçu de ce qui serait émis.
  void _imprimer(BuildContext ctx, ContexteEcran c, Fiche? r) {
    final filles = _filles(c);
    final rap = assRapprocher(filles);
    final lignes = r != null
        ? [for (final x in (r['souscripteurs'] as List? ?? const [])) (x as Map).cast<String, Object?>()]
        : [
            for (final g in filles)
              {
                'souscripteur': g.souscripteur,
                'nbFactures': g.factures.length,
                'montant': g.montant,
                'assureur': g.assureur,
                'patient': g.patient,
              }
          ];
    final total = r != null ? n(r['montantReclame']) : rap.totalFilles;
    final controle = r != null ? (r['controle'] as Map).cast<String, Object?>() : null;
    final nomC = r != null ? '${r['compagnie']}' : _nom(c);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'FACTURE MÈRE — ${nomC.toUpperCase()}',
            sousTitre: r != null ? '${r['numero']}' : 'Aperçu — pièce non émise',
            cartouche: [
              ('Compagnie', nomC),
              (
                'Périodicité',
                r != null
                    ? '${r['periodeLabel']}'
                    : assPeriodesMere.firstWhere((p) => p.$1 == _per).$2
              ),
              (
                'Période',
                '${dateDe(r != null ? r['debut'] : _depuis(c))} au ${dateDe(r != null ? r['fin'] : iso(c.aujourdhui))}'
              ),
              ('Souscripteurs consolidés', nombre(lignes.length)),
              ('Pièces filles', nombre(r != null ? n(r['nbFactures']) : rap.nbFactures)),
              ('Émise le', r != null ? dateDe(r['dateEmission']) : '— aperçu —'),
              ('RCCM', IdentiteClinique.rccm),
            ],
            blocs: [
              const BlocTexte('CONSOLIDATION PAR SOUSCRIPTEUR', gras: true),
              BlocTableau(TableauEtat(
                  libelleTotal: 'TOTAL GÉNÉRAL',
                  colonnes: [
                    ColonneEtat(
                        libelle: 'Souscripteur (n° de police)',
                        valeur: (x) => x['souscripteur']),
                    ColonneEtat(
                        libelle: 'Pièces',
                        droite: true,
                        valeur: (x) => nombre(x['nbFactures']),
                        somme: (x) => n(x['nbFactures'])),
                    ColonneEtat(
                        libelle: 'Montant total',
                        droite: true,
                        valeur: (x) => m(x['montant']),
                        somme: (x) => n(x['montant'])),
                    ColonneEtat(
                        libelle: 'Part patient',
                        droite: true,
                        valeur: (x) => m(x['patient']),
                        somme: (x) => n(x['patient'])),
                    ColonneEtat(
                        libelle: 'PART RÉCLAMÉE',
                        droite: true,
                        valeur: (x) => m(x['assureur']),
                        somme: (x) => n(x['assureur'])),
                  ],
                  lignes: lignes)),
              BlocTexte('Montant réclamé à la compagnie : ${m(total)}', gras: true),
              BlocTexte('${IdentiteClinique.formuleArrete} : ${montantEnLettres(total)}.'),
              // Le rapprochement est PORTÉ SUR LA PIÈCE : la compagnie constate la concordance sans demander un second document.
              BlocTexte(
                  'Contrôle de concordance — total des souscripteurs : ${m(controle != null ? controle['totalFilles'] : rap.totalFilles)}   ·   total des pièces filles : ${m(controle != null ? controle['totalFactures'] : rap.totalFactures)}   ·   total du détail ligne à ligne : ${m(controle != null ? controle['totalLignes'] : rap.totalLignes)}. Les trois montants coïncident.',
                  italique: true),
              const BlocTexte(
                  'Le relevé détaillé par assuré et par prestation accompagne la présente facture. Toute contestation portant sur une ligne s’y rapporte.',
                  italique: true),
            ],
            signatures: const [
              Signature('La Directrice de l’Administration et des Finances',
                  mention: 'Signature et cachet'),
              Signature('Pour la compagnie', mention: 'Reçu le / Signature'),
            ]));
  }

  // --- Les onglets ---------------------------------------------------------------------------------------------------------

  Widget _consolidation(BuildContext ctx, List<AssFilleMere> filles) {
    if (filles.isEmpty) {
      return const CarteSigh(
          child: VideSigh('Aucune prestation assurée sur la période.',
              icone: LucideIcons.layers,
              indice: 'Élargir la périodicité, ou choisir une autre compagnie.'));
    }
    return TableauSigh(
      lignes: [
        for (final g in filles)
          {
            'id': g.souscripteur,
            'souscripteur': g.souscripteur,
            'nb': g.factures.length,
            'lignes': g.lignes,
            'montant': g.montant,
            'patient': g.patient,
            'assureur': g.assureur,
          }
      ],
      recherche: false,
      messageVide: 'Aucun souscripteur.',
      colonnes: [
        const ColonneTableau(cle: 'souscripteur', libelle: 'Souscripteur (n° de police)'),
        ColonneTableau(
            cle: 'nb',
            libelle: 'Pièces filles',
            droite: true,
            texte: (r) => nombre(r['nb'])),
        ColonneTableau(
            cle: 'lignes',
            libelle: 'Prestations',
            droite: true,
            texte: (r) => nombre(r['lignes'])),
        ColonneTableau(
            cle: 'montant',
            libelle: 'Montant total',
            droite: true,
            texte: (r) => money(r['montant'])),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Part patient',
            droite: true,
            texte: (r) => money(r['patient'])),
        ColonneTableau(
            cle: 'assureur',
            libelle: 'Part à réclamer',
            droite: true,
            texte: (r) => money(r['assureur']),
            rendu: (_, r) => Text(money(r['assureur']),
                style: const TextStyle(
                    fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
      ],
      actionsLigne: (context, r) => [
        BoutonIcone(
            icone: LucideIcons.eye,
            libelle: 'Voir les pièces filles de ce souscripteur',
            onPressed: () {
              final g = filles.firstWhere((x) => x.souscripteur == r['souscripteur']);
              final pieces = trierPar<Fiche>(g.factures, (f) => f['date']);
              afficherTiroir<void>(context,
                  titre: g.souscripteur,
                  sousTitre:
                      '${nombre(g.factures.length)} pièce(s) — ${money(g.assureur)} à réclamer',
                  corps: MiniTableauSigh(colonnes: [
                    ColonneMini('Pièce', (f) => '${f['numero']}'),
                    ColonneMini('Date', (f) => dateDe(f['date'])),
                    ColonneMini('Patient', (f) => '${f['patient'] ?? ''}'),
                    ColonneMini('Total', (f) => money(f['montantTTC'])),
                    ColonneMini('Part assureur', (f) => money(f['partAssurance'])),
                  ], lignes: pieces));
            }),
      ],
    );
  }

  Widget _lignes(List<AssFilleMere> filles) {
    final rows = <Fiche>[];
    for (final g in filles) {
      for (final f in g.factures) {
        for (final x in (f['lignes'] as List? ?? const [])) {
          final l = (x as Map).cast<String, Object?>();
          if (!(n(l['partAssureur']) > 0)) continue;
          rows.add({
            'id': '${f['numero']}-${rows.length}',
            'souscripteur': g.souscripteur,
            'piece': f['numero'],
            'date': f['date'],
            'patient': '${f['patient']} — ${f['patientCode']}',
            'designation': l['designation'],
            'quantite': l['quantite'],
            'montant': l['montant'],
            'partAssureur': l['partAssureur'],
          });
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Chaque ligne d’assurance est reprise ici, patient par patient et prestation par prestation. C’est le niveau auquel une compagnie conteste — il doit donc être produit sans reconstruction, à partir des pièces elles-mêmes.',
          icone: LucideIcons.list),
      const SizedBox(height: 12),
      TableauSigh(
        lignes: trierPar<Fiche>(rows, (r) => r['date']),
        recherche: false,
        messageVide: 'Aucune ligne d’assurance sur la période.',
        colonnes: [
          ColonneTableau(
              cle: 'date', libelle: 'Date', texte: (r) => dateDe(r['date'])),
          const ColonneTableau(cle: 'souscripteur', libelle: 'Souscripteur'),
          const ColonneTableau(cle: 'piece', libelle: 'Pièce'),
          const ColonneTableau(cle: 'patient', libelle: 'Assuré'),
          const ColonneTableau(cle: 'designation', libelle: 'Prestation'),
          const ColonneTableau(cle: 'quantite', libelle: 'Qté', droite: true),
          ColonneTableau(
              cle: 'montant',
              libelle: 'Montant',
              droite: true,
              texte: (r) => money(r['montant'])),
          ColonneTableau(
              cle: 'partAssureur',
              libelle: 'Part assureur',
              droite: true,
              texte: (r) => money(r['partAssureur']),
              rendu: (_, r) => Text(money(r['partAssureur']),
                  style: const TextStyle(
                      fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
        ],
      ),
    ]);
  }

  Widget _emises(BuildContext ctx, ContexteEcran c, List<Fiche> emises) {
    return TableauSigh(
      lignes: trierPar<Fiche>(emises, (r) => r['dateEmission'], descendant: true),
      recherche: false,
      messageVide: 'Aucune facture mère émise pour cette compagnie.',
      colonnes: [
        const ColonneTableau(cle: 'numero', libelle: 'Numéro'),
        ColonneTableau(
            cle: 'dateEmission',
            libelle: 'Émise le',
            texte: (r) => dateDe(r['dateEmission'])),
        const ColonneTableau(cle: 'periodeLabel', libelle: 'Périodicité'),
        const ColonneTableau(
            cle: 'nbSouscripteurs', libelle: 'Souscripteurs', droite: true),
        const ColonneTableau(cle: 'nbFactures', libelle: 'Pièces filles', droite: true),
        ColonneTableau(
            cle: 'montantReclame',
            libelle: 'Réclamé',
            droite: true,
            texte: (r) => money(r['montantReclame'])),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (r) => r['etat'] == 'reglee' ? 'Réglée' : 'Transmise',
            rendu: (_, r) => r['etat'] == 'reglee'
                ? const BadgeSigh('Réglée', ton: TonSigh.succes)
                : const BadgeSigh('Transmise', ton: TonSigh.attention)),
      ],
      actionsLigne: (context, r) => [
        BoutonIcone(
            icone: LucideIcons.printer,
            libelle: 'Réimprimer la facture mère',
            onPressed: () => _imprimer(context, c, r)),
        if (r['etat'] != 'reglee' && c.droit.editer)
          BoutonSigh(
              libelle: 'Enregistrer le règlement',
              icone: LucideIcons.banknote,
              taille: TailleBouton.sm,
              onPressed: () => _regler(context, c, r)),
        BoutonIcone(
            icone: LucideIcons.eye,
            libelle: 'Détail',
            onPressed: () => afficherTiroir<void>(context,
                titre: '${r['numero']}',
                sousTitre: '${r['compagnie']} — ${r['periodeLabel']}',
                corps: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DescListeSigh([
                        ('Numéro', r['numero']),
                        ('Compagnie', r['compagnie']),
                        ('Périodicité', r['periodeLabel']),
                        ('Période', '${dateDe(r['debut'])} au ${dateDe(r['fin'])}'),
                        ('Émise le', dateDe(r['dateEmission'])),
                        ('Souscripteurs', nombre(r['nbSouscripteurs'])),
                        ('Pièces filles', nombre(r['nbFactures'])),
                        ('Montant réclamé', money(r['montantReclame'])),
                        (
                          'État',
                          r['etat'] == 'reglee'
                              ? 'Réglée le ${dateDe(r['dateReglement'])}'
                              : 'Transmise'
                        ),
                      ]),
                      const SizedBox(height: 16),
                      CarteSigh(
                          titre: 'Souscripteurs consolidés',
                          child: MiniTableauSigh(colonnes: [
                            ColonneMini('Souscripteur', (x) => '${x['souscripteur']}'),
                            ColonneMini('Pièces', (x) => nombre(x['nbFactures'])),
                            ColonneMini('Part réclamée', (x) => money(x['assureur'])),
                          ], lignes: [
                            for (final x in (r['souscripteurs'] as List? ?? const []))
                              (x as Map).cast<String, Object?>()
                          ])),
                      const SizedBox(height: 16),
                      const NoteSigh(
                          'Cette pièce a été transmise : elle ne se modifie plus. Une correction passe par un avoir, sans quoi la compagnie et la clinique n’auraient plus le même document sous les yeux.',
                          icone: LucideIcons.lock),
                    ]))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['assureurs', 'factures', 'facturesMere']),
      builder: (context, _) {
        final filles = _filles(c);
        final rap = assRapprocher(filles);
        final emises = actives(c, 'facturesMere')
            .where((x) => x['compagnieCode'] == _code)
            .toList();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  titre: 'Compagnie et périodicité',
                  child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                    commande(_compagnie!, largeur: 280),
                    commande(_periode!, largeur: 200),
                    BoutonSigh(
                        libelle: 'Aperçu de la facture mère',
                        icone: LucideIcons.eye,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => _imprimer(context, c, null)),
                    // L'émission n'est offerte que si le rapprochement est bon : un bouton grisé inviterait à chercher pourquoi.
                    if (rap.concorde && filles.isNotEmpty && c.droit.editer)
                      BoutonSigh(
                          libelle: 'Émettre la facture mère',
                          icone: LucideIcons.send,
                          onPressed: () => _emettre(context, c)),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Souscripteurs facturés',
                    valeur: nombre(filles.length),
                    indice: _nom(c),
                    icone: LucideIcons.building2),
                KpiSigh(
                    libelle: 'Pièces filles',
                    valeur: nombre(rap.nbFactures),
                    indice: 'factures patients de la période',
                    icone: LucideIcons.files,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Total à réclamer',
                    valeur: money(rap.totalFilles),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Rapprochement',
                    valeur: rap.vide
                        ? 'Aucune pièce'
                        : (rap.concorde
                            ? 'Concordant'
                            : '${nombre(rap.ecarts.length)} écart(s)'),
                    icone: rap.vide
                        ? LucideIcons.inbox
                        : (rap.concorde
                            ? LucideIcons.checkCheck
                            : LucideIcons.triangleAlert),
                    ton: rap.vide
                        ? TonSigh.neutre
                        : (rap.concorde ? TonSigh.succes : TonSigh.danger)),
              ]),
              const SizedBox(height: 16),
              // La maquette teste `!concorde` AVANT `vide` : sur une compagnie sans pièce, c'est ce premier message qui s'affiche (E502).
              if (!rap.concorde)
                NoteSigh(
                    'La facture mère ne peut pas être émise. ${rap.ecarts.join('\n')}\nUne mère qui ne se recoupe pas avec ses filles donnerait à la compagnie un montant que la clinique ne saurait pas justifier ligne à ligne le jour du litige.',
                    ton: TonSigh.danger,
                    icone: LucideIcons.triangleAlert)
              else if (filles.isNotEmpty)
                NoteSigh(
                    'Les trois niveaux concordent : ${money(rap.totalFilles)} au total des souscripteurs, des factures patients et du détail ligne à ligne. La pièce peut être émise.',
                    ton: TonSigh.succes,
                    icone: LucideIcons.checkCheck),
              const SizedBox(height: 16),
              OngletsSigh(onglets: [
                OngletDef(
                    id: 'consolidation',
                    libelle: 'Consolidation',
                    compte: filles.length,
                    construire: (ctx) => _consolidation(ctx, filles)),
                OngletDef(
                    id: 'lignes',
                    libelle: 'Détail par ligne d’assurance',
                    compte: rap.nbFactures,
                    construire: (_) => _lignes(filles)),
                OngletDef(
                    id: 'emises',
                    libelle: 'Factures mères émises',
                    compte: emises.length,
                    construire: (ctx) => _emises(ctx, c, emises)),
              ]),
            ]);
      },
    );
  }
}
