import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../cfg/cfb_configuration_fiscale.dart';
import '../cfg/cfa_commun.dart' show cfaPile, cfaCode;
import 'cpc_commun.dart';

/// `m12-calendrier-fiscal` : « Calendrier fiscal mensuel » (lot A3b, 09/11/2026 ; ouvert au poste par le lot FISC-2, Direction du 16/11/2026) : la grille du mois, en LECTURE.
///
/// Une VUE du même registre que le suivi (collection `echeancesFiscales`) : aucune seconde collection, aucun calcul de date à part (la date vient de l'échéance,
/// reportée au jour ouvrable suivant par le moteur), l'état vient de `cpcCalculerEtat`, donc des MÊMES paramètres que le suivi (les délais d'alerte du calendrier,
/// lus À LA DATE : `cfbDelaisFiscauxALaDate`). Elle ne modifie rien ; ses droits sont ceux de `m12-echeances`.
class EcranCalendrierFiscal extends StatefulWidget with EcranMaquette {
  const EcranCalendrierFiscal({super.key});

  @override
  String get titre => 'Calendrier fiscal mensuel';

  @override
  String get description => 'Les échéances fiscales et sociales du mois, jour par jour, avec leur état : payée, en retard, à payer, à venir.';

  @override
  String get regle =>
      'Cette vue lit le même registre que le suivi des échéances : une échéance, son jour et son état y sont identiques. Rien ne se saisit ici ; le paiement se valide au suivi. Un jour qui tombe un samedi ou un dimanche est reporté au jour ouvrable suivant, et les seuils « à payer » et « déclaration » sont ceux des paramètres comptables.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Suivi des échéances',
            icone: LucideIcons.calendarClock,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m12-echeances')),
        BoutonSigh(
            libelle: 'Obligations & règles',
            icone: LucideIcons.bookOpenCheck,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('cfg-comptabilite')),
      ];

  @override
  State<EcranCalendrierFiscal> createState() => _EtatCalendrierFiscal();
}

const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

class _EtatCalendrierFiscal extends State<EcranCalendrierFiscal> {
  bool _demarre = false;
  int? _annee, _mois0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_demarre) return;
    _demarre = true;
    final c = ContexteEcran.of(context);
    _annee = c.aujourdhui.year;
    _mois0 = c.aujourdhui.month - 1;
    // Comme le suivi : un exercice sans échéance les reçoit depuis la version EN VIGUEUR des obligations (écriture différée après la construction).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ConfigurationFiscalePoste.amorcer(c.magasin);
      ConfigurationFiscalePoste(c).amorcerEcheances(c.aujourdhui.year);
    });
  }

  void _decaler(int n) {
    final d = DateTime(_annee!, _mois0! + 1 + n, 1);
    setState(() {
      _annee = d.year;
      _mois0 = d.month - 1;
    });
  }

  TonSigh _ton(String t) => switch (t) {
        'succes' => TonSigh.succes,
        'danger' => TonSigh.danger,
        'attention' => TonSigh.attention,
        'info' => TonSigh.info,
        _ => TonSigh.neutre,
      };

  (Color, Color, Color) _couleurs(String etat) => switch (etat) {
        'payee' => (JetonsShell.success50, JetonsShell.success200, JetonsShell.success700),
        'en_retard' => (JetonsShell.danger50, JetonsShell.danger200, JetonsShell.danger700),
        'a_payer' => (JetonsShell.warning50, JetonsShell.warning200, JetonsShell.warning700),
        'declaration' => (JetonsShell.info50, JetonsShell.info200, JetonsShell.info700),
        _ => (JetonsShell.slate50, JetonsShell.slate200, JetonsShell.slate600),
      };

  static String _delai(Fiche e) {
    if (e['paye'] == true) return 'réglée';
    final j = nombreOuZero(e['jours']).toInt();
    return j < 0 ? '${j.abs()} j de retard' : 'dans $j j';
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection('echeancesFiscales'), c.magasin.collection('parametresFiscaux')]),
        builder: (ctx, _) {
          final a = _annee!, m0 = _mois0!;
          final delais = cfbDelaisFiscauxALaDate(c.magasin.collection('parametresFiscaux').actives, c.aujourdhui);
          final debut = '$a-${(m0 + 1).toString().padLeft(2, '0')}-01';
          final nb = DateTime(a, m0 + 2, 0).day;
          final fin = '$a-${(m0 + 1).toString().padLeft(2, '0')}-${nb.toString().padLeft(2, '0')}';
          final rows = [
            for (final e in cpcLignesEcheances(c.magasin.collection('echeancesFiscales').actives, c.aujourdhui, delaiAPayer: delais.delaiAPayer, delaiDeclaration: delais.delaiDeclaration))
              if ('${e['echeance']}'.compareTo(debut) >= 0 && '${e['echeance']}'.compareTo(fin) <= 0) e
          ]..sort((x, y) {
              final k = '${x['echeance']}'.compareTo('${y['echeance']}');
              return k != 0 ? k : '${x['code']}'.compareTo('${y['code']}');
            });
          final parJour = <String, List<Fiche>>{};
          for (final e in rows) {
            parJour.putIfAbsent('${e['echeance']}', () => []).add(e);
          }
          final premier = DateTime(a, m0 + 1, 1);
          final decalage = (premier.weekday + 6) % 7;
          final jourJ = '${c.aujourdhui.year}-${c.aujourdhui.month.toString().padLeft(2, '0')}-${c.aujourdhui.day.toString().padLeft(2, '0')}';
          final titre = '${_mois[m0][0].toUpperCase()}${_mois[m0].substring(1)} $a';
          final cellules = <Widget>[
            for (final j in const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'])
              Center(child: Text(j.toUpperCase(), style: const TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate500))),
            for (var v = 0; v < decalage; v++) const SizedBox.shrink(),
            for (var j = 1; j <= nb; j++)
              () {
                final cle = '$a-${(m0 + 1).toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}';
                final we = DateTime(a, m0 + 1, j).weekday >= 6;
                return Container(
                    key: Key('cal:jour:$cle'),
                    constraints: const BoxConstraints(minHeight: 80),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: we ? JetonsShell.slate50 : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: we ? JetonsShell.slate100 : JetonsShell.slate200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$j',
                          style: TextStyle(
                              fontSize: 12,
                              height: 16 / 12,
                              fontWeight: FontWeight.w600,
                              decoration: cle == jourJ ? TextDecoration.underline : null,
                              color: cle == jourJ ? JetonsShell.navy700 : JetonsShell.slate500)),
                      for (final e in parJour[cle] ?? const <Fiche>[])
                        Builder(builder: (_) {
                          final (fond, bord, texte) = _couleurs('${e['etat']}');
                          return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: InkWell(
                                  key: Key('cal:ech:${e['code']}:$cle'),
                                  onTap: () => c.aller('m12-echeances'),
                                  child: Tooltip(
                                      message: '${e['libelle']} (${cpcEtat('${e['etat']}').$2}, ${_delai(e)})',
                                      child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          decoration: BoxDecoration(color: fond, border: Border.all(color: bord), borderRadius: BorderRadius.circular(4)),
                                          child: Text('${e['code']}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: texte))))));
                        }),
                    ]));
              }(),
          ];
          final retard = rows.where((e) => e['etat'] == 'en_retard').length;
          return cfaPile([
            Row(children: [
              BoutonSigh(key: const Key('cal:precedent'), libelle: 'Mois précédent', icone: LucideIcons.chevronLeft, variante: VarianteBouton.secondaire, onPressed: () => _decaler(-1)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(titre, key: const Key('cal:titre'), style: const TextStyle(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
              BoutonSigh(key: const Key('cal:suivant'), libelle: 'Mois suivant', icone: LucideIcons.chevronRight, variante: VarianteBouton.secondaire, onPressed: () => _decaler(1)),
              const Spacer(),
              BoutonSigh(
                  key: const Key('cal:aujourdhui'),
                  libelle: 'Aujourd’hui',
                  variante: VarianteBouton.secondaire,
                  onPressed: () => setState(() {
                        _annee = c.aujourdhui.year;
                        _mois0 = c.aujourdhui.month - 1;
                      })),
            ]),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Échéances du mois', valeur: nombre(rows.length), icone: LucideIcons.calendarDays, ton: TonSigh.navy),
              KpiSigh(libelle: 'En retard', valeur: nombre(retard), icone: LucideIcons.alarmClock, ton: retard > 0 ? TonSigh.danger : TonSigh.succes),
              KpiSigh(
                  libelle: 'À payer ou à déclarer',
                  valeur: nombre(rows.where((e) => e['etat'] == 'a_payer' || e['etat'] == 'declaration').length),
                  icone: LucideIcons.coins,
                  ton: TonSigh.attention),
              KpiSigh(libelle: 'Payées', valeur: nombre(rows.where((e) => e['etat'] == 'payee').length), icone: LucideIcons.circleCheck, ton: TonSigh.succes),
            ]),
            CarteSigh(
                titre: 'Le mois en grille',
                child: cfaPile([
                  GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 1.5, children: cellules),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final s in cpcEtatsEcheance) BadgeSigh(s.$2, ton: _ton(s.$3)),
                  ]),
                ], espace: 8)),
            CarteSigh(
                titre: 'Les échéances du mois',
                child: MiniTableauSigh(
                    vide: 'Aucune échéance ce mois. L’échéancier d’un exercice se génère à son ouverture.',
                    colonnes: [
                      ColonneMini('Date', (e) => '${dateDe(e['echeance'])}${e['reportee'] == true ? ' (reportée)' : ''}'),
                      ColonneMini('Code', (e) => '${e['code']}', rendu: (e) => cfaCode(e['code'])),
                      ColonneMini('Obligation', (e) => '${e['libelle']}${e['part'] != null && nombreOuZero(e['part']) < 100 ? ', tranche de ${e['part']} %' : ''}'),
                      ColonneMini('Délai', _delai),
                      ColonneMini('État', (e) => cpcEtat('${e['etat']}').$2, rendu: (e) => BadgeSigh(cpcEtat('${e['etat']}').$2, ton: _ton(cpcEtat('${e['etat']}').$3))),
                    ],
                    lignes: rows)),
          ], espace: 16);
        });
  }
}
