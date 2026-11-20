// ENGENDRÉ par prototype_html/build/vecteurs-fichiers.js : NE PAS ÉDITER. `D.DOCUMENTS` de la maquette (assets/js/data.js) : formats admis, tailles, types de document du patient
// et leur ZONE, profils de la zone 2. La taille maximale est un RÉGLAGE en base (`documentsBornes`) : `fichierTailleDefaut` ne sert que tant que rien n'est réglé (10 Mo, « à valider »).

/// Un format de fichier admis : identifiant, libellé, type MIME, extensions, familles qui l'admettent (`courrier`, `patient`).
class FormatFichier {
  const FormatFichier(this.id, this.libelle, this.mime, this.ext, this.familles);
  final String id;
  final String libelle;
  final String mime;
  final List<String> ext;
  final List<String> familles;
}

/// Un type de document du dossier patient et sa zone (1 administratif, 2 médical : RG-13). La zone des dix types est une PROPOSITION À VALIDER.
class TypeDocumentPatient {
  const TypeDocumentPatient(this.libelle, this.zone);
  final String libelle;
  final int zone;
}

const List<FormatFichier> fichierFormats = [
  FormatFichier('pdf', 'PDF', 'application/pdf', ['pdf'], ['courrier', 'patient']),
  FormatFichier('jpeg', 'JPEG', 'image/jpeg', ['jpg', 'jpeg'], ['courrier', 'patient']),
  FormatFichier('png', 'PNG', 'image/png', ['png'], ['courrier', 'patient']),
  FormatFichier('webp', 'WEBP', 'image/webp', ['webp'], ['patient']),
];

const int fichierTailleDefaut = 10485760;
const int fichierTaillePlancher = 102400;
const int fichierTaillePlafond = 67108864;

const List<TypeDocumentPatient> docTypesPatient = [
  TypeDocumentPatient('Ordonnance', 2),
  TypeDocumentPatient('Résultat de laboratoire', 2),
  TypeDocumentPatient('Compte rendu médical', 2),
  TypeDocumentPatient('Consentement éclairé', 2),
  TypeDocumentPatient('Imagerie / Échographie', 2),
  TypeDocumentPatient('Bulletin d’hospitalisation', 2),
  TypeDocumentPatient('Facture', 2),
  TypeDocumentPatient('Pièce d’identité', 1),
  TypeDocumentPatient('Carte d’assurance', 1),
  TypeDocumentPatient('Certificat médical', 2),
];

/// Les profils qui lisent les pièces de la zone 2 (`D.DOCUMENTS.ROLES_ZONE_2`).
const List<String> docRolesZone2 = ['admin', 'dm', 'medecin', 'infirmier', 'chirurgien', 'anesthesiste'];
