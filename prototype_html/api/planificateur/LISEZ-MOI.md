# Planificateur du serveur

`api/cron.php` évalue les règles à heure fixe (échéances fiscales, seuils de stock, péremptions,
rendez-vous du lendemain, créances âgées), fait la sauvegarde compressée du magasin (7 derniers jours), copie de façon incrémentale et vérifiée
les fichiers numérisés (toutes les heures, conservation illimitée) et contrôle chaque nuit leur intégrité (manquants, altérés, orphelins).

| Système | Installation |
|---|---|
| Linux | `sh api/planificateur/installer-linux.sh` |
| Windows | `.\api\planificateur\installer-windows.ps1 -Racine <dossier> -Php <php.exe>` (PowerShell administrateur) |

Sans tâche système, le serveur exécute lui-même le planificateur quand un poste l'interroge et que
rien n'a tourné depuis 5 minutes : les alertes existent, mais seulement tant qu'un poste est ouvert.
Un planificateur arrêté se voit à l'écran **Tâches planifiées** (M14) : « en retard sur leur fréquence ».
Essai à blanc : `php api/cron.php --force`.

## Où vont les sauvegardes

Par défaut dans `api/sauvegardes/`, **sur le même disque que les données** : cela ne protège pas d'une panne de disque, et l'écran **Tâches planifiées** comme une alerte
(administrateur, DAF) le disent tant que c'est le cas. Pour protéger vraiment, régler la destination sur **un autre disque ou un partage** (écran **Tâches planifiées**, « Destination de la sauvegarde ») :
le serveur refuse en le nommant un dossier inexistant, non inscriptible ou qui recouvre les fichiers, et ne le crée jamais. Une destination qui disparaît donne une exécution en erreur et une alerte critique.

Dans la destination : `magasin-AAAA-MM-JJ.json.gz` (7 derniers jours), `fichiers/<aa>/<sha256>.<ext>` et leur `.json` (jamais supprimés), `fichiers-AAAA-MM-JJ.json.gz` (manifeste daté).

| Commande | Rôle |
|---|---|
| `php api/restaurer.php --fichiers` | simulation de la restauration des fichiers (`--oui` pour appliquer) |
| `php api/restaurer.php <magasin.json.gz>` | simulation magasin et fichiers (`--oui` pour appliquer, `--sans-fichiers` pour le magasin seul) |
| `php api/controler_fichiers.php [--sauvegarde] [--json]` | contrôle d'intégrité, code de sortie 3 si un fichier manque ou est altéré |

Variables d'environnement (bancs d'essai et installations particulières) : `SIGH_FICHIERS_DIR` (dossier des fichiers), `SIGH_SAUVEGARDES_DIR` (destination par défaut), `SIGH_SAUVEGARDE_BUDGET_S` (temps accordé à une passe lancée par le serveur, 15 s par défaut).
