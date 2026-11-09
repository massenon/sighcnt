/// MECeF, lot M1 : la fonction UNIQUE des montants envoyés à la normalisation, et la validation de l'acheteur.
///
/// Port fidèle de `SIGH.mecefMontants` et `SIGH.mecef.validerAcheteur` (`prototype_html/assets/js/parcours.js`, E2299), rejoué sur
/// `test/vecteurs/mecef_montants.json` (cas fixes, ventes tirées au hasard, acheteurs). Règles : prix unitaire ENTIER en FCFA (sauf quand la
/// pièce porte son `montantBrut`, qui gouverne), quantité décimale jusqu'à trois décimales, remise globale répartie au prorata du net avec
/// l'écart d'arrondi sur la PLUS GRANDE ligne, base MECeF = part du PATIENT seulement (ni part assureur, ni personnel, ni remise), totaux
/// contrôlés avant tout envoi. Toute l'arithmétique est ENTIÈRE : aucune décimale ne traverse. Aucun protocole de boîtier n'est supposé.
library;

/// Un refus nommé : code, motif lisible, geste de correction.
class RefusMecef {
  const RefusMecef(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;

  Map<String, Object?> toJson() =>
      {'ok': false, 'code': code, 'motif': motif, 'geste': geste};

  @override
  String toString() => '$code : $motif';
}

/// Une ligne normalisée (montants entiers).
class LigneMecef {
  const LigneMecef({
    required this.id,
    required this.designation,
    required this.quantite,
    required this.prixUnitaireEnvoye,
    required this.brut,
    required this.remise,
    required this.net,
    required this.partAssureur,
    required this.partPersonnel,
    required this.partPatient,
  });
  final String? id;
  final String? designation;
  final num quantite;
  final int prixUnitaireEnvoye;
  final int brut;
  final int remise;
  final int net;
  final int partAssureur;
  final int partPersonnel;
  final int partPatient;

  Map<String, Object?> toJson() => {
        'id': id,
        'designation': designation,
        'quantite': quantite,
        'prixUnitaireEnvoye': prixUnitaireEnvoye,
        'brut': brut,
        'remise': remise,
        'net': net,
        'partAssureur': partAssureur,
        'partPersonnel': partPersonnel,
        'partPatient': partPatient,
      };
}

/// Les montants d'une vente, tous entiers.
class MontantsMecef {
  const MontantsMecef({
    required this.lignes,
    required this.brut,
    required this.remises,
    required this.total,
    required this.partAssureur,
    required this.partPersonnel,
    required this.partPatient,
    required this.base,
    required this.ht,
    required this.tva,
    required this.aib,
    required this.net,
  });
  final List<LigneMecef> lignes;
  final int brut;
  final int remises;
  final int total;
  final int partAssureur;
  final int partPersonnel;
  final int partPatient;

  /// Ce que la normalisation retient : la part réglée par le patient.
  final int base;
  final int ht;
  final int tva;
  final int aib;
  final int net;

  Map<String, Object?> toJson() => {
        'ok': true,
        'lignes': [for (final l in lignes) l.toJson()],
        'brut': brut,
        'remises': remises,
        'total': total,
        'partAssureur': partAssureur,
        'partPersonnel': partPersonnel,
        'partPatient': partPatient,
        'base': base,
        'ht': ht,
        'tva': tva,
        'aib': aib,
        'net': net,
      };
}

/// Résultat : soit les montants, soit un refus nommé.
class ResultatMontants {
  const ResultatMontants.ok(MontantsMecef this.montants) : refus = null;
  const ResultatMontants.refus(RefusMecef this.refus) : montants = null;
  final MontantsMecef? montants;
  final RefusMecef? refus;
  bool get ok => montants != null;

  Map<String, Object?> toJson() => ok ? montants!.toJson() : refus!.toJson();
}

/// Les taux d'AIB offerts à la fenêtre : 0, 1 ou 5 %.
const aibTauxAdmis = [0, 1, 5];

/// 1 % par défaut (régime de la facture de référence, à confirmer par la Direction : Q4 du PRD).
const aibTauxParDefaut = 1;

/// L'écriture JavaScript d'une valeur dans un message (`1` et non `1.0`).
String _js(Object? v) {
  if (v == null) return 'undefined';
  if (v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 1e21) {
    return v.toInt().toString();
  }
  return '$v';
}

/// `Number(v)` pour une valeur JSON ; NaN si elle ne se lit pas.
double _nombre(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? double.nan;
  }
  return double.nan;
}

bool _entierPositif(double x) =>
    x.isFinite && x.floorToDouble() == x && x >= 0;

/// a / b arrondi au plus proche (la moitié vers le haut), en arithmétique entière. a >= 0, b > 0.
int _divArrondi(int a, int b) => (2 * a + b) ~/ (2 * b);

class _L {
  _L(this.src, this.id, this.designation, this.qm, this.quantite, this.brut,
      this.remise, this.partAssureur, this.partPersonnel);
  final Map<String, Object?> src;
  final String? id;
  final String? designation;
  final int qm;
  final num quantite;
  final int brut;
  int remise;
  final int partAssureur;
  final int partPersonnel;
  int get net => brut - remise;
  bool partDecimale = false;
}

RefusMecef _refus(String c, String m, String g) => RefusMecef(c, m, g);

/// Les montants d'une vente. [tauxTvaCourant] est le taux du régime en vigueur, utilisé quand [tauxTva] est absent.
///
/// Entrée : `lignes` (id, designation, quantite, prixUnitaire, montantBrut?, remise?, partAssureur?, partPersonnel?, partPatient?,
/// statutPaiement?), `remiseGlobale?`, `totalAttendu?`, `paiements?`, `seulementPayees?`.
ResultatMontants mecefMontants({
  required List<Map<String, Object?>> lignes,
  num? remiseGlobale,
  num? totalAttendu,
  List<num>? paiements,
  bool seulementPayees = false,
  num? aibTaux,
  num? tauxTva,
  num tauxTvaCourant = 0,
}) {
  if (lignes.isEmpty) {
    return ResultatMontants.refus(_refus(
        'AUCUNE_LIGNE',
        'La pièce ne porte aucune ligne à normaliser.',
        'Ajouter au moins une prestation avant la normalisation.'));
  }
  final liste = <_L>[];
  for (var i = 0; i < lignes.length; i++) {
    final l = lignes[i];
    final nom = _nomLigne(l, i);
    final q = l['quantite'] == null ? 1.0 : _nombre(l['quantite']);
    final qmD = q.isFinite ? (q * 1000 + 0.5).floorToDouble() : double.nan;
    if (!(q.isFinite && q > 0) || (qmD / 1000 - q).abs() > 1e-9) {
      return ResultatMontants.refus(_refus(
          'QUANTITE_INVALIDE',
          'La quantité de « $nom » (${_js(l['quantite'])}) doit être positive, à trois décimales au plus.',
          'Corriger la quantité de la ligne.'));
    }
    final qm = qmD.toInt();
    int brut;
    if (l['montantBrut'] != null) {
      final mb = _nombre(l['montantBrut']);
      if (!_entierPositif(mb)) {
        return ResultatMontants.refus(_refus(
            'MONTANT_DECIMAL',
            'Le montant de « $nom » (${_js(l['montantBrut'])}) n’est pas un nombre entier de FCFA.',
            'Corriger la ligne : un montant normalisé est un entier.'));
      }
      brut = mb.toInt();
    } else {
      final pu = l.containsKey('prixUnitaire') ? _nombre(l['prixUnitaire']) : double.nan;
      if (!_entierPositif(pu)) {
        return ResultatMontants.refus(_refus(
            'PRIX_DECIMAL',
            'Le prix unitaire de « $nom » (${_js(l['prixUnitaire'])}) n’est pas un nombre entier de FCFA.',
            'Corriger le prix : seule la quantité peut être décimale.'));
      }
      brut = _divArrondi(qm * pu.toInt(), 1000);
    }
    final r = l['remise'] == null ? 0.0 : _nombre(l['remise']);
    if (!_entierPositif(r) || r > brut) {
      return ResultatMontants.refus(_refus(
          'REMISE_INVALIDE',
          'La remise de « $nom » (${_js(l['remise'])}) doit être un entier de FCFA qui ne dépasse pas le montant de la ligne.',
          'Corriger la remise de la ligne.'));
    }
    // Les parts : un nombre non entier est refusé plus bas (MONTANT_DECIMAL), après la remise globale, comme la maquette.
    final pa = _nombre(l['partAssureur']);
    final pp = _nombre(l['partPersonnel']);
    liste.add(_L(
        l,
        l['id'] == null ? null : '${l['id']}',
        l['designation'] == null ? null : '${l['designation']}',
        qm,
        l['quantite'] == null ? 1 : (q == q.truncateToDouble() ? q.toInt() : q),
        brut,
        r.toInt(),
        _partEntiere(pa),
        _partEntiere(pp)));
    if (!_entierPositif(pa) || !_entierPositif(pp)) {
      liste.last.partDecimale = true;
    }
  }
  final rgD = remiseGlobale == null ? 0.0 : remiseGlobale.toDouble();
  if (!_entierPositif(rgD)) {
    return ResultatMontants.refus(_refus(
        'REMISE_INVALIDE',
        'La remise globale (${_js(remiseGlobale)}) doit être un entier de FCFA.',
        'Corriger la remise.'));
  }
  final rg = rgD.toInt();
  if (rg > 0) {
    final sommeNet = liste.fold<int>(0, (n, x) => n + x.net);
    if (rg > sommeNet) {
      return ResultatMontants.refus(_refus(
          'REMISE_INVALIDE',
          'La remise globale ($rg) dépasse le total de la pièce ($sommeNet).',
          'Corriger la remise.'));
    }
    final parts = [for (final x in liste) (rg * x.net) ~/ sommeNet];
    final reste = rg - parts.fold<int>(0, (n, p) => n + p);
    var plus = 0;
    for (var k = 0; k < liste.length; k++) {
      if (liste[k].net > liste[plus].net) plus = k;
    }
    parts[plus] += reste;
    for (var k = 0; k < liste.length; k++) {
      if (parts[k] > liste[k].net) {
        return ResultatMontants.refus(_refus(
            'REMISE_INVALIDE',
            'La part de remise de « ${liste[k].designation ?? liste[k].id ?? 'ligne ${k + 1}'} » dépasse son montant.',
            'Corriger la remise.'));
      }
      liste[k].remise += parts[k];
    }
  }
  var totalBrut = 0, totalRemises = 0, total = 0, tAss = 0, tPers = 0, tPat = 0, base = 0;
  final sortie = <LigneMecef>[];
  for (var j = 0; j < liste.length; j++) {
    final x = liste[j];
    final nomL = x.designation ?? x.id ?? 'ligne ${j + 1}';
    if (x.partDecimale) {
      return ResultatMontants.refus(_refus(
          'MONTANT_DECIMAL',
          'Une part de « $nomL » n’est pas un nombre entier de FCFA.',
          'Corriger la prise en charge de la ligne.'));
    }
    final pat = x.net - x.partAssureur - x.partPersonnel;
    final sp = x.src['partPatient'];
    if (sp != null && rg == 0 && _nombre(sp) != pat) {
      return ResultatMontants.refus(_refus(
          'TOTAL_INCOHERENT',
          'Les parts de « $nomL » (patient ${_js(sp)}, assureur ${x.partAssureur}, personnel ${x.partPersonnel}) ne totalisent pas son montant (${x.net}).',
          'Reprendre la répartition de la ligne.'));
    }
    if (pat < 0) {
      return ResultatMontants.refus(_refus(
          'TOTAL_INCOHERENT',
          'Les parts de « $nomL » dépassent son montant (${x.net}).',
          'Reprendre la répartition de la ligne.'));
    }
    final compte = !seulementPayees || x.src['statutPaiement'] == 'paye';
    totalBrut += x.brut;
    totalRemises += x.remise;
    total += x.net;
    tAss += x.partAssureur;
    tPers += x.partPersonnel;
    tPat += pat;
    if (compte) base += pat;
    sortie.add(LigneMecef(
        id: x.id,
        designation: x.designation,
        quantite: x.quantite,
        prixUnitaireEnvoye: x.qm != 0 ? _divArrondi(x.brut * 1000, x.qm) : x.brut,
        brut: x.brut,
        remise: x.remise,
        net: x.net,
        partAssureur: x.partAssureur,
        partPersonnel: x.partPersonnel,
        partPatient: pat));
  }
  if (totalAttendu != null && totalAttendu != total) {
    return ResultatMontants.refus(_refus(
        'TOTAL_INCOHERENT',
        'La somme des lignes ($total) diffère du total de la pièce (${_js(totalAttendu)}).',
        'Reprendre les lignes ou le total de la pièce avant la normalisation.'));
  }
  if (paiements != null) {
    final som = paiements.fold<num>(0, (n, p) => n + p);
    if (som != base) {
      return ResultatMontants.refus(_refus(
          'TOTAL_INCOHERENT',
          'Les paiements (${_js(som)}) diffèrent de la base normalisée ($base).',
          'Reprendre les règlements de la pièce.'));
    }
  }
  final tva = (tauxTva ?? tauxTvaCourant).toInt();
  final aibD = aibTaux == null ? 0.0 : aibTaux.toDouble();
  if (!_entierPositif(aibD) || aibD > 100) {
    return ResultatMontants.refus(_refus(
        'AIB_TAUX_INVALIDE',
        'Le taux d’AIB (${_js(aibTaux)}) n’est pas un pourcentage entier.',
        'Choisir 0, 1 ou 5 %.'));
  }
  final ht = tva != 0 ? _divArrondi(base * 100, 100 + tva) : base;
  final aib = _divArrondi(ht * aibD.toInt(), 100);
  return ResultatMontants.ok(MontantsMecef(
      lignes: sortie,
      brut: totalBrut,
      remises: totalRemises,
      total: total,
      partAssureur: tAss,
      partPersonnel: tPers,
      partPatient: tPat,
      base: base,
      ht: ht,
      tva: base - ht,
      aib: aib,
      net: base + aib));
}

int _partEntiere(double d) => d.isFinite ? d.truncate() : 0;

String _nomLigne(Map<String, Object?> l, int i) {
  final d = l['designation'];
  if (d != null && '$d'.isNotEmpty) return '$d';
  final id = l['id'];
  if (id != null && '$id'.isNotEmpty) return '$id';
  return 'ligne ${i + 1}';
}

/// L'acheteur validé de la fenêtre « Facture normalisée ».
class AcheteurMecef {
  const AcheteurMecef({this.ifu, this.nom, required this.aibTaux});
  final String? ifu;
  final String? nom;
  final int aibTaux;

  Map<String, Object?> toJson() => {'ifu': ifu, 'nom': nom, 'aibTaux': aibTaux};
}

/// Contrôle de la fenêtre « Facture normalisée » : IFU de l'acheteur (13 chiffres quand il est renseigné, facultatif pour un particulier),
/// nom (obligatoire dès qu'un IFU est saisi), taux d'AIB (0, 1 ou 5 ; [aibParDefaut] quand il est vide).
({AcheteurMecef? acheteur, RefusMecef? refus}) validerAcheteurMecef({
  Object? ifu,
  Object? nom,
  Object? aibTaux,
  int aibParDefaut = aibTauxParDefaut,
}) {
  final i = (ifu == null ? '' : '$ifu').replaceAll(RegExp('[\\s  ]'), '');
  if (i.isNotEmpty && !RegExp(r'^\d{13}$').hasMatch(i)) {
    return (
      acheteur: null,
      refus: _refus(
          'IFU_INVALIDE',
          'L’IFU de l’acheteur (« $i ») doit comporter exactement 13 chiffres.',
          'Corriger l’IFU, ou le laisser vide pour un particulier.')
    );
  }
  final n = (nom == null ? '' : '$nom').trim();
  if (i.isNotEmpty && n.isEmpty) {
    return (
      acheteur: null,
      refus: _refus(
          'NOM_ACHETEUR_ABSENT',
          'Un IFU d’acheteur est saisi sans son nom.',
          'Saisir le nom de l’acheteur qui porte cet IFU.')
    );
  }
  final brut = aibTaux == null || aibTaux == '' ? aibParDefaut.toDouble() : _nombre(aibTaux);
  if (!brut.isFinite || !aibTauxAdmis.contains(brut.toInt()) || brut != brut.truncateToDouble()) {
    return (
      acheteur: null,
      refus: _refus(
          'AIB_TAUX_INVALIDE',
          'Le taux d’AIB (${_js(aibTaux)}) n’est pas l’un des choix admis (0, 1 ou 5 %).',
          'Choisir 0, 1 ou 5 %.')
    );
  }
  return (
    acheteur: AcheteurMecef(
        ifu: i.isEmpty ? null : i, nom: n.isEmpty ? null : n, aibTaux: brut.toInt()),
    refus: null
  );
}

/// Une ligne de pièce vue par la fonction des montants : la pièce garde ses montants (`montantBrut` ou `montant` gouverne quand elle le porte).
Map<String, Object?> ligneVersMecef(Map<String, Object?> l) {
  final o = <String, Object?>{
    'id': l['id'],
    'designation': l['designation'],
    'quantite': l['quantite'] ?? 1,
    'prixUnitaire': l['prixUnitaire'],
    'partAssureur': _faux(l['partAssureur']) ? 0 : l['partAssureur'],
    'partPersonnel': _faux(l['partPersonnel']) ? 0 : l['partPersonnel'],
    'statutPaiement': l['statutPaiement'],
  };
  if (l['montantBrut'] != null) {
    o['montantBrut'] = l['montantBrut'];
    o['remise'] = _faux(l['remise']) ? 0 : l['remise'];
  } else if (l['montant'] != null) {
    o['montantBrut'] = l['montant'];
    o['remise'] = 0;
  }
  return o;
}

bool _faux(Object? v) => v == null || v == 0 || v == '' || v == false;
