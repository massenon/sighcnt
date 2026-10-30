import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mat_commun.dart';
import 'mat_crud.dart';

/// Les registres de suivi de la maternité (M4) : CPN & carte maternelle, CPoN, planification familiale, SONUB / SONUC, PTME, soins curatifs.
/// Référentiels tracés au rapport officiel du 27/08/2026 (`mat_donnees.dart`, engendré depuis la maquette).

ColonneTableau _ref(String lib) => ColonneTableau(
    cle: 'reference', libelle: lib, sansCoupure: true, texte: (r) => '${r['reference'] ?? ''}', rendu: (_, r) => matRef(r['reference']));

ColonneTableau _date(String cle, String lib) =>
    ColonneTableau(cle: cle, libelle: lib, sansCoupure: true, texte: (r) => matDateFR(r[cle]), rendu: (_, r) => Text(matDateFR(r[cle])));

ColonneTableau _patientLigne(String lib) =>
    ColonneTableau(cle: 'patient', libelle: lib, texte: (r) => '${r['patient'] ?? ''} — ${r['patientCode'] ?? ''}');

ColonneTableau _oui(String cle, String lib, String ouiT, TonSigh ton, String nonT, {TonSigh? tonNon}) => ColonneTableau(
    cle: cle,
    libelle: lib,
    texte: (r) => matVrai(r[cle]) ? ouiT : nonT,
    rendu: (_, r) => matVrai(r[cle]) ? BadgeSigh(ouiT, ton: ton) : (tonNon != null ? BadgeSigh(nonT, ton: tonNon) : matMuet(nonT)));

List<OptionChamp> _opts(Iterable<String> l) => [for (final x in l) OptionChamp(x)];

KpiSigh _kpi(String lib, String val, IconData ic, TonSigh ton, [String? indice]) =>
    KpiSigh(libelle: lib, valeur: val, icone: ic, ton: ton, indice: indice);

FiltreTableau _oneNon(String nom, String lib, String oui, String non, bool Function(Fiche) test) => FiltreTableau(
    nom: nom,
    libelle: lib,
    options: [OptionChamp('oui', oui), OptionChamp('non', non)],
    correspond: (r, v) => v == 'oui' ? test(r) : !test(r));

Fiche _nombres(Fiche v, Iterable<String> cles) {
  for (final k in cles) {
    if (v.containsKey(k)) v[k] = matNombreSaisi(v[k]);
  }
  return v;
}

List<String> _liste(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-cpn — CPN & carte maternelle
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranCpn extends StatelessWidget with EcranMaquette {
  const EcranCpn({super.key});
  @override
  String get titre => 'CPN & carte maternelle';
  @override
  String get description => 'Consultations prénatales structurées : SP1-SP5, MILDA, grossesse à risque, Mébendazole, visites CPN.';
  @override
  String get regle =>
      'La carte maternelle porte les quatre variables nouvelles du rapport du 27/08/2026 : doses SP1 à SP5 (TPI paludisme), MILDA remise, GAR (grossesse à risque, badge d’alerte) et Mébendazole (déparasitage dès le 2ᵉ trimestre). Un âge < 18 ans ou > 35 ans est un facteur de risque CPN — le formulaire le signale.';

  /// « Ajouter une visite CPN » : la grille du formulaire national s'allonge d'une colonne.
  static void ajouterVisite(BuildContext ctx, Fiche g) {
    final c = ContexteEcran.of(ctx);
    final n = ((g['visites'] as List?) ?? const []).length + 1;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'date', libelle: 'Date de la visite', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'ta', libelle: 'TA', indicatif: '12/8', requis: true),
      const ChampDef(nom: 'poids', libelle: 'Poids (kg)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'hu', libelle: 'Hauteur utérine (cm)', type: TypeChamp.nombre),
      const ChampDef(nom: 'bdcf', libelle: 'BDCF (bpm)', type: TypeChamp.nombre),
      ChampDef(nom: 'albumine', libelle: 'Albumine urinaire', type: TypeChamp.select, options: _opts(const ['—', '+', '++'])),
      ChampDef(nom: 'sucre', libelle: 'Sucre urinaire', type: TypeChamp.select, options: _opts(const ['—', '+', '++'])),
    ]);
    afficherModale<void>(ctx,
        titre: 'Visite CPN $n — ${g['patient']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer la visite',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final vv = ctl.valider();
                    if (vv == null) return;
                    final visites = <Object?>[
                      ...((g['visites'] as List?) ?? const []),
                      matSansNuls({'n': n, ..._nombres({...vv}, const ['poids', 'hu', 'bdcf'])}),
                    ];
                    c.magasin.collection('grossesses').mettreAJour(g['id'], {'visites': visites});
                    fermer();
                    ToastsSigh.afficher(ctx, 'Visite CPN enregistrée.', type: TypeToast.succes);
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('grossesses');
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('CPN-', col.toutes);
      _nombres(v, const ['termeSA']);
      v['sp'] = _liste(v['sp']);
      // Facteur de risque CPN : on SIGNALE, on ne coche pas GAR à la place de la sage-femme.
      final p = matFemmes(c.magasin).where((x) => x['code'] == v['patientCode']).firstOrNull;
      if (p != null && p['dateNaissance'] != null && matAgeHorsFenetreCpn(p['dateNaissance'], matVrai(v['gar']), c.aujourdhui)) {
        ToastsSigh.afficher(ctx, matMessageAgeCpn(), type: TypeToast.attention);
      }
      return matSansNuls(v);
    }

    return CrudMat(
      collection: col,
      entite: 'grossesse suivie',
      entiteP: 'grossesses suivies',
      prefixeId: 'GRO',
      triInitial: 'dpa',
      largeurTiroir: 672,
      source: 'Rapport officiel maternité du 27/08/2026 — Module B et tableau 8 (CPN 1 à 8, OMS).',
      colonnes: [
        _ref('N°'),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patiente',
            texte: (r) => '${r['patient'] ?? ''} ${r['patientCode'] ?? ''}',
            rendu: (_, r) => matCelPatient('${r['patient'] ?? ''}', '${r['patientCode'] ?? ''}')),
        ColonneTableau(cle: 'termeSA', libelle: 'Terme', droite: true, valeur: (r) => matNum(r['termeSA']), texte: (r) => '${r['termeSA'] == null ? '—' : matTexteNombre(r['termeSA'])} SA'),
        _date('dpa', 'DPA'),
        ColonneTableau(
            cle: 'gar',
            libelle: 'GAR',
            texte: (r) => matVrai(r['gar']) ? 'À risque' : '—',
            rendu: (_, r) => matVrai(r['gar']) ? const BadgeSigh('GROSSESSE À RISQUE', ton: TonSigh.danger) : matMuet('—')),
        ColonneTableau(
            cle: 'sp',
            libelle: 'SP (TPI)',
            texte: (r) => _liste(r['sp']).join(' '),
            rendu: (_, r) => _liste(r['sp']).isEmpty ? matMuet('Aucune dose') : matBadges([for (final s in _liste(r['sp'])) (s, TonSigh.info)])),
        _oui('milda', 'MILDA', 'Remise', TonSigh.succes, 'Non remise', tonNon: TonSigh.attention),
        _oui('mebendazole', 'Mébendazole', 'Fait', TonSigh.succes, '—'),
        ColonneTableau(cle: 'visites', libelle: 'CPN', droite: true, valeur: (r) => ((r['visites'] as List?) ?? const []).length, texte: (r) => '${((r['visites'] as List?) ?? const []).length}'),
        const ColonneTableau(cle: 'sageFemme', libelle: 'Sage-femme'),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Patiente', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        const ChampDef(nom: 'ddr', libelle: 'Date des dernières règles (DDR)', type: TypeChamp.date, requis: true),
        const ChampDef(
            nom: 'dpa',
            libelle: 'Date prévue d’accouchement (DPA)',
            type: TypeChamp.date,
            requis: true,
            aide: 'Calculée depuis la DDR (≈ 40 SA) — corrigée par l’échographie de datation le cas échéant.'),
        const ChampDef(nom: 'termeSA', libelle: 'Terme actuel (SA)', type: TypeChamp.nombre, requis: true),
        ChampDef(nom: 'groupeSanguin', libelle: 'Groupe sanguin / Rhésus', type: TypeChamp.select, options: _opts(matGroupesSanguins)),
        ChampDef(nom: 'sageFemme', libelle: 'Sage-femme référente', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
        const ChampDef.section('Variables du rapport du 27/08/2026'),
        ChampDef(nom: 'sp', libelle: 'Doses SP administrées (TPI paludisme)', type: TypeChamp.multiselect, options: _opts(matDosesSp)),
        const ChampDef(nom: 'milda', libelle: 'MILDA remise', type: TypeChamp.case_),
        const ChampDef(
            nom: 'gar',
            libelle: 'Grossesse à risque (GAR)',
            type: TypeChamp.case_,
            aide: 'Déclenche le badge d’alerte rouge sur la fiche et compte à l’indicateur DHIS2.'),
        const ChampDef(nom: 'mebendazole', libelle: 'Mébendazole (déparasitage, dès le 2ᵉ trimestre)', type: TypeChamp.case_),
        const ChampDef.section('Prévention'),
        ChampDef(nom: 'vat', libelle: 'Vaccination antitétanique', type: TypeChamp.select, options: _opts(const ['VAT1', 'VAT2', 'VAT3', 'VAT4', 'VAT5'])),
        const ChampDef(nom: 'fer', libelle: 'Fer prescrit', type: TypeChamp.case_),
        const ChampDef(nom: 'folates', libelle: 'Acide folique prescrit', type: TypeChamp.case_),
      ],
      valeursInitiales: () => {},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        _oneNon('gar', 'Risque', 'Grossesses à risque', 'Sans risque identifié', (r) => matVrai(r['gar'])),
        _oneNon('milda', 'MILDA', 'Remise', 'Non remise', (r) => matVrai(r['milda'])),
      ],
      kpis: (ctx, rows) => [
        _kpi('Grossesses suivies', matNombre(rows.length), LucideIcons.baby, TonSigh.navy),
        _kpi('À risque (GAR)', matNombre(rows.where((r) => matVrai(r['gar'])).length), LucideIcons.triangleAlert, TonSigh.danger),
        _kpi('Couverture SP3', matPct(rows.where((r) => _liste(r['sp']).contains('SP3')).length, rows.length), LucideIcons.shieldCheck, TonSigh.info, 'Indicateur DHIS2'),
        _kpi('MILDA remises', matPct(rows.where((r) => matVrai(r['milda'])).length, rows.length), LucideIcons.tent, TonSigh.succes),
      ],
      detail: (ctx, r0) => AnimatedBuilder(
          animation: col,
          builder: (ctx, _) {
            final r = col.parId(r0['id']) ?? r0;
            final visites = [for (final v in ((r['visites'] as List?) ?? const [])) (v as Map).cast<String, Object?>()];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (matVrai(r['gar'])) ...[
                matNote('GROSSESSE À RISQUE — le rapport demande un badge visuel d’alerte sur le dossier. Surveillance rapprochée.',
                    ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
                const SizedBox(height: 16),
              ],
              DescListeSigh([
                ('Référence', '${r['reference']}'),
                ('Patiente', '${r['patient']} — ${r['patientCode']}'),
                ('DDR', matDateFR(r['ddr'])),
                ('DPA', matDateFR(r['dpa'])),
                ('Terme', '${r['termeSA'] == null ? '—' : matTexteNombre(r['termeSA'])} SA'),
                ('Groupe sanguin', matOuTiret(r['groupeSanguin'])),
                ('Doses SP', _liste(r['sp']).isEmpty ? 'Aucune' : _liste(r['sp']).join(', ')),
                ('MILDA', matVrai(r['milda']) ? 'Remise' : 'Non remise'),
                ('Mébendazole', matVrai(r['mebendazole']) ? 'Administré' : 'Non'),
                ('VAT', matOuTiret(r['vat'])),
                ('Fer / folates', '${matVrai(r['fer']) ? 'Fer' : '—'} / ${matVrai(r['folates']) ? 'folates' : '—'}'),
                ('Sage-femme', '${r['sageFemme'] ?? ''}'),
              ]),
              const SizedBox(height: 16),
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Visites CPN — la grille du formulaire national',
                      style: TextStyle(color: JetonsShell.slate900, fontSize: 14, fontWeight: FontWeight.w600))),
              if (visites.isEmpty)
                const VideSigh('Aucune visite CPN enregistrée.', icone: LucideIcons.clipboard)
              else
                MiniTableauSigh(colonnes: [
                  ColonneMini('CPN', (v) => 'CPN ${matTexteNombre(v['n'])}'),
                  ColonneMini('Date', (v) => matDateFR(v['date'])),
                  ColonneMini('TA', (v) => '${v['ta'] ?? ''}'),
                  ColonneMini('Poids (kg)', (v) => matTexteNombre(v['poids'])),
                  ColonneMini('HU (cm)', (v) => matTexteNombre(v['hu'])),
                  ColonneMini('BDCF', (v) => matTexteNombre(v['bdcf'])),
                  ColonneMini('Albumine', (v) => '${v['albumine'] ?? ''}'),
                  ColonneMini('Sucre', (v) => '${v['sucre'] ?? ''}'),
                ], lignes: visites),
              if (c.droit.editer) ...[
                const SizedBox(height: 16),
                BoutonSigh(libelle: 'Ajouter une visite CPN', icone: LucideIcons.plus, onPressed: () => ajouterVisite(context, r)),
              ],
            ]);
          }),
      etat: (ctx, r) {
        final visites = [for (final v in ((r['visites'] as List?) ?? const [])) (v as Map).cast<String, Object?>()];
        matImprimer(ctx,
            titre: 'Carte maternelle — suivi CPN',
            sousTitre: '${r['reference']}',
            cartouche: [
              ('Patiente', '${r['patient']}'),
              ('Dossier', '${r['patientCode']}'),
              ('DDR', matDateFR(r['ddr'])),
              ('DPA', matDateFR(r['dpa'])),
              ('Groupe sanguin', matOuTiret(r['groupeSanguin'])),
              ('Sage-femme', '${r['sageFemme'] ?? ''}'),
            ],
            blocs: [
              matBlocRubriques([
                ('Doses SP (TPI paludisme)', _liste(r['sp']).isEmpty ? 'Aucune' : _liste(r['sp']).join(', ')),
                ('MILDA remise', matVrai(r['milda']) ? 'Oui' : 'Non'),
                ('Grossesse à risque (GAR)', matVrai(r['gar']) ? 'OUI' : 'Non'),
                ('Mébendazole', matVrai(r['mebendazole']) ? 'Oui' : 'Non'),
                ('VAT', matOuTiret(r['vat'])),
              ], libelleValeur: 'Valeur'),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'CPN', valeur: (v) => 'CPN ${matTexteNombre(v['n'])}'),
                ColonneEtat(libelle: 'Date', valeur: (v) => matDateFR(v['date'])),
                ColonneEtat(libelle: 'TA', valeur: (v) => '${v['ta'] ?? ''}'),
                ColonneEtat(libelle: 'Poids (kg)', valeur: (v) => matTexteNombre(v['poids']), droite: true),
                ColonneEtat(libelle: 'HU (cm)', valeur: (v) => matTexteNombre(v['hu']), droite: true),
                ColonneEtat(libelle: 'BDCF', valeur: (v) => matTexteNombre(v['bdcf']), droite: true),
              ], lignes: visites)),
            ],
            signatures: [Signature('La Sage-femme', nom: '${r['sageFemme'] ?? ''}')]);
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-cpon — consultations post-natales (Module D)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranCpon extends StatelessWidget with EcranMaquette {
  const EcranCpon({super.key});
  @override
  String get titre => 'Consultations post-natales (CPoN)';
  @override
  String get description => 'CPoN 1 à 3, hémorragie ANTE-partum, HPP, examen puerpéral et état du nouveau-né.';
  @override
  String get regle =>
      'Trois séances — CPoN 1 (6 h–24 h), CPoN 2 (J6–J14), CPoN 3 (6ᵉ semaine). L’hémorragie ANTE-PARTUM est LA variable nouvelle du rapport : elle corrèle les complications puerpérales aux hémorragies du 3ᵉ trimestre (placenta praevia, HRP, rupture utérine) — sans elle, le suivi post-natal ignore l’antécédent qui le commande.';

  static String _seance(Object? code) => matTypeCpon(code)?['label'] as String? ?? '$code';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('CPO-', c.magasin.collection('cpon').toutes);
      if (!matVrai(v['hemorragieAntePartum'])) v['etiologieAnte'] = null;
      return matSansNuls(v);
    }

    return CrudMat(
      collection: c.magasin.collection('cpon'),
      entite: 'consultation post-natale',
      entiteP: 'consultations post-natales',
      prefixeId: 'CPO',
      triInitial: 'date',
      sensInitial: 'desc',
      source: 'Rapport officiel maternité du 27/08/2026 — Module D et tableau 1 (registre CPoN).',
      colonnes: [
        _ref('N°'),
        _date('date', 'Date'),
        _patientLigne('Accouchée'),
        ColonneTableau(cle: 'type', libelle: 'Séance', texte: (r) => _seance(r['type']), rendu: (_, r) => BadgeSigh(_seance(r['type']), ton: TonSigh.navy)),
        ColonneTableau(
            cle: 'hemorragieAntePartum',
            libelle: 'Hémorragie ANTE-partum',
            texte: (r) => matVrai(r['hemorragieAntePartum']) ? 'Oui — ${r['etiologieAnte'] ?? ''}' : 'Non',
            rendu: (_, r) => matVrai(r['hemorragieAntePartum'])
                ? BadgeSigh('OUI — ${r['etiologieAnte'] ?? 'étiologie à préciser'}', ton: TonSigh.danger)
                : matMuet('Non')),
        _oui('hpp', 'HPP', 'HPP', TonSigh.danger, 'Non'),
        _oui('conseilPF', 'Conseil PF', 'Fait', TonSigh.succes, '—'),
        const ColonneTableau(cle: 'sageFemme', libelle: 'Sage-femme'),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Accouchée', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        const ChampDef(nom: 'date', libelle: 'Date de la consultation', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'type',
            libelle: 'Séance',
            type: TypeChamp.select,
            requis: true,
            options: [for (final t in matTypesCpon) OptionChamp('${t['code']}', '${t['label']} — ${t['fenetre']}')]),
        const ChampDef.section('Hémorragies — la variable nouvelle du rapport'),
        const ChampDef(nom: 'hemorragieAntePartum', libelle: 'Hémorragie ANTE-partum (3ᵉ trimestre)', type: TypeChamp.case_),
        ChampDef(
            nom: 'etiologieAnte',
            libelle: 'Étiologie (si hémorragie ante-partum)',
            type: TypeChamp.select,
            options: _opts(const ['Placenta praevia', 'Hématome rétro-placentaire', 'Rupture utérine', 'Autre'])),
        const ChampDef(nom: 'hpp', libelle: 'Hémorragie du post-partum (HPP)', type: TypeChamp.case_),
        const ChampDef.section('Examen et suites'),
        const ChampDef(
            nom: 'examen', libelle: 'Examen clinique (TA, T°, utérus, lochies, seins)', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
        const ChampDef(nom: 'supplementation', libelle: 'Supplémentation (Vit A, fer, folates)'),
        const ChampDef(nom: 'conseilPF', libelle: 'Conseil et adoption PF post-partum', type: TypeChamp.case_),
        const ChampDef(
            nom: 'etatNouveauNe', libelle: 'État du nouveau-né (poids, ictère, cordon, allaitement)', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
        ChampDef(nom: 'sageFemme', libelle: 'Sage-femme', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
      ],
      valeursInitiales: () => {},
      refuser: (v) => matRefusCpon(hemorragieAntePartum: v['hemorragieAntePartum'] == true, etiologie: v['etiologieAnte']),
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        FiltreTableau(nom: 'type', libelle: 'Séance', options: [for (final t in matTypesCpon) OptionChamp('${t['code']}', '${t['label']}')]),
        _oneNon('hemorragieAntePartum', 'Hémorragie ante-partum', 'Oui', 'Non', (r) => matVrai(r['hemorragieAntePartum'])),
      ],
      kpis: (ctx, rows) => [
        _kpi('CPoN enregistrées', matNombre(rows.length), LucideIcons.stethoscope, TonSigh.navy),
        _kpi('Hémorragies ante-partum', matNombre(rows.where((r) => matVrai(r['hemorragieAntePartum'])).length), LucideIcons.droplets, TonSigh.danger,
            '★ variable nouvelle du rapport'),
        _kpi('HPP', matNombre(rows.where((r) => matVrai(r['hpp'])).length), LucideIcons.droplet, TonSigh.attention),
        _kpi('Conseils PF donnés', matPct(rows.where((r) => matVrai(r['conseilPF'])).length, rows.length), LucideIcons.heartHandshake, TonSigh.succes),
      ],
      etat: (ctx, r) {
        final t = matTypeCpon(r['type']);
        matImprimer(ctx,
            titre: 'Consultation post-natale',
            sousTitre: '${_seance(r['type'])} — ${r['reference']}',
            cartouche: [
              ('Accouchée', '${r['patient']}'),
              ('Dossier', '${r['patientCode']}'),
              ('Date', matDateFR(r['date'])),
              ('Séance', t != null ? '${t['label']} (${t['fenetre']})' : '${r['type']}'),
              ('Sage-femme', '${r['sageFemme'] ?? ''}'),
              ('Accouchement', matOuTiret(r['accouchementRef'])),
            ],
            blocs: [
              matBlocRubriques([
                ('Hémorragie ANTE-partum', matVrai(r['hemorragieAntePartum']) ? 'OUI — ${r['etiologieAnte'] ?? ''}' : 'Non'),
                ('Hémorragie du post-partum (HPP)', matVrai(r['hpp']) ? 'OUI' : 'Non'),
                ('Examen clinique', matOuTiret(r['examen'])),
                ('Supplémentation', matOuTiret(r['supplementation'])),
                ('Conseil PF post-partum', matVrai(r['conseilPF']) ? 'Donné' : 'Non'),
                ('État du nouveau-né', matOuTiret(r['etatNouveauNe'])),
              ], libelleValeur: 'Valeur')
            ],
            signatures: [Signature('La Sage-femme', nom: '${r['sageFemme'] ?? ''}')]);
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-planification — 15 méthodes, codification A/N (Module H)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranPlanification extends StatelessWidget with EcranMaquette {
  const EcranPlanification({super.key});
  @override
  String get titre => 'Planification familiale';
  @override
  String get description => 'Registre PF : 15 méthodes contraceptives, codification A/N, rendez-vous de renouvellement.';
  @override
  String get regle =>
      'Choix exclusif parmi les 15 méthodes du rapport ; la colonne A/N suit la codification nationale — A = nouvelle acceptante, N = ancienne (renouvellement ou changement). Les actes de PF sont non couverts par les assurances : la grille tarifaire le porte en toutes lettres.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('PF-', c.magasin.collection('planificationFamiliale').toutes);
      v['methodeLabel'] = matMethodePf(v['methode'])?['label'] ?? v['methode'];
      return matSansNuls(v);
    }

    return CrudMat(
      collection: c.magasin.collection('planificationFamiliale'),
      entite: 'consultation PF',
      entiteP: 'consultations PF',
      prefixeId: 'PLF',
      triInitial: 'date',
      sensInitial: 'desc',
      plageChamp: 'date',
      source: 'Rapport officiel maternité du 27/08/2026 — Module H et tableaux B et 5.',
      colonnes: [
        _ref('N°'),
        _date('date', 'Date'),
        _patientLigne('Cliente'),
        ColonneTableau(
            cle: 'acceptante',
            libelle: 'A/N',
            texte: (r) => r['acceptante'] == 'A' ? 'A — nouvelle' : 'N — ancienne',
            rendu: (_, r) => BadgeSigh(r['acceptante'] == 'A' ? 'A — nouvelle' : 'N — ancienne', ton: r['acceptante'] == 'A' ? TonSigh.succes : TonSigh.info)),
        ColonneTableau(
            cle: 'methode',
            libelle: 'Méthode adoptée',
            texte: (r) => '${r['methodeLabel'] ?? r['methode'] ?? ''}${matMethodePf(r['methode']) != null ? ' ${matMethodePf(r['methode'])!['categorie']}' : ''}',
            rendu: (_, r) {
              final m = matMethodePf(r['methode']);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${r['methodeLabel'] ?? r['methode'] ?? ''}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14)),
                if (m != null) matMuet('${m['categorie']}'),
              ]);
            }),
        ColonneTableau(cle: 'rdv', libelle: 'Prochain RDV', sansCoupure: true, texte: (r) => matVrai(r['rdv']) ? matDateFR(r['rdv']) : '—'),
        const ColonneTableau(cle: 'sageFemme', libelle: 'Sage-femme'),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Cliente', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'acceptante',
            libelle: 'Statut d’acceptante (A/N)',
            type: TypeChamp.select,
            requis: true,
            options: [for (final s in matStatutsAcceptante) OptionChamp('${s['code']}', '${s['label']}')]),
        ChampDef(
            nom: 'methode',
            libelle: 'Méthode contraceptive adoptée',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [for (final x in matMethodesPf) OptionChamp('${x['code']}', '${x['label']}')],
            aide: 'Les 15 méthodes du rapport, en choix exclusif.'),
        const ChampDef(nom: 'methodeAnterieure', libelle: 'Méthode antérieure utilisée'),
        const ChampDef(nom: 'ddr', libelle: 'Date des dernières règles (DDR)', type: TypeChamp.date),
        const ChampDef(nom: 'constantes', libelle: 'Constantes (poids, TA, IMC)'),
        const ChampDef(nom: 'rdv', libelle: 'Prochain rendez-vous', type: TypeChamp.date),
        ChampDef(nom: 'sageFemme', libelle: 'Sage-femme', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
      ],
      valeursInitiales: () => {},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        FiltreTableau(nom: 'acceptante', libelle: 'A/N', options: const [OptionChamp('A', 'Nouvelles acceptantes (A)'), OptionChamp('N', 'Anciennes (N)')]),
        FiltreTableau(nom: 'methode', libelle: 'Méthode', options: [for (final x in matMethodesPf) OptionChamp('${x['code']}', '${x['label']}')]),
      ],
      kpis: (ctx, rows) => [
        _kpi('Consultations PF', matNombre(rows.length), LucideIcons.heartHandshake, TonSigh.navy),
        _kpi('Nouvelles acceptantes (A)', matNombre(rows.where((r) => r['acceptante'] == 'A').length), LucideIcons.userPlus, TonSigh.succes,
            'Indicateur DHIS2 — taux d’acceptation'),
        _kpi('Méthodes longue durée',
            matNombre(rows.where((r) => RegExp('Longue').hasMatch('${matMethodePf(r['methode'])?['categorie'] ?? ''}')).length), LucideIcons.calendarRange, TonSigh.info),
        _kpi('Méthodes distinctes', '${matNombre({for (final r in rows) '${r['methode']}'}.length)} / 15', LucideIcons.listChecks, TonSigh.neutre),
      ],
      etat: (ctx, r) {
        final m = matMethodePf(r['methode']);
        matImprimer(ctx,
            titre: 'Fiche de planification familiale',
            sousTitre: '${r['reference']}',
            cartouche: [
              ('Cliente', '${r['patient']}'),
              ('Dossier', '${r['patientCode']}'),
              ('Date', matDateFR(r['date'])),
              ('Statut', r['acceptante'] == 'A' ? 'A — nouvelle acceptante' : 'N — ancienne acceptante'),
              ('Sage-femme', '${r['sageFemme'] ?? ''}'),
              ('Prochain RDV', matVrai(r['rdv']) ? matDateFR(r['rdv']) : '—'),
            ],
            blocs: [
              matBlocRubriques([
                ('Méthode adoptée', '${r['methodeLabel'] ?? r['methode']}'),
                ('Catégorie', m == null ? '—' : '${m['categorie']}'),
                ('Spécification', m == null ? '—' : '${m['specification']}'),
                ('Méthode antérieure', matOuTiret(r['methodeAnterieure'])),
                ('DDR', matVrai(r['ddr']) ? matDateFR(r['ddr']) : '—'),
                ('Constantes', matOuTiret(r['constantes'])),
              ], libelleValeur: 'Valeur')
            ],
            signatures: [Signature('La Sage-femme', nom: '${r['sageFemme'] ?? ''}')]);
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-sonu — registre SONUB / SONUC (Module F)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranSonu extends StatelessWidget with EcranMaquette {
  const EcranSonu({super.key});
  @override
  String get titre => 'Registre SONUB / SONUC';
  @override
  String get description => 'Urgences obstétricales et néonatales : les 10 fonctions officielles, gestes horodatés, évolution.';
  @override
  String get regle =>
      'Les 7 fonctions SONUB (base) et les 3 SONUC (transfusion, chirurgie obstétricale, césarienne) du rapport, en liste fermée, plus une case « autre geste » en texte libre horodaté. C’est la cotation exacte des gestes d’urgence vitale posés — elle classe la structure SONUB ou SONUC dans les rapports nationaux.';

  static List<int> _fonctions(Object? v) => [for (final x in (v as List? ?? const [])) matNum(x)?.toInt() ?? 0];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('SONU-', c.magasin.collection('registreSONU').toutes);
      v['fonctions'] = (_fonctions(v['fonctions'])..sort());
      _nombres(v, const ['gestite', 'parite']);
      matRecomposerDateHeure(v, 'dateHeure');
      return matSansNuls(v);
    }

    bool sonuc(Fiche r) => _fonctions(r['fonctions']).any((n) => n >= 8);
    return CrudMat(
      collection: c.magasin.collection('registreSONU'),
      entite: 'urgence obstétricale',
      entiteP: 'urgences obstétricales',
      prefixeId: 'SON',
      triInitial: 'dateHeure',
      sensInitial: 'desc',
      source: 'Rapport officiel maternité du 27/08/2026 — Module F et tableaux A et 3.',
      colonnes: [
        _ref('N°'),
        ColonneTableau(
            cle: 'dateHeure', libelle: 'Arrivée', sansCoupure: true, valeur: (r) => matMs(r['dateHeure']), texte: (r) => matDateHeure(r['dateHeure'])),
        _patientLigne('Patiente'),
        ColonneTableau(
            cle: 'evacuation',
            libelle: 'Provenance',
            texte: (r) => matVrai(r['evacuation']) ? 'Évacuée — ${r['provenance'] ?? ''}' : 'Venue d’elle-même',
            rendu: (_, r) => matVrai(r['evacuation'])
                ? BadgeSigh('Évacuée — ${r['provenance'] ?? ''}', ton: TonSigh.attention)
                : const Text('Venue d’elle-même', style: TextStyle(color: JetonsShell.slate500, fontSize: 12))),
        ColonneTableau(
            cle: 'fonctions',
            libelle: 'Fonctions SONU posées',
            texte: (r) => [for (final n in _fonctions(r['fonctions'])) '$n — ${matFonctionSonu(n)?['label'] ?? ''}'].join(' '),
            rendu: (_, r) => matBadges([
                  for (final n in _fonctions(r['fonctions']))
                    ('$n — ${matFonctionSonu(n)?['label'] ?? ''}', matFonctionSonu(n)?['type'] == 'SONUC' ? TonSigh.danger : TonSigh.info)
                ])),
        ColonneTableau(
            cle: 'evolution',
            libelle: 'Évolution',
            texte: (r) => matOuTiret(r['evolution']),
            rendu: (_, r) => BadgeSigh(matOuTiret(r['evolution']),
                ton: r['evolution'] == 'Favorable' ? TonSigh.succes : (r['evolution'] == 'Décédée' ? TonSigh.danger : TonSigh.attention))),
        const ColonneTableau(cle: 'agent', libelle: 'Agent'),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Patiente', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        ...matChampsDateHeure('dateHeure', 'Date et heure d’arrivée'),
        const ChampDef(nom: 'gestite', libelle: 'Gestité', type: TypeChamp.nombre),
        const ChampDef(nom: 'parite', libelle: 'Parité', type: TypeChamp.nombre),
        const ChampDef(nom: 'evacuation', libelle: 'Évacuée d’une autre structure', type: TypeChamp.case_),
        const ChampDef(nom: 'provenance', libelle: 'Provenance (CS / localité)'),
        const ChampDef(nom: 'diagnosticEvacuation', libelle: 'Diagnostic d’évacuation'),
        const ChampDef(nom: 'heureAbordVeineux', libelle: 'Heure de l’abord veineux', indicatif: '08h15'),
        const ChampDef.section('Les 10 fonctions SONU — diagnostic après examen'),
        ChampDef(
            nom: 'fonctions',
            libelle: 'Fonctions posées',
            type: TypeChamp.multiselect,
            requis: true,
            col: ColChamp.plein,
            options: [for (final f in matFonctionsSonu) OptionChamp('${f['num']}', '${f['num']} — ${f['label']} (${f['type']})')]),
        const ChampDef(nom: 'autreGeste', libelle: 'Autre geste SONU (texte libre)', col: ColChamp.plein),
        const ChampDef(nom: 'heureFinGestes', libelle: 'Heure de fin des gestes', indicatif: '10h40'),
        const ChampDef.section('Issue'),
        ChampDef(nom: 'evolution', libelle: 'Évolution', type: TypeChamp.select, requis: true, options: _opts(const ['Favorable', 'Référée', 'Décédée'])),
        ChampDef(nom: 'agent', libelle: 'Agent (nom et qualification)', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
      ],
      valeursInitiales: () => {},
      valeursEdition: (f) => {...matValeursEdition(f, const ['dateHeure']), 'fonctions': [for (final n in _fonctions(f['fonctions'])) '$n']},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        FiltreTableau(
            nom: 'niveau',
            libelle: 'Niveau',
            options: const [OptionChamp('sonub', 'SONUB seulement (1-7)'), OptionChamp('sonuc', 'Avec fonction SONUC (8-10)')],
            correspond: (r, v) => v == 'sonuc' ? sonuc(r) : !sonuc(r)),
        FiltreTableau(nom: 'evolution', libelle: 'Évolution', options: _opts(const ['Favorable', 'Référée', 'Décédée'])),
      ],
      kpis: (ctx, rows) => [
        _kpi('Urgences enregistrées', matNombre(rows.length), LucideIcons.siren, TonSigh.danger),
        _kpi('Avec fonction SONUC', matNombre(rows.where(sonuc).length), LucideIcons.building2, TonSigh.attention, 'transfusion, chirurgie, césarienne'),
        _kpi('Réanimations nouveau-né (f7)', matNombre(rows.where((r) => _fonctions(r['fonctions']).contains(7)).length), LucideIcons.baby, TonSigh.info),
        _kpi('Évolutions favorables', matPct(rows.where((r) => r['evolution'] == 'Favorable').length, rows.length), LucideIcons.heart, TonSigh.succes),
      ],
      etat: (ctx, r) => matImprimer(ctx,
          titre: 'Registre SONUB / SONUC — fiche d’urgence',
          sousTitre: '${r['reference']}',
          cartouche: [
            ('Patiente', '${r['patient']}'),
            ('Dossier', '${r['patientCode']}'),
            ('Arrivée', matDateHeure(r['dateHeure'])),
            ('Gestité / parité', '${r['gestite'] != null ? matTexteNombre(r['gestite']) : '—'} / ${r['parite'] != null ? matTexteNombre(r['parite']) : '—'}'),
            ('Provenance', matVrai(r['evacuation']) ? 'Évacuée — ${r['provenance'] ?? ''}' : 'Venue d’elle-même'),
            ('Évolution', '${r['evolution'] ?? ''}'),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'N°', valeur: (l) => '${l['n']}', droite: true),
              ColonneEtat(libelle: 'Fonction SONU posée', valeur: (l) => matFonctionSonu(l['n'])?['label'] ?? '${l['n']}'),
              ColonneEtat(libelle: 'Type', valeur: (l) => matFonctionSonu(l['n'])?['type'] ?? '—'),
            ], lignes: [
              for (final n in _fonctions(r['fonctions'])) {'n': n}
            ])),
            matBlocRubriques([
              ('Diagnostic d’évacuation', matOuTiret(r['diagnosticEvacuation'])),
              ('Heure de l’abord veineux', matOuTiret(r['heureAbordVeineux'])),
              ('Autre geste SONU', matOuTiret(r['autreGeste'])),
              ('Heure de fin des gestes', matOuTiret(r['heureFinGestes'])),
            ], libelleValeur: 'Valeur'),
          ],
          signatures: [Signature('L’Agent', nom: '${r['agent'] ?? ''}', mention: 'Nom, prénom et qualification')]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-ptme — registre quadripartite (Module I)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranPtme extends StatelessWidget with EcranMaquette {
  const EcranPtme({super.key});
  @override
  String get titre => 'Registre PTME';
  @override
  String get description => 'Prévention de la transmission mère-enfant : dépistage, protocole, enfants exposés, dispensation ARV.';
  @override
  String get regle =>
      'Quatre volets, comme le registre national : 1 dépistage triple (VIH, Ag HBs, syphilis), 2 protocole et allaitement, 3 enfants exposés (PCR-1 à 6 semaines, PCR-2 à 9 mois, sérologie à 18 mois), 4 dispensation mensuelle des ARV. Données parmi les plus sensibles du dossier — le cloisonnement RBAC de M4 s’applique pleinement (RG-13).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final p = matPtme;
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('PTME-', c.magasin.collection('ptme').toutes);
      return matSansNuls(v);
    }

    List<String> liste(String k) => _liste(p[k]);
    return CrudMat(
      collection: c.magasin.collection('ptme'),
      entite: 'fiche PTME',
      entiteP: 'fiches PTME',
      prefixeId: 'PTM',
      triInitial: 'reference',
      source: 'Rapport officiel maternité du 27/08/2026 — Module I et tableau 6 (protocoles PTME).',
      colonnes: [
        _ref('N°'),
        _patientLigne('Mère suivie'),
        ColonneTableau(
            cle: 'chargeVirale',
            libelle: 'Charge virale',
            texte: (r) => matOuTiret(r['chargeVirale']),
            rendu: (_, r) => BadgeSigh(matOuTiret(r['chargeVirale']), ton: r['chargeVirale'] == 'Indétectable' ? TonSigh.succes : TonSigh.attention)),
        const ColonneTableau(cle: 'allaitement', libelle: 'Allaitement'),
        ColonneTableau(
            cle: 'pcr1',
            libelle: 'Suivi enfant',
            texte: (r) => 'PCR naissance : ${matVrai(r['pcrNaissance']) ? r['pcrNaissance'] : 'en attente'} PCR-1 (6 sem) : ${matVrai(r['pcr1']) ? r['pcr1'] : 'à faire'} · PCR-2 (9 mois) : ${matVrai(r['pcr2']) ? r['pcr2'] : 'à faire'}'),
        ColonneTableau(
            cle: 'dispensations',
            libelle: 'Dispensations ARV',
            droite: true,
            valeur: (r) => ((r['dispensations'] as List?) ?? const []).length,
            texte: (r) {
              final l = ((r['dispensations'] as List?) ?? const []);
              return '${l.where((d) => (d as Map)['servie'] == true).length} / ${l.length}';
            }),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Mère suivie', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        const ChampDef.section('Volet 1 — dépistage (CPN)'),
        ChampDef(nom: 'vihTrimestre', libelle: 'Trimestre du dépistage VIH', type: TypeChamp.select, options: _opts(const ['1', '2', '3'])),
        ChampDef(nom: 'vihType', libelle: 'Type', type: TypeChamp.select, options: _opts(const ['VIH-1', 'VIH-2', 'VIH-1+2'])),
        ChampDef(nom: 'agHbs', libelle: 'Ag HBs (hépatite B)', type: TypeChamp.select, options: _opts(const ['Négatif', 'Positif'])),
        ChampDef(nom: 'syphilis', libelle: 'Syphilis (TPHA/VDRL)', type: TypeChamp.select, options: _opts(const ['Négatif', 'Positif'])),
        const ChampDef(nom: 'chargeVirale', libelle: 'Charge virale'),
        const ChampDef.section('Volet 2 — protocole mère et nouveau-né'),
        const ChampDef(nom: 'protocoleARV', libelle: 'Protocole ARV'),
        ChampDef(nom: 'dureeARV', libelle: 'Durée du traitement', type: TypeChamp.select, options: _opts(liste('dureesARV'))),
        ChampDef(nom: 'allaitement', libelle: 'Mode d’allaitement', type: TypeChamp.select, requis: true, options: _opts(liste('allaitements'))),
        ChampDef(
            nom: 'prophylaxieNN',
            libelle: 'Prophylaxie ARV du nouveau-né',
            type: TypeChamp.select,
            options: [for (final x in (p['prophylaxiesNN'] as List)) OptionChamp('${(x as Map)['code']}', '${x['code']} = ${x['label']}')]),
        const ChampDef.section('Volet 3 — enfant exposé'),
        ChampDef(nom: 'pcrNaissance', libelle: 'PCR à la naissance', type: TypeChamp.select, options: _opts(const ['En attente', 'Négatif', 'Positif'])),
        ChampDef(nom: 'pcr1', libelle: 'PCR-1 (6 semaines)', type: TypeChamp.select, options: _opts(const ['', 'Négatif', 'Positif'])),
        ChampDef(nom: 'pcr2', libelle: 'PCR-2 (9 mois)', type: TypeChamp.select, options: _opts(const ['', 'Négatif', 'Positif'])),
        ChampDef(nom: 'serologie18m', libelle: 'Sérologie VIH (18 mois)', type: TypeChamp.select, options: _opts(const ['', 'Négatif', 'Positif'])),
        const ChampDef(nom: 'ctm', libelle: 'Prophylaxie Cotrimoxazole (CTM)', type: TypeChamp.case_),
        const ChampDef(nom: 'hepBJ0', libelle: 'Vaccination hépatite B à J0', type: TypeChamp.case_),
      ],
      valeursInitiales: () => {},
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      kpis: (ctx, rows) => [
        _kpi('Mères suivies', matNombre(rows.length), LucideIcons.shieldCheck, TonSigh.navy),
        _kpi('Charges virales indétectables', matNombre(rows.where((r) => r['chargeVirale'] == 'Indétectable').length), LucideIcons.circleCheck, TonSigh.succes),
        _kpi('PCR-1 rendues', matNombre(rows.where((r) => matVrai(r['pcr1'])).length), LucideIcons.flaskConical, TonSigh.info),
        _kpi('Sous CTM', matNombre(rows.where((r) => matVrai(r['ctm'])).length), LucideIcons.pill, TonSigh.neutre),
      ],
      detail: (ctx, r) {
        final disp = [for (final d in ((r['dispensations'] as List?) ?? const [])) (d as Map).cast<String, Object?>()];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          matNote('Fiche sensible — le détail reste derrière les permissions de M4 ; il ne figure ni dans les notifications, ni dans les alertes sonores.',
              ton: TonSigh.attention, icone: LucideIcons.lock),
          const SizedBox(height: 16),
          DescListeSigh([
            ('Référence', '${r['reference']}'),
            ('Mère', '${r['patient']} — ${r['patientCode']}'),
            ('Dépistage', 'VIH ${matOuTiret(r['vihType'])} (T${matOuTiret(r['vihTrimestre'])}) · Ag HBs ${matOuTiret(r['agHbs'])} · Syphilis ${matOuTiret(r['syphilis'])}'),
            ('Charge virale', matOuTiret(r['chargeVirale'])),
            ('Protocole', '${matOuTiret(r['protocoleARV'])} — ${matOuTiret(r['dureeARV'])}'),
            ('Allaitement', matOuTiret(r['allaitement'])),
            ('Prophylaxie NN', matOuTiret(r['prophylaxieNN'])),
            ('Enfant exposé',
                'PCR naissance ${matOuTiret(r['pcrNaissance'])} · PCR-1 ${matOuTiret(r['pcr1'])} · PCR-2 ${matOuTiret(r['pcr2'])} · Séro 18 m ${matOuTiret(r['serologie18m'])}'),
            ('CTM / Hép. B J0', '${matVrai(r['ctm']) ? 'CTM' : '—'} / ${matVrai(r['hepBJ0']) ? 'fait' : '—'}'),
          ]),
          const SizedBox(height: 16),
          const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Volet 4 — dispensation mensuelle des ARV',
                  style: TextStyle(color: JetonsShell.slate900, fontSize: 14, fontWeight: FontWeight.w600))),
          if (disp.isEmpty)
            const VideSigh('Aucune dispensation tracée.', icone: LucideIcons.pill)
          else
            MiniTableauSigh(
                colonnes: [ColonneMini('Mois', (d) => '${d['mois']}'), ColonneMini('Servie', (d) => d['servie'] == true ? 'Oui' : 'MANQUÉE')],
                lignes: disp),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m4-soins-curatifs — Case 27 restructurée (Module E)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranSoinsCuratifs extends StatelessWidget with EcranMaquette {
  const EcranSoinsCuratifs({super.key});
  @override
  String get titre => 'Soins curatifs & urgences maternité';
  @override
  String get description => 'Registre des consultations curatives : MILDA, femmes référées d’urgence, devenir (Case 27).';
  @override
  String get regle =>
      'La Case 27 du registre national est restructurée comme le rapport le demande : « femme observée » (oui/non), « femme hospitalisée » (oui/non) et « nombre de jours » — ce dernier n’a de sens que si l’hospitalisation est cochée, et le formulaire le tient. Les trois variables de femmes en travail référées d’urgence alimentent l’audit des transferts.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    Fiche fiche(BuildContext ctx, Fiche v, Fiche? e) {
      matRattacher(v, matFemmes(c.magasin));
      v['reference'] = e?['reference'] ?? matReferenceSuivante('SCM-', c.magasin.collection('soinsCuratifsMaternite').toutes);
      _nombres(v, const ['joursHospitalisation']);
      if (!matVrai(v['femmeHospitalisee'])) v['joursHospitalisation'] = null;
      return matSansNuls(v);
    }

    String urgence(Fiche r) => matUrgenceMaternite(r['urgenceMaternite'])?['label'] as String? ?? '—';
    return CrudMat(
      collection: c.magasin.collection('soinsCuratifsMaternite'),
      entite: 'soin curatif',
      entiteP: 'soins curatifs',
      prefixeId: 'SCM',
      triInitial: 'date',
      sensInitial: 'desc',
      plageChamp: 'date',
      source: 'Rapport officiel maternité du 27/08/2026 — Module E et tableau 2 (registre de soins curatifs).',
      colonnes: [
        _ref('N°'),
        _date('date', 'Date'),
        _patientLigne('Consultante'),
        const ColonneTableau(cle: 'diagnostic', libelle: 'Diagnostic'),
        _oui('mildaDelivree', 'MILDA', 'Délivrée', TonSigh.succes, '—'),
        ColonneTableau(
            cle: 'urgenceMaternite',
            libelle: 'Urgence maternité',
            texte: urgence,
            rendu: (_, r) => matPresent(r['urgenceMaternite']) ? BadgeSigh(urgence(r), ton: TonSigh.danger) : matMuet('—')),
        ColonneTableau(
            cle: 'femmeHospitalisee',
            libelle: 'Devenir (Case 27)',
            texte: (r) => '${matVrai(r['femmeObservee']) ? 'Observée' : ''}${matVrai(r['femmeHospitalisee']) ? ' · Hospitalisée ${r['joursHospitalisation'] != null ? matTexteNombre(r['joursHospitalisation']) : '?'} j' : ''}'.trim(),
            rendu: (_, r) {
              final out = <(String, TonSigh)>[
                if (matVrai(r['femmeObservee'])) ('Observée', TonSigh.info),
                if (matVrai(r['femmeHospitalisee']))
                  ('Hospitalisée — ${r['joursHospitalisation'] != null ? matTexteNombre(r['joursHospitalisation']) : '?'} j', TonSigh.attention),
              ];
              return out.isEmpty ? matMuet('Retour à domicile') : matBadges(out);
            }),
        const ColonneTableau(cle: 'agent', libelle: 'Agent'),
      ],
      champs: (m) => [
        ChampDef(nom: 'patientCode', libelle: 'Consultante', type: TypeChamp.select, requis: true, options: matOptionsFemmes(m), col: ColChamp.plein),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        ChampDef(nom: 'trancheAge', libelle: 'Tranche d’âge', type: TypeChamp.select, options: _opts(matTranchesAgeCuratif)),
        const ChampDef(
            nom: 'symptomes', libelle: 'Symptômes et signes (si toux, préciser la durée)', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
        const ChampDef(nom: 'diagnostic', libelle: 'Diagnostic', requis: true),
        const ChampDef(nom: 'traitement', libelle: 'Traitement / posologie'),
        const ChampDef(nom: 'mildaDelivree', libelle: 'MILDA délivrée', type: TypeChamp.case_),
        ChampDef(
            nom: 'urgenceMaternite',
            libelle: 'Femme en travail référée d’urgence',
            type: TypeChamp.select,
            options: [const OptionChamp('', '— Sans objet —'), for (final u in matUrgencesMaternite) OptionChamp('${u['code']}', '${u['label']}')]),
        const ChampDef.section('Case 27 — devenir de la patiente'),
        const ChampDef(nom: 'femmeObservee', libelle: 'Femme observée', type: TypeChamp.case_),
        const ChampDef(nom: 'femmeHospitalisee', libelle: 'Femme hospitalisée', type: TypeChamp.case_),
        const ChampDef(
            nom: 'joursHospitalisation',
            libelle: 'Nombre de jours d’hospitalisation',
            type: TypeChamp.nombre,
            aide: 'Ne se renseigne que si l’hospitalisation est cochée — le formulaire le contrôle.'),
        ChampDef(nom: 'agent', libelle: 'Agent', type: TypeChamp.select, requis: true, options: matSagesFemmes(m)),
      ],
      valeursInitiales: () => {},
      refuser: (v) => matRefusCase27(hospitalisee: v['femmeHospitalisee'] == true, jours: v['joursHospitalisation']),
      transformer: (ctx, v) => fiche(ctx, v, null),
      transformerExistante: fiche,
      referenceToast: (f) => '${f['reference'] ?? ''}',
      filtres: [
        FiltreTableau(nom: 'urgenceMaternite', libelle: 'Urgences', options: [for (final u in matUrgencesMaternite) OptionChamp('${u['code']}', '${u['label']}')]),
        FiltreTableau(
            nom: 'devenir',
            libelle: 'Devenir',
            options: const [OptionChamp('obs', 'Observées'), OptionChamp('hosp', 'Hospitalisées')],
            correspond: (r, v) => v == 'obs' ? matVrai(r['femmeObservee']) : matVrai(r['femmeHospitalisee'])),
      ],
      kpis: (ctx, rows) => [
        _kpi('Consultations curatives', matNombre(rows.length), LucideIcons.stethoscope, TonSigh.navy),
        _kpi('MILDA délivrées', matNombre(rows.where((r) => matVrai(r['mildaDelivree'])).length), LucideIcons.tent, TonSigh.succes),
        _kpi('Femmes référées d’urgence', matNombre(rows.where((r) => matVrai(r['urgenceMaternite'])).length), LucideIcons.siren, TonSigh.danger,
            'les trois variables normalisées'),
        _kpi('Hospitalisées (Case 27)', matNombre(rows.where((r) => matVrai(r['femmeHospitalisee'])).length), LucideIcons.bedDouble, TonSigh.attention),
      ],
    );
  }
}

bool matPresent(Object? v) => v != null && v != '';
