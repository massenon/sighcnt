import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';

/// Les pièces imprimées de la paie (`P.etat` de la maquette) : le bulletin, le journal, les quatre états de cotisations. Le total d'un tableau est
/// CALCULÉ (`somme` sur la colonne, refait depuis les lignes imprimées), jamais fourni ; les lignes conditionnelles d'un bulletin (sanction, avance,
/// participation) sont éliminées par UN SEUL filtre en fin de tableau — chaque moitié d'une liste concaténée filtre, ou le rendu casse au clic.

/// Ce que l'état « Bulletin de paie » lit : le même contenu qu'il vienne d'un CALCUL (écran de calcul) ou d'un bulletin STOCKÉ (registre).
class PaiBulletinVue {
  const PaiBulletinVue(
      {required this.reference,
      required this.periode,
      required this.employe,
      required this.matricule,
      required this.fonction,
      required this.service,
      required this.categorie,
      required this.cnss,
      required this.situation,
      required this.telephone,
      required this.salaireBase,
      required this.primeAnciennete,
      required this.lignesPrimes,
      required this.totalPrimes,
      required this.brut,
      required this.pctSanction,
      required this.sanction,
      required this.cnssOuvriere,
      required this.cnssPatronale,
      required this.vps,
      required this.its,
      required this.ortb,
      required this.avances,
      required this.detailOrtb,
      required this.participations,
      required this.participationsDetail,
      required this.totalRetenues,
      required this.net,
      this.heuresSupMontant = 0,
      this.heuresSupNb = 0,
      this.prets = 0,
      this.pretsDetail = const []});
  final String reference, periode, employe, matricule, fonction, service, categorie, cnss, situation, telephone;
  final num salaireBase, primeAnciennete, totalPrimes, brut, pctSanction, sanction, cnssOuvriere, cnssPatronale, vps, its, ortb, avances, participations, totalRetenues, net;
  final List<PaiLignePrime> lignesPrimes;
  final PaiOrtb? detailOrtb;
  final List<String> participationsDetail;

  /// Heures supplémentaires validées (comprises dans le brut) et échéances de prêt retenues ce mois ; [pretsDetail] : « PRT-0001 2/3 ».
  final num heuresSupMontant, heuresSupNb, prets;
  final List<String> pretsDetail;
}

String _t(Object? v) => '${v ?? ''}';

/// Le bulletin d'un calcul : sa référence est `BP-<matricule>-<mois>` (le rang du mois dans l'année, deux chiffres).
PaiBulletinVue vueDeCalcul(PaiCalcul c) => PaiBulletinVue(
    reference: 'BP-${c.matricule}-${(c.mois + 1).toString().padLeft(2, '0')}',
    periode: c.periode,
    employe: c.nomComplet,
    matricule: c.matricule,
    fonction: _t(c.employe['fonction']),
    service: _t(c.employe['service']),
    categorie: _t(c.employe['categorie']),
    cnss: _t(c.employe['cnss']),
    situation: _t(c.employe['situation']),
    telephone: _t(c.employe['telephone']),
    salaireBase: c.salaireBase,
    primeAnciennete: c.primeAnciennete,
    lignesPrimes: c.lignesPrimes,
    totalPrimes: c.totalPrimes,
    brut: c.brut,
    pctSanction: c.pctSanction,
    sanction: c.sanction,
    cnssOuvriere: c.cnssOuvriere,
    cnssPatronale: c.cnssPatronale,
    vps: c.vps,
    its: c.its,
    ortb: c.ortb,
    avances: c.avances,
    detailOrtb: c.detailOrtb,
    participations: c.participations,
    participationsDetail: [for (final x in c.participationsDetail) _t(x['evenementLibelle'])],
    totalRetenues: c.totalRetenues,
    net: c.net,
    heuresSupMontant: c.heuresSupMontant,
    heuresSupNb: c.heuresSupNb,
    prets: c.prets,
    pretsDetail: [for (final x in c.pretsDetail) '${x['reference']} ${x['rang']}/${x['nbEcheances']}']);

/// Un bulletin STOCKÉ : le détail ORTB et les participations voyagent avec la pièce (E682) ; un bulletin antérieur n'en porte pas — il retombe sur
/// « Non applicable », comme la maquette.
PaiBulletinVue vueDeFiche(Fiche b) {
  num v(String k) => nombreOuZero(b[k]);
  return PaiBulletinVue(
      reference: _t(b['reference']),
      periode: _t(b['periode']),
      employe: _t(b['employe']),
      matricule: _t(b['matricule']),
      fonction: _t(b['fonction']),
      service: _t(b['service']),
      categorie: _t(b['categorie']),
      cnss: _t(b['cnss']),
      situation: _t(b['situation']),
      telephone: _t(b['telephone']),
      salaireBase: v('salaireBase'),
      primeAnciennete: v('primeAnciennete'),
      lignesPrimes: [
        for (final l in (b['lignesPrimes'] as List? ?? const []).whereType<Map>())
          PaiLignePrime(_t(l['id']), _t(l['label']), nombreOuZero(l['unitaire']), nombreOuZero(l['nombre']).toInt(), nombreOuZero(l['total']))
      ],
      totalPrimes: v('totalPrimes'),
      brut: v('brut'),
      pctSanction: v('pctSanction'),
      sanction: v('sanction'),
      cnssOuvriere: v('cnssOuvriere'),
      cnssPatronale: v('cnssPatronale'),
      vps: v('vps'),
      its: v('its'),
      ortb: v('ortb'),
      avances: v('avances'),
      detailOrtb: paiOrtbDeFiche(b['detailOrtb']),
      participations: v('participations'),
      participationsDetail: [for (final x in (b['participationsDetail'] as List? ?? const []).whereType<Map>()) _t(x['evenementLibelle'])],
      totalRetenues: v('totalRetenues'),
      net: v('net'),
      heuresSupMontant: v('heuresSupMontant'),
      heuresSupNb: v('heuresSupNb'),
      prets: v('prets'),
      pretsDetail: [for (final x in (b['pretsDetail'] as List? ?? const []).whereType<Map>()) '${x['reference']} ${x['rang']}/${x['nbEcheances']}']);
}

String _mf(num v) => money(v, avecDevise: false);

/// `etatBulletin(b)` : gains, retenues, net, charges patronales (non déduites du net). Les rubriques conditionnelles (prime d'ancienneté, sanction, avance,
/// participation) n'existent que si elles valent quelque chose.
PieceA4 pieceBulletin(ContexteEcran c, PaiBulletinVue b) {
  final gains = <Map<String, Object?>>[
    {'rub': '01', 'libelle': 'Salaire de base', 'base': '', 'taux': '', 'montant': _mf(b.salaireBase)},
    if (b.primeAnciennete != 0) {'rub': '02', 'libelle': 'Prime d’ancienneté', 'base': '', 'taux': '', 'montant': _mf(b.primeAnciennete)},
  ];
  for (final p in b.lignesPrimes) {
    gains.add({
      'rub': (gains.length + 1).toString().padLeft(2, '0'),
      'libelle': 'Prime — ${p.libelle}',
      'base': '${p.nombre}',
      'taux': _mf(p.unitaire),
      'montant': _mf(p.total)
    });
  }
  if (b.heuresSupMontant != 0) {
    gains.add({'rub': (gains.length + 1).toString().padLeft(2, '0'), 'libelle': 'Heures supplémentaires', 'base': nombre(b.heuresSupNb), 'taux': '', 'montant': _mf(b.heuresSupMontant)});
  }
  gains.add({'rub': '', 'libelle': 'TOTAL BRUT', 'base': '', 'taux': '', 'montant': _mf(b.brut)});

  final retenues = <Map<String, Object?>>[
    if (b.sanction != 0)
      {'rub': '', 'libelle': 'Sanction NS 131', 'base': _mf(b.brut), 'taux': '${paiNum(b.pctSanction)} %', 'montant': _mf(b.sanction)},
    {'rub': '', 'libelle': 'CNSS part ouvrière', 'base': _mf(b.brut - b.sanction), 'taux': '${paiNum(paiCnssOuvriere)} %', 'montant': _mf(b.cnssOuvriere)},
    {'rub': '', 'libelle': 'Impôt sur les traitements et salaires (ITS)', 'base': '', 'taux': 'Barème', 'montant': _mf(b.its)},
    for (final l in paiLignesOrtb(b.detailOrtb)) {'rub': '', 'libelle': l.libelle, 'base': l.base, 'taux': 'Forfait annuel', 'montant': l.montant},
    if (b.avances != 0) {'rub': '', 'libelle': 'Remboursement d’avance sur salaire', 'base': '', 'taux': '', 'montant': _mf(b.avances)},
    if (b.prets != 0) {'rub': '', 'libelle': 'Échéance de prêt', 'base': b.pretsDetail.join(' ; '), 'taux': '', 'montant': _mf(b.prets)},
    if (b.participations != 0)
      {
        'rub': '',
        'libelle': 'Participation aux événements du personnel',
        'base': b.participationsDetail.join(' ; '),
        'taux': 'Forfait',
        'montant': _mf(b.participations)
      },
    {'rub': '', 'libelle': 'TOTAL DES RETENUES', 'base': '', 'taux': '', 'montant': _mf(b.totalRetenues + b.sanction)},
  ];

  TableauEtat rubriques(String libelleBase, List<Map<String, Object?>> lignes, {required bool gain}) => TableauEtat(colonnes: [
        ColonneEtat(libelle: 'N°', valeur: (r) => r['rub']),
        ColonneEtat(libelle: 'Libellé', valeur: (r) => r['libelle']),
        ColonneEtat(libelle: libelleBase, droite: true, valeur: (r) => r['base']),
        ColonneEtat(libelle: gain ? 'Taux / unitaire' : 'Taux', droite: true, valeur: (r) => r['taux']),
        ColonneEtat(libelle: 'Montant', droite: true, valeur: (r) => r['montant']),
      ], lignes: lignes);

  return pieceM9(c,
      titre: 'Bulletin de paie',
      sousTitre: b.periode,
      cartouche: [
        ('Nom et prénoms', b.employe),
        ('Matricule', b.matricule),
        ('Fonction', paiFonctionLibelle(b.fonction)),
        ('Service', b.service),
        ('Catégorie / échelon', b.categorie),
        ('Numéro CNSS', b.cnss),
        ('Situation matrimoniale', b.situation),
        ('Téléphone', b.telephone),
      ],
      blocs: [
        const BlocTexte('Éléments de gain', gras: true),
        BlocTableau(rubriques('Nombre', gains, gain: true)),
        const BlocTexte('Retenues', gras: true),
        BlocTableau(rubriques('Base', retenues, gain: false)),
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
          ColonneEtat(libelle: 'Montant', droite: true, valeur: (r) => r['v']),
        ], lignes: [
          {'k': 'Salaire brut', 'v': _mf(b.brut)},
          {'k': 'Total des retenues', 'v': _mf(b.totalRetenues + b.sanction)},
          {'k': 'NET À PAYER', 'v': _mf(b.net)},
        ])),
        BlocTexte(
            'Charges patronales (non déduites du net) : CNSS ${paiNum(paiCnssPatronale)} % — ${money(b.cnssPatronale)} ; VPS ${paiNum(paiVpsTaux)} % — ${money(b.vps)}.'),
      ],
      signatures: [Signature('L’Employé(e)', nom: b.employe, mention: 'Signature'), signDaf]);
}

void imprimerBulletin(BuildContext ctx, PaiBulletinVue b) => afficherApercu(ctx, pieceBulletin(ContexteEcran.of(ctx), b));

/// « Journal de paie » d'un mois : un total par colonne de montant, refait depuis les lignes imprimées (`somme`), trié par nom d'agent.
void imprimerJournalCalcul(BuildContext ctx, int mois, List<PaiCalcul> calc) {
  final c = ContexteEcran.of(ctx);
  final lignes = [for (final x in trierPar(calc, (x) => x.nomComplet)) ligneCalcul(x)];
  num f(Map<String, Object?> r, String k) => nombreOuZero(r[k]);
  afficherApercu(
      ctx,
      pieceM9(c,
          titre: 'Journal de paie',
          sousTitre: periodeBrute(mois),
          cartouche: [
            ('Période', periodeBrute(mois)),
            ('Effectif', nombre(calc.length)),
            ('Masse salariale brute', money(paiSomme(calc, (x) => x.brut))),
            ('Net à payer', money(paiSomme(calc, (x) => x.net))),
            ('CNSS totale', money(paiSomme(calc, (x) => x.cnssOuvriere) + paiSomme(calc, (x) => x.cnssPatronale))),
            ('Date d’édition', dateFR(c.aujourdhui)),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Mat.', valeur: (r) => r['matricule']),
              ColonneEtat(libelle: 'Agent', valeur: (r) => r['agent']),
              ColonneEtat(libelle: 'Base', droite: true, valeur: (r) => _mf(f(r, 'salaireBase')), somme: (r) => f(r, 'salaireBase')),
              ColonneEtat(libelle: 'Primes', droite: true, valeur: (r) => _mf(f(r, 'totalPrimes')), somme: (r) => f(r, 'totalPrimes')),
              ColonneEtat(libelle: 'Brut', droite: true, valeur: (r) => _mf(f(r, 'brut')), somme: (r) => f(r, 'brut')),
              ColonneEtat(libelle: 'Sanction', droite: true, valeur: (r) => f(r, 'sanction') != 0 ? _mf(f(r, 'sanction')) : '', somme: (r) => f(r, 'sanction')),
              ColonneEtat(libelle: 'CNSS', droite: true, valeur: (r) => _mf(f(r, 'cnssOuvriere')), somme: (r) => f(r, 'cnssOuvriere')),
              ColonneEtat(libelle: 'ITS', droite: true, valeur: (r) => _mf(f(r, 'its')), somme: (r) => f(r, 'its')),
              ColonneEtat(libelle: 'Net à payer', droite: true, valeur: (r) => _mf(f(r, 'net')), somme: (r) => f(r, 'net')),
            ], lignes: lignes, libelleTotal: 'TOTAL GÉNÉRAL')
          ],
          signatures: const [
            Signature('Le Responsable RH'),
            signComptable,
            Signature('La Direction', nom: paiNomDirection, mention: 'Validation'),
          ]));
}
