/// Codes d'erreur du protocole (spec §14) et refus nommés (spec §5). Ne pas en inventer
/// côté client : un code inconnu doit être affiché tel quel dans l'écran « À traiter ».
class CodeSync {
  CodeSync._();
  static const appareilRevoque = 'appareil_revoque';
  static const jetonExpire = 'jeton_expire';
  static const droitRefuse = 'droit_refuse';
  static const epochInconnue = 'epoch_inconnue';
  static const versionConflictuelle = 'version_conflictuelle';
  static const invariantViole = 'invariant_viole';
  static const schemaIncompatible = 'schema_incompatible';
  static const suppressionInterdite = 'suppression_interdite';
  static const ficheArchivee = 'fiche_archivee';
  static const pieceEmiseImmuable = 'piece_emise_immuable';
  static const journalImmuable = 'journal_immuable';
  static const numeroHorsPlage = 'numero_hors_plage';
  static const doublonNumero = 'doublon_numero';
}
