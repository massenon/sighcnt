# PRD : Poste, installateur Windows (build_windows.bat + Inno Setup)

Statut : **proposé le 05/11/2026**, en attente des arbitrages de la section 9.
Sources : demande de la Direction du 05/11/2026 (deux exemples d'installateurs Inno Setup déjà livrés sur d'autres projets), `docs/guides/GUIDE-LANCEMENT-LOCAL.md`, `apps/poste/lib/main.dart`, `apps/poste/windows/`.
Règle de rédaction : pas de tiret cadratin comme ponctuation.

## 1. Problème

Le poste (Flutter, modes fileul et mère) ne se lance aujourd'hui qu'avec `flutter run` depuis un dépôt cloné. Une clinique ne peut pas l'installer : pas d'exécutable livrable, pas de raccourci, pas de désinstallation, pas de procédure de mise à jour. Pire, `dossierDonnees` vaut par défaut `donnees-poste`, un chemin RELATIF au dossier courant : installé sous `C:\Program Files`, le poste écrirait dans un dossier non inscriptible, ou ailleurs selon le raccourci. La base de la clinique (SQLite chiffré, clé locale, magasin de fichiers) doit survivre aux mises à jour et ne jamais se perdre par accident.

Coût de ne rien faire : chaque installation est un travail d'informaticien, une mise à jour peut faire perdre des saisies non synchronisées, et un poste neuf sans le runtime Visual C++ ne démarre pas, sans message.

## 2. Objectifs

- **O1.** Un seul geste produit l'installateur : `build_windows.bat` aboutit à `build\installer\SIGH_Poste_Setup_<version>.exe`, ou s'arrête à la première étape en échec en NOMMANT le fichier ou la commande en cause.
- **O2.** Une nouvelle version REMPLACE l'ancienne (même identifiant d'application) sans toucher aux données : critère, installer v0.1.0, créer un compte et des fiches, installer v0.1.1 par-dessus, retrouver tout.
- **O3.** Les données vivent HORS du dossier d'installation. Critère : après désinstallation silencieuse, la base est intacte.
- **O4.** Aucune suppression de données par accident : sauvegarde proposée, avertissement Oui/Non avec « Non » par défaut, mode silencieux = données gardées.
- **O5.** Un poste Windows neuf démarre l'application, ou le script de build refuse de produire un installateur sans les trois DLL du runtime Visual C++.
- **O6.** La version vient d'UNE source, `apps/poste/pubspec.yaml`.

## 3. Non-objectifs

- **Signature de code** (certificat Authenticode) : coût et fournisseur à décider, voir Q5. Sans elle, SmartScreen avertit au premier lancement.
- **Mise à jour automatique en ligne** : la mise à jour est un nouvel installateur lancé à la main. Un service de mise à jour demande un serveur de distribution.
- **Installateur Android / mobile** : hors sujet, le mobile suit un autre circuit.
- **Linux** : le dossier `linux/` existe mais n'est pas livré ici.
- **Migration automatique de schéma de données entre versions** : portée par le poste lui-même (`_version` du magasin), pas par l'installateur.

## 4. Les deux fichiers

### 4.1 `apps/poste/build_windows.bat`

Enchaînement, avec arrêt à la première erreur (`if errorlevel 1`) et message qui nomme l'étape :

1. **Prérequis** : `flutter` et `ISCC.exe` (Inno Setup 6) trouvés, sinon message avec le lien d'installation.
2. **Fermer l'application** : `taskkill /F /IM sigh_poste.exe` et `flutter_tester.exe` (un `sqlite3.dll` verrouillé fait échouer `flutter build`).
3. **Lire la version** dans `pubspec.yaml` (`version: x.y.z+n`) : `AppVersion=x.y.z`.
4. `flutter pub get`.
5. **Génération de code** : `dart run build_runner build` (sans `--delete-conflicting-outputs`, absent des versions récentes). Étape sautée si aucun `build_runner` n'est déclaré, voir Q7.
6. `flutter build windows --release`.
7. **Vérification des sources de l'installateur** : chaque fichier référencé par le `.iss` est testé et le premier absent est NOMMÉ (l'incident connu : « The system cannot find the path specified » sans nom). Liste minimale : `sigh_poste.exe`, `flutter_windows.dll`, `sqlite3.dll`, `data\app.so`, `data\icudtl.dat`, `data\flutter_assets`, icône, `installer\poste.example.json`.
8. **Runtime Visual C++** : copier `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` depuis `%SystemRoot%\System32` vers le dossier de sortie ; s'arrêter si l'une manque.
9. `ISCC.exe /DAppVersion=%VERSION% installer\sigh_poste.iss`.
10. **Contrôle final** : le `.exe` existe, sa taille est affichée, son SHA-256 est écrit à côté (`.sha256`).

### 4.2 `apps/poste/installer/sigh_poste.iss`

- **AppId fixe**, généré UNE fois (`{{GUID}`) et jamais changé. Il est consigné dans ce PRD et dans le `.iss`, avec le commentaire « ne jamais changer ».
- `AppName=SIGH-CNT Poste`, éditeur : Clinique Nassiera Too, `DefaultDirName={autopf}\SIGH-CNT`, `ArchitecturesAllowed=x64compatible`, `CloseApplications=yes`.
- `[Files]` : tout `build\windows\x64\runner\Release\*` plus le modèle `poste.example.json` (aucune valeur réelle).
- `[Icons]` : menu Démarrer, désinstallation, bureau (case décochée par défaut).
- `[Languages]` : français.
- `OutputDir=..\build\installer`, `OutputBaseFilename=SIGH_Poste_Setup_{#AppVersion}`.
- `[Code]` : voir la section 6 (désinstallation).

## 5. Où vivent les données

| Quoi | Où | Pourquoi |
|---|---|---|
| Base mère/fileul, magasin de fichiers, clé locale, sauvegardes de la mère | `%LOCALAPPDATA%\SIGHCNT\donnees\` | machine locale, non itinérant, volumineux |
| Configuration du poste (mode, adresse du relais, appairage) | `%APPDATA%\SIGHCNT\` | configuration de l'utilisateur |
| Archives de clôture exportées, états PDF | `Documents\SIGH-CNT\` | l'utilisateur doit les retrouver |

**Prérequis de code (bloquant)** : aujourd'hui `dossierDonnees` est `String.fromEnvironment('SIGH_DONNEES', defaultValue: 'donnees-poste')`. Il faut résoudre le dossier à l'exécution : si `SIGH_DONNEES` est défini (développement, tests), l'utiliser ; sinon `%LOCALAPPDATA%\SIGHCNT\donnees` sous Windows, avec création au premier démarrage et un message NOMMÉ si le dossier n'est pas inscriptible. Les tests continuent de passer un dossier explicite. Aucune donnée ne s'écrit sous `{app}`.

Mise à jour : l'installateur ne lit, ne déplace ni ne supprime jamais ces dossiers.

## 6. Désinstallation

Ordre des gestes (interface) :

1. **Fermeture** du poste en cours (`taskkill`), car une base ouverte ne se copie pas de façon cohérente.
2. **Proposition de sauvegarde** (Oui par défaut) : copie des données vers `Documents\SIGH-CNT-Sauvegarde-AAAA-MM-JJ_HHMM`, jamais supprimée par la désinstallation. Échec de sauvegarde : message et choix de continuer ou d'annuler (annuler par défaut).
3. **Avertissement** Oui/Non avec **Non par défaut**, qui liste ce qui sera supprimé (base locale, clé de chiffrement, configuration, archives exportées) et le dit : les saisies NON SYNCHRONISÉES seront perdues, définitivement. Un poste MÈRE reçoit un avertissement renforcé : sa base est la copie de référence de la clinique, les fileuls ne la reconstituent pas entièrement.
4. **Oui** : désinstaller et supprimer les données (`[UninstallDelete]` sous condition `SupprimerLesDonnees`). **Non** : la désinstallation est annulée, rien n'est retiré.
5. **Mode silencieux** (`/SILENT`, `/VERYSILENT`) : les données sont GARDÉES, aucune question, aucune suppression.

La clé de chiffrement du magasin (`cle-poste.bin`, protégée par DPAPI sous Windows) suit les données : la supprimer sans la base rend la base illisible, la garder sans la base ne sert à rien. Les deux partent ou restent ensemble.

## 7. Récits d'utilisateur

- En tant qu'**informaticien de la clinique**, je lance `build_windows.bat` et j'obtiens un seul `.exe`, ou un message qui nomme exactement ce qui manque, afin de ne pas deviner.
- En tant qu'**administrateur d'un poste**, j'installe une nouvelle version par-dessus l'ancienne et je retrouve mes comptes et mes fiches, afin de mettre à jour sans peur.
- En tant que **responsable de la clinique**, je désinstalle un poste de caisse : on me propose d'abord une sauvegarde, puis on me demande de confirmer la perte des données, « Non » étant le choix par défaut, afin qu'un clic distrait ne détruise rien.
- En tant que **personne qui déploie à distance**, je lance l'installateur en `/VERYSILENT` et je désinstalle en silencieux sans jamais perdre de données, afin d'automatiser sans risque.
- En tant qu'**utilisateur d'un poste neuf**, je démarre l'application sans avoir installé le runtime Visual C++, afin de ne pas tomber sur un échec muet.
- Cas limites : installation sur un poste où l'ancienne version tourne (fermeture proposée) ; build lancé alors que l'application est ouverte (fermée par le script) ; dossier de données non inscriptible (message nommé) ; disque plein pendant la sauvegarde (choix explicite).

## 8. Exigences et critères d'acceptation

### P0 (sans eux, pas de livraison)

| # | Exigence | Critère |
|---|---|---|
| R1 | `build_windows.bat` produit `SIGH_Poste_Setup_<version>.exe` | un poste de build propre donne le `.exe` en une commande ; chaque étape en échec s'arrête avec son nom |
| R2 | AppId fixe | v0.1.0 puis v0.1.1 s'installent dans le même dossier, une seule entrée dans « Applications installées » |
| R3 | Données hors de `{app}` (prérequis de code section 5) | après installation, aucun fichier de données sous `Program Files` ; la base se crée sous `%LOCALAPPDATA%\SIGHCNT\donnees` |
| R4 | Mise à jour sans perte | un test manuel documenté : comptes et fiches intacts après mise à jour |
| R5 | Désinstallation : sauvegarde, avertissement, Non par défaut, Non annule, Oui supprime | cinq cas déroulés : Non, Oui sans sauvegarde, Oui avec sauvegarde, sauvegarde en échec, silencieux |
| R6 | Silencieux garde les données | `/VERYSILENT` puis recherche du dossier de données : présent |
| R7 | Vérification de chaque source avant ISCC | on supprime `poste.example.json` : le script nomme ce fichier et s'arrête |
| R8 | Trois DLL Visual C++ copiées, arrêt si l'une manque | on masque `vcruntime140_1.dll` : le script s'arrête en la nommant |
| R9 | Fermeture de l'application avant le build | le build réussit avec le poste ouvert au départ |
| R10 | Version unique dans `pubspec.yaml` | changer la version là-bas change le nom du `.exe` et la version affichée dans Windows |

### P1

- R11 : SHA-256 écrit à côté du `.exe`, et rappelé dans le message final.
- R12 : le poste affiche sa version (écran « À propos » ou pied) lue depuis le paquet, pour vérifier une mise à jour sans ouvrir l'installateur.
- R13 : avertissement renforcé à la désinstallation d'un poste mère.
- R14 : `/DAppEnv=dev|recette|production` et refus d'une version suffixée `-demo` en production (le garde-fou de l'exemple AgriERP).

### P2 (à ne pas rendre difficile)

- Signature de code ; mise à jour automatique ; paquet MSIX ; installation par utilisateur sans droits administrateur.

## 9. Décisions à valider par la Direction

| # | Question | Ma recommandation | Qui |
|---|---|---|---|
| **Q1** | Désinstaller supprime-t-il les données après Oui, ou les garde-t-il toujours ? Les deux exemples livrés les suppriment sur Oui | **Supprimer sur Oui**, avec sauvegarde proposée et Non par défaut, comme vos deux exemples | Direction |
| **Q2** | Nom commercial et nom de fichier : « SIGH-CNT Poste » / `SIGH_Poste_Setup_<version>.exe` ? | oui, avec le dossier de données `SIGHCNT` | Direction |
| **Q3** | Droits : installation en administrateur (`Program Files`) ou par utilisateur ? | administrateur, un seul emplacement par poste | Direction |
| **Q4** | Un poste mère se désinstalle-t-il avec le même avertissement qu'un fileul ? | avertissement renforcé (R13), car sa base est la copie de référence | Direction |
| **Q5** | Signature de code : achat d'un certificat ? | différer ; documenter l'avertissement SmartScreen au déploiement | Direction |
| **Q6** | Emplacement des sauvegardes de désinstallation : `Documents\SIGH-CNT-Sauvegarde-...` ? | oui, jamais supprimé par le désinstallateur | Direction |
| **Q7** | `build_runner` : le poste en a-t-il besoin aujourd'hui ? (`drift` est déclaré, aucun `build_runner` visible dans `pubspec.yaml`) | étape conditionnelle, à confirmer par l'équipe Flutter | Ingénierie |
| **Q8** | Le poste est-il compilable sous Windows avec SQLite3 Multiple Ciphers sans étape manuelle ? Jamais exécuté dans l'environnement de rédaction | à vérifier sur un vrai poste Windows avant le premier installateur | Ingénierie |

Bloquantes : Q1, Q3, Q8. Les autres peuvent se résoudre pendant la réalisation.

## 10. Métriques de réussite

- **Avant livraison** : 10 critères P0 déroulés sur une machine Windows 10 et une Windows 11 vierges ; 0 échec muet.
- **Après un mois** : 100 % des postes installés par l'installateur ; 0 incident de données perdues à la mise à jour ; temps d'installation d'un poste neuf sous 10 minutes, hors paramétrage.
- **Après un trimestre** : au moins 2 mises à jour passées sans intervention d'un développeur.

## 11. Ce qui ne peut pas être vérifié ici

Cet environnement n'a ni Windows, ni Visual Studio, ni Inno Setup. `flutter build windows`, la compilation du `.iss`, la protection DPAPI de la clé et le comportement réel de `[UninstallDelete]` sont donc écrits à partir de vos deux exemples et de la documentation, mais **non exécutés**. Le premier essai sur un vrai poste fera le travail de recette ; les cinq cas de désinstallation de R5 sont à y rejouer.

## 12. Phasage

1. **Phase A (prérequis de code)** : résolution du dossier de données à l'exécution (section 5), avec test.
2. **Phase B** : `build_windows.bat` et `sigh_poste.iss` (P0).
3. **Phase C** : recette sur poste vierge, puis P1.
