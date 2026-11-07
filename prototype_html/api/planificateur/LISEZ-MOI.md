# Planificateur du serveur

`api/cron.php` évalue les règles à heure fixe (échéances fiscales, seuils de stock, péremptions,
rendez-vous du lendemain, créances âgées) et fait la sauvegarde compressée du magasin.

| Système | Installation |
|---|---|
| Linux | `sh api/planificateur/installer-linux.sh` |
| Windows | `.\api\planificateur\installer-windows.ps1 -Racine <dossier> -Php <php.exe>` (PowerShell administrateur) |

Sans tâche système, le serveur exécute lui-même le planificateur quand un poste l'interroge et que
rien n'a tourné depuis 5 minutes : les alertes existent, mais seulement tant qu'un poste est ouvert.
Un planificateur arrêté se voit à l'écran **Tâches planifiées** (M14) : « en retard sur leur fréquence ».
Essai à blanc : `php api/cron.php --force`.
