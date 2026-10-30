import '../format/format_fr.dart';
import 'identite.dart';

/// Une ligne du ticket 80 mm : texte seul, ou paire gauche/droite (`paire()` de `print.js`).
class LigneTicket {
  const LigneTicket.texte(this.gauche, {this.style = StyleLigne.normal})
      : droite = null,
        gras = false;
  const LigneTicket.paire(this.gauche, String this.droite, {this.gras = false})
      : style = StyleLigne.normal;

  final String gauche;
  final String? droite;
  final bool gras;
  final StyleLigne style;

  bool get estPaire => droite != null;

  /// Forme du vecteur de la maquette : « gauche|droite » ou texte seul.
  String get brut => estPaire ? '$gauche|$droite' : gauche;
}

enum StyleLigne { normal, titre, centre, centreGras, lettres, separateur, fin }

class LigneArticle {
  const LigneArticle(
      {required this.designation,
      required this.quantite,
      required this.prixUnitaire,
      required this.montant});
  final String designation;
  final num quantite;
  final num prixUnitaire;
  final num montant;
}

class BlocMecef {
  const BlocMecef({this.nim, this.code, this.compteurs, this.heure});
  final String? nim;
  final String? code;
  final String? compteurs;
  final String? heure;
}

/// Entrée de `P.ticket(o)`. Toutes les parts sont celles que la caisse a CALCULÉES (`repartir`) ; le ticket n'en recalcule aucune,
/// sauf le total dû (reste après versement), comme la maquette.
class EntreeTicket {
  const EntreeTicket({
    required this.operateur,
    required this.numero,
    required this.date,
    this.typeVente = 'COMPTANT',
    this.assureur,
    this.assure,
    this.dossier,
    this.lignes = const [],
    this.total = 0,
    this.remise,
    this.partAssureur,
    this.partNonAssuree,
    this.partPatient = 0,
    this.regle,
    this.rendu,
    this.reste,
    this.baseMecef,
    this.mecef,
  });

  final String operateur;
  final String numero;
  final DateTime date;
  final String typeVente;
  final String? assureur;
  final String? assure;
  final String? dossier;
  final List<LigneArticle> lignes;
  final num total;
  final num? remise;
  final num? partAssureur;
  final num? partNonAssuree;
  final num partPatient;
  final num? regle;
  final num? rendu;
  final num? reste;
  final num? baseMecef;
  final BlocMecef? mecef;
}

const _sep = '--------------------------------';

bool _vrai(num? v) => v != null && v != 0;

/// Suite des lignes du rouleau de caisse, dans l'ordre exact de `P.ticket` (print.js) — vérifiée contre les vecteurs de la maquette.
List<LigneTicket> lignesTicket(EntreeTicket o) {
  const sep = LigneTicket.texte(_sep, style: StyleLigne.separateur);
  final l = <LigneTicket>[
    const LigneTicket.texte(IdentiteClinique.nomCourt, style: StyleLigne.titre),
    const LigneTicket.texte(IdentiteClinique.bp, style: StyleLigne.centre),
    LigneTicket.texte('TÉL. ${IdentiteClinique.telephones.join(' / ')}',
        style: StyleLigne.centre),
    const LigneTicket.texte('IFU ${IdentiteClinique.ifu}',
        style: StyleLigne.centre),
    const LigneTicket.texte('RCCM ${IdentiteClinique.rccm}',
        style: StyleLigne.centre),
    sep,
  ];
  final m = o.mecef;
  if (m != null) {
    l.addAll([
      LigneTicket.texte('NIM : ${m.nim ?? '—'}'),
      LigneTicket.texte('CODE DGI : ${m.code ?? '—'}'),
      LigneTicket.texte('CPT : ${m.compteurs ?? '—'}'),
      LigneTicket.texte('HEURE : ${m.heure ?? heure(o.date)}'),
      sep,
    ]);
  }
  l.add(LigneTicket.paire('OPÉRATEUR', o.operateur));
  l.add(LigneTicket.paire('TYPE VENTE', o.typeVente));
  if (o.assureur != null) l.add(LigneTicket.paire('ASSUREUR', o.assureur!));
  if (o.assure != null) l.add(LigneTicket.paire('ASSURÉ', o.assure!));
  // Une vente au comptoir n'oblige pas à ouvrir un dossier : la pièce le dit plutôt que de laisser une ligne vide.
  l.add(LigneTicket.paire(
      'DOSSIER', o.dossier ?? 'VENTE AU COMPTOIR — sans dossier'));
  l.add(LigneTicket.paire('N° PIÈCE', o.numero));
  l.add(LigneTicket.paire('DATE', '${dateFR(o.date)} ${heure(o.date)}'));
  l.add(sep);
  for (final a in o.lignes) {
    l.add(LigneTicket.texte(a.designation));
    l.add(LigneTicket.paire(
        '  ${nombre(a.quantite)} x ${money(a.prixUnitaire, avecDevise: false)}',
        money(a.montant, avecDevise: false)));
  }
  l.add(sep);
  l.add(LigneTicket.paire('MONTANT TOTAL', money(o.total, avecDevise: false),
      gras: true));
  if (_vrai(o.remise))
    l.add(
        LigneTicket.paire('REMISE', '- ${money(o.remise, avecDevise: false)}'));
  if (_vrai(o.partAssureur))
    l.add(LigneTicket.paire(
        'PART ASSUREUR', money(o.partAssureur, avecDevise: false)));
  // La part NON assurée porte les lignes qu'AUCUNE compagnie ne couvre : elle explique au guichet pourquoi un assuré règle tout.
  if (_vrai(o.partNonAssuree))
    l.add(LigneTicket.paire(
        'DONT PART NON ASSURÉE', money(o.partNonAssuree, avecDevise: false)));
  l.add(LigneTicket.paire(o.assureur != null ? 'PART ASSURÉ' : 'NET À PAYER',
      money(o.partPatient, avecDevise: false),
      gras: true));
  if (o.regle != null)
    l.add(LigneTicket.paire('RÉGLÉ', money(o.regle, avecDevise: false)));
  if (_vrai(o.rendu))
    l.add(LigneTicket.paire('RENDU', money(o.rendu, avecDevise: false)));
  // Le TOTAL DÛ : sur un règlement partiel, son absence laissait le patient repartir sans savoir ce qu'il devait encore.
  final due = o.reste ??
      (o.regle != null
          ? (o.partPatient - o.regle!).clamp(0, double.infinity)
          : null);
  if (due != null)
    l.add(LigneTicket.paire('TOTAL DÛ', money(due, avecDevise: false),
        gras: true));
  // La base MECeF ne porte que la part réglée par le patient : l'imprimer permet de le vérifier sans ouvrir le logiciel.
  if (o.baseMecef != null)
    l.add(
        LigneTicket.paire('BASE MECeF', money(o.baseMecef, avecDevise: false)));
  l.add(sep);
  l.add(const LigneTicket.texte('${IdentiteClinique.formuleArrete} :'));
  l.add(LigneTicket.texte(montantEnLettres(o.partPatient),
      style: StyleLigne.lettres));
  l.add(sep);
  l.add(const LigneTicket.texte(IdentiteClinique.formulePolitesse,
      style: StyleLigne.centreGras));
  return l;
}
