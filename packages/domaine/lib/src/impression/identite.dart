/// Identité légale imprimée : UN SEUL en-tête sur toutes les pièces (arbitrage du 31/08/2026).
///
/// Depuis le 06/11/2026 (Direction), l'identité est une DONNÉE DE RÉFÉRENCE DATÉE : la collection `identiteLegale` porte une fiche par
/// version (`debut` null = depuis l'ouverture, `fin` null = en force). [IdentiteClinique] est la SEMENCE (la version 1, `C.BRAND_ORIGINE` de
/// `core.js`) ; une pièce s'imprime avec [IdentiteImprimee], la version en force À LA DATE DE LA PIÈCE (`cfbIdentiteALaDate`), repli sur la
/// semence quand le magasin n'en porte aucune. Une facture d'hier garde le RCCM d'hier, même si une nouvelle version prend effet demain.
class IdentiteClinique {
  const IdentiteClinique._();
  static const sigle = 'CNT';
  static const nom = 'CLINIQUE NASSIERA TOO SARL';
  static const nomCourt = 'CLINIQUE NASSIERA TOO';
  static const slogan = 'Votre santé, notre raison de vivre';
  static const forme = 'Société à Responsabilité Limitée';
  static const adresse = 'Quartier Tchirimina, Natitingou';
  static const bp = 'BP : 507 NATITINGOU (Rép. du Bénin)';
  static const pays = 'République du Bénin';
  static const telephones = ['01 95 44 51 51', '01 66 43 28 20'];
  static const telephoneRdv = '60 33 92 92';
  static const email = 'cliniquenassiera@gmail.com';
  static const ifu = '3201642748214';
  static const rccm = 'RB/NAT/2016-B-268';
  /// Le pied de page légal de tous les écrans (texte arrêté par la Direction le 01/11/2026) : lu de l'identité unique, jamais réécrit ailleurs. Les
  /// séparateurs sont une identité légale imprimée, pas de la ponctuation rédigée.
  static const mentionLegale = '$nom — IFU $ifu — RCCM $rccm.';
  static const autorisation =
      'N° 066/MS/DC/SGM/CJ/DNSP/SRS/SA/058SGG20/N°20 du 02/07/2020';
  /// `autorisationExercice` est nulle au semis : l'inscription à l'ordre suffit (loi 2025-1), elle n'est plus imprimée. Le motif est celui de la maquette.
  static const String? autorisationExercice = null;
  static const autorisationExerciceMotif =
      'Non applicable — l’inscription à l’ordre suffit depuis la loi 2025-1 de juin 2026. L’autorisation d’exercice n’est plus imprimée sur les états.';
  static const devise = 'FCFA';
  static const codeDevise = 'XOF';
  static const logo = 'assets/img/logo.jpeg';
  static const formuleArrete = 'Arrêtée la présente facture à la somme de';
  static const formulePolitesse = 'QUE DIEU VOUS GUÉRISSE ! AMINE !';
  /// Le régime de TVA tel que `cfg-fiscalite` l'affiche (E2272 : en divergence avec l'exonération que `mecef-config` applique ; SIGNALÉ, non arbitré).
  static const regimeTva = 'Taux normal 18 %';
}

/// Les champs d'identité d'une fiche de `identiteLegale` (`C.CHAMPS_IDENTITE`), dans l'ordre de la maquette : ni id, ni version, ni dates.
const List<String> champsIdentiteLegale = [
  'sigle',
  'nom',
  'slogan',
  'forme',
  'adresse',
  'bp',
  'pays',
  'telephones',
  'telephoneRdv',
  'email',
  'ifu',
  'rccm',
  'autorisation',
  'autorisationExercice',
  'autorisationExerciceMotif',
  'devise',
  'codeDevise',
  'logo',
  'formuleArrete',
  'formulePolitesse',
  'regimeTva',
];

/// L'identité qu'une PIÈCE imprime : la version en force à sa date, ou la semence. Les états et le ticket la reçoivent EN PARAMÈTRE : rien dans
/// l'impression ne lit une constante directement, sans quoi une facture d'hier porterait le RCCM de demain.
class IdentiteImprimee {
  const IdentiteImprimee({
    required this.sigle,
    required this.nom,
    required this.slogan,
    required this.forme,
    required this.adresse,
    required this.bp,
    required this.pays,
    required this.telephones,
    required this.telephoneRdv,
    required this.email,
    required this.ifu,
    required this.rccm,
    required this.autorisation,
    this.autorisationExercice,
    required this.autorisationExerciceMotif,
    required this.devise,
    required this.codeDevise,
    required this.logo,
    required this.formuleArrete,
    required this.formulePolitesse,
    required this.regimeTva,
    this.version,
    this.debut,
    this.fin,
  });

  /// La semence : `C.BRAND_ORIGINE`, la version 1 « depuis l'ouverture du dossier ».
  static const semence = IdentiteImprimee(
    sigle: IdentiteClinique.sigle,
    nom: IdentiteClinique.nom,
    slogan: IdentiteClinique.slogan,
    forme: IdentiteClinique.forme,
    adresse: IdentiteClinique.adresse,
    bp: IdentiteClinique.bp,
    pays: IdentiteClinique.pays,
    telephones: IdentiteClinique.telephones,
    telephoneRdv: IdentiteClinique.telephoneRdv,
    email: IdentiteClinique.email,
    ifu: IdentiteClinique.ifu,
    rccm: IdentiteClinique.rccm,
    autorisation: IdentiteClinique.autorisation,
    autorisationExercice: IdentiteClinique.autorisationExercice,
    autorisationExerciceMotif: IdentiteClinique.autorisationExerciceMotif,
    devise: IdentiteClinique.devise,
    codeDevise: IdentiteClinique.codeDevise,
    logo: IdentiteClinique.logo,
    formuleArrete: IdentiteClinique.formuleArrete,
    formulePolitesse: IdentiteClinique.formulePolitesse,
    regimeTva: IdentiteClinique.regimeTva,
    version: 1,
  );

  /// Une fiche du magasin (une version de `identiteLegale`) relue ; chaque champ absent retombe sur la semence (`C.champsIdentite`). `null` : la semence.
  factory IdentiteImprimee.depuisFiche(Map<String, Object?>? f) {
    if (f == null) return semence;
    String t(String k, String defaut) => f.containsKey(k) && f[k] != null ? '${f[k]}' : defaut;
    final tel = f['telephones'];
    return IdentiteImprimee(
      sigle: t('sigle', semence.sigle),
      nom: t('nom', semence.nom),
      slogan: t('slogan', semence.slogan),
      forme: t('forme', semence.forme),
      adresse: t('adresse', semence.adresse),
      bp: t('bp', semence.bp),
      pays: t('pays', semence.pays),
      telephones: tel is List ? [for (final x in tel) '$x'] : (tel is String && tel.trim().isNotEmpty ? [for (final x in tel.split(RegExp(r'[/,;]'))) x.trim()] : semence.telephones),
      telephoneRdv: t('telephoneRdv', semence.telephoneRdv),
      email: t('email', semence.email),
      ifu: t('ifu', semence.ifu),
      rccm: t('rccm', semence.rccm),
      autorisation: t('autorisation', semence.autorisation),
      autorisationExercice: f['autorisationExercice'] == null ? null : '${f['autorisationExercice']}',
      autorisationExerciceMotif: t('autorisationExerciceMotif', semence.autorisationExerciceMotif),
      devise: t('devise', semence.devise),
      codeDevise: t('codeDevise', semence.codeDevise),
      logo: t('logo', semence.logo),
      formuleArrete: t('formuleArrete', semence.formuleArrete),
      formulePolitesse: t('formulePolitesse', semence.formulePolitesse),
      regimeTva: t('regimeTva', semence.regimeTva),
      version: f['version'] is num ? (f['version'] as num).toInt() : null,
      debut: f['debut'] == null ? null : '${f['debut']}',
      fin: f['fin'] == null ? null : '${f['fin']}',
    );
  }

  final String sigle, nom, slogan, forme, adresse, bp, pays, telephoneRdv, email, ifu, rccm, autorisation, autorisationExerciceMotif;
  final String devise, codeDevise, logo, formuleArrete, formulePolitesse, regimeTva;
  final String? autorisationExercice;
  final List<String> telephones;

  /// Le numéro de la version relue (1 pour la semence), et ses bornes ISO (`null` : depuis l'ouverture / en force).
  final int? version;
  final String? debut, fin;

  /// Le nom sans sa forme juridique, tel que le rouleau 80 mm et l'en-tête A4 l'impriment (la maquette écrit le littéral « CLINIQUE NASSIERA TOO » ;
  /// dérivé ici du nom de la version, pour qu'une dénomination changée s'imprime).
  String get nomCourt {
    final m = RegExp(r'^(.*?)\s+(SARL|SA|SAS|SUARL|SARLU)\.?$', caseSensitive: false).firstMatch(nom.trim());
    return m == null ? nom.trim() : m.group(1)!;
  }

  /// Le pied légal de la version : même forme que [IdentiteClinique.mentionLegale].
  String get mentionLegale => '$nom — IFU $ifu — RCCM $rccm.';

  /// Les champs d'identité, sur la forme d'une fiche (`C.champsIdentite`) : ce que le semis écrit et ce qu'une version copie.
  Map<String, Object?> get fiche => {
        'sigle': sigle,
        'nom': nom,
        'slogan': slogan,
        'forme': forme,
        'adresse': adresse,
        'bp': bp,
        'pays': pays,
        'telephones': [...telephones],
        'telephoneRdv': telephoneRdv,
        'email': email,
        'ifu': ifu,
        'rccm': rccm,
        'autorisation': autorisation,
        'autorisationExercice': autorisationExercice,
        'autorisationExerciceMotif': autorisationExerciceMotif,
        'devise': devise,
        'codeDevise': codeDevise,
        'logo': logo,
        'formuleArrete': formuleArrete,
        'formulePolitesse': formulePolitesse,
        'regimeTva': regimeTva,
      };
}
