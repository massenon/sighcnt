/// Moteur de synchronisation SIGH-CNT : poste mère, poste fileul, mobile.
library;

export 'src/commun.dart' show arg, uuid7, Err;
export 'src/mere.dart' show Mere, ConfigMere, collectionsFichiersJamaisMobile;
export 'src/fichiers_mere.dart' show FichiersMere, chargerMatriceRbac;
export 'src/fileul.dart' show Fileul, ConfigFileul;
export 'src/mobile.dart' show Mobile, ConfigMobile;
export 'src/pair.dart' show FileulPair, ConfigPair;
export 'src/smtp.dart' show ConfigSmtp, EtapeSmtp, ResultatSmtp, envoyerSmtp;
export 'src/stockage_fichiers.dart' show StockageFichiers, ErreurFichier, FichierRange, MetaFichier, EtatLocalFichier;
// La sauvegarde, le contrôle et la restauration des fichiers numérisés d'un poste (lot D5, étape 7) : copie incrémentale vérifiée, jamais tournante, destination jamais créée.
export 'src/sauvegarde_fichiers.dart'
    show
        dossierSauvegardeFichiers,
        cheminSousOuEgal,
        verifierDestinationSauvegarde,
        sauvegarderFichiers,
        controlerSauvegardeFichiers,
        restaurerFichiers,
        RapportSauvegardeFichiers,
        RapportControleSauvegarde,
        RapportRestaurationFichiers;
