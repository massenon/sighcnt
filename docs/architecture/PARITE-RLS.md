# Parité du panneau superadmin du relais (module RLS, domaine « Relais en ligne »)

**Mise à jour du 01/11/2026 : cette décision est remplacée.** Les douze écrans sont AUSSI portés dans `apps/poste` (`lib/modules/rls/`, N1 = 100 % mesuré par `parite_ecrans_test.dart`), lus par la mère ; le panneau Laravel reste la source de vérité de ce que seul le relais connaît (écarts E1740 à E1752). La garde de parité accepte donc désormais ces douze ids dans `ecransPortes`, et `servisParWeb` proposé plus bas n'a plus d'objet.

Décision d'origine, du 31/10/2026 : les douze écrans RLS ne sont pas refaits en Flutter. Ils sont servis par `apps/web` (Laravel 12 + Livewire) et déclarés « porté (apps/web) » une fois la parité contrôlée contre les fiches de la maquette (`docs/architecture/ecrans/rls-*.json`).

## Méthode

- Mesure : `apps/web/tests/Feature/Panneau/ParitePanneauTest.php`. Il rend chaque page sous un compte superadmin de test, sur un jeu minimal qui fait dessiner chaque tableau (les en-têtes d'un tableau vide ne se dessinent pas), et compare aux fiches avec les règles de `apps/poste/test/parite/extracteur.dart` :
  - attendus : titre, description, KPI, onglets, en-têtes de tableaux, champs, cartes (chiffres neutralisés des deux côtés) et commandes (chiffres de fin retirés) ;
  - un libellé est présent s'il égale ou est contenu dans UN texte visible (jamais dans la concaténation de la page) : un texte visible = un élément sans bloc dedans, plus le texte direct des blocs, plus les attributs `title`, `placeholder`, `aria-label` ;
  - normalisation : espaces réduits, trim, minuscules.
- Deux différences avec la mesure Flutter : la mesure ne porte que sur `<main>` (le menu du panneau nomme les douze écrans sur chaque page et rendrait la mesure complaisante), et les tirets cadratins sont ramenés à une virgule des deux côtés (E1420).
- Le test garde sa propre mesure : `test_la_mesure_n_est_pas_complaisante` vérifie qu'un libellé absent est bien signalé. Un second garde interdit les tirets cadratins dans les vues et classes du panneau.
- Rapport engendré : `docs/architecture/rapport-parite-rls.json` (réécrit à chaque passage du test).
- Les valeurs de données ne sont pas comparées (jeu différent), comme côté Flutter.

## Résultats (N1 mesuré)

« Avant » = `apps/web` au commit de départ (3c7ce3f), mesuré avec la même fonction sur un jeu équivalent. Les huit pages absentes ne répondaient pas (aucune route).

| Écran | Route / composant Livewire / vue | N1 avant | N1 après |
|---|---|---|---|
| `rls-tableau` | `/panneau`, `Tableau`, `livewire/panneau/tableau.blade.php` | 2/10 (20 %) | 10/10 (100 %) |
| `rls-appareils` | `/panneau/appareils`, `Appareils`, `appareils.blade.php` | 6/9 (67 %) | 9/9 (100 %) |
| `rls-boites` | `/panneau/boites`, `Boites`, `boites.blade.php` | page absente | 12/12 (100 %) |
| `rls-codes` | `/panneau/codes`, `Codes`, `codes.blade.php` | 3/10 (30 %) | 10/10 (100 %) |
| `rls-indicateurs` | `/panneau/indicateurs`, `Indicateurs`, `indicateurs.blade.php` | page absente | 9/9 (100 %) |
| `rls-alertes` | `/panneau/alertes`, `Alertes`, `alertes.blade.php` | page absente | 8/8 (100 %) |
| `rls-journal` | `/panneau/journal`, `Journal` (inchangé), `journal.blade.php` | 5/7 (71 %) | 7/7 (100 %) |
| `rls-superadmin` | `/panneau/superadmin`, `Superadmin`, `superadmin.blade.php` | page absente | 12/12 (100 %) |
| `rls-parametres` | `/panneau/parametres`, `Parametres`, `parametres.blade.php` | page absente | 6/6 (100 %) |
| `rls-hebergement` | `/panneau/hebergement`, `Hebergement`, `hebergement.blade.php` | page absente | 10/10 (100 %) |
| `rls-sauvegarde` | `/panneau/sauvegarde`, `Sauvegarde`, `sauvegarde.blade.php` | page absente | 8/8 (100 %) |
| `rls-opacite` | `/panneau/opacite`, `Opacite`, `opacite.blade.php` | page absente | 8/8 (100 %) |

Composants dans `apps/web/app/Livewire/Panneau/`, vues dans `apps/web/resources/views/livewire/panneau/`, routes dans `apps/web/routes/web.php` (toutes derrière `auth`). `hub-rls` (page d'accueil de module de la maquette) n'a pas d'équivalent : le menu du panneau en tient lieu.

## Ce qui manquait et ce qui a été ajouté dans apps/web

Le relais reste opaque : aucune clé, aucune règle de gestion, aucun contenu de santé. Les ajouts sont des horodatages, des compteurs publiés par la mère et des mesures techniques.

- Libellés : titres, descriptions, KPI, en-têtes, cartes et commandes alignés sur les fiches (apostrophes typographiques comprises).
- Schéma (`2026_10_31_000000_relais_panneau_complet.php`) : `relais_codes.cree` et `utilise_le`, `relais_alertes`, `relais_indicateurs_historique`, `relais_exports`.
- Contrôleur du relais : trois lignes (horodatage de déclaration et d'usage d'un code, historique des indicateurs publiés). Le test `test_le_relais_ne_contient_aucun_chiffrement_ni_cle` passe toujours. Aucun comportement du contrat n'a changé.
- `App\Relais\Surveillance` : quatre alertes (battement, appareil bloqué publié par la mère, disque, cron), ouverture et résolution tenues en base et journalisées (acteur « système », RG-12), courriel d'alerte sans nom de patient.
- `App\Relais\Exporteur` et commande `relais:exporter [--avant-migration]` : export `.jsonl.gz` des tables `relais_*` (sans comptes ni sessions), journalisé.
- `App\Relais\Opacite` : entropie et contenu lisible mesurés sur les 200 dernières enveloppes.
- Commande `relais:surveiller` (chaque minute : passage du cron, alertes, purge de l'historique des indicateurs à 48 h) et export quotidien, planifiés dans `routes/console.php`. `relais:purger` lit désormais `relais.retention_audit_jours` (365 par défaut).
- Changement de mot de passe du superadmin (ancien mot de passe vérifié, 12 caractères, jamais journalisé), courriel de test, export manuel : gestes journalisés.
- Config : `retention_audit_jours`, `seuil_disque_pct`, `seuil_cron_ms`, `alertes`.
- Tests : `PanneauCompletTest` (13 tests de comportement) et `ParitePanneauTest` (3 tests). Suite complète : 50 tests, 253 assertions, verts (SQLite en mémoire).

Écarts consignés : `docs/architecture/ECARTS-MAQUETTE.md`, section RLS, E1420 à E1431.

## Ce qui n'est pas vérifié ou pas fait

- Tests lancés sur SQLite en mémoire seulement ; pas rejoués sur PostgreSQL (`DB_CONNECTION=pgsql`), alors que la version de la base et `pdo_pgsql` sont lus à l'écran Hébergement et que `relais:exporter` n'a été essayé que sur SQLite.
- Banc d'essai à plusieurs processus (`npm run banc:cible`, `SIGH_RELAIS=laravel`) non relancé : les trois lignes ajoutées au contrôleur n'ont été éprouvées que par les tests PHPUnit existants.
- Rendu visuel jamais regardé dans un navigateur (pas de capture) ; seul le HTML est mesuré. L'interaction Livewire du navigateur (`wire:click`, `wire:confirm`, polling) n'est testée que par `Livewire::test`.
- Mesure N1 = présence des libellés. Elle ne dit rien de la fidélité de comportement (par exemple, la maquette simule « Exporter maintenant », le panneau l'exécute vraiment).
- Non faits, dits à l'écran : expiration des codes appliquée par le relais (E1424), double facteur (E1427), liste fermée de champs d'indicateurs et refus des champs suspects (E1425), téléchargement et purge des exports (E1428), seuils d'alerte modifiables depuis le panneau (ils vivent dans `.env`).
- L'alerte « appareil bloqué » dépend de la clé `appareils_bloques` que la mère ne publie pas encore (E1425) : elle ne se lèvera pas tant que la mère ne l'envoie pas.
- Courriel d'alerte et courriel de test vérifiés avec `Mail::fake` et le pilote `array`, pas avec un vrai SMTP.
- Le certificat TLS n'est mesuré que si `APP_URL` est en https et le réseau ouvert ; non éprouvé ici.
- Installation : `composer install` avec dépendances en source échoue ici (accès GitHub non authentifié, disque saturé par le cache). `vendor/` a été copié (sans `.git`) depuis `apps/web/vendor` du poste principal, non versionné.

## Lignes proposées pour `docs/architecture/parite-statuts.json` (non appliquées)

```json
"rls-tableau": "porté",
"rls-appareils": "porté",
"rls-boites": "porté",
"rls-codes": "porté",
"rls-indicateurs": "porté",
"rls-alertes": "porté",
"rls-journal": "porté",
"rls-superadmin": "porté",
"rls-parametres": "porté",
"rls-hebergement": "porté",
"rls-sauvegarde": "porté",
"rls-opacite": "porté"
```

Statut « porté (apps/web) » : la valeur du fichier reste « porté » (le générateur `prototype_html/build/parite.js` ne connaît que `non commencé`, `porté`, `recetté`) ; la précision « apps/web » vit dans ce document. `hub-rls` est un hub engendré, hors des 12.

## La garde Flutter accepte-t-elle ce statut ?

Oui, sans correctif. `apps/poste/test/parite_ecrans_test.dart` n'itère que sur `ecransPortes()` (les écrans qui ont un widget Flutter) : la garde « déclaré porté donc 100 % » ne s'applique qu'à ces identifiants. Aucun `rls-*` n'est dans `ecransPortes()`, donc un statut « porté » les laisse hors de la mesure Flutter et ne casse rien. Deux réserves :

1. Si un jour un widget `rls-*` est ajouté à `ecransPortes()`, la garde se mettrait à les exiger à 100 % : c'est le comportement voulu.
2. Le compteur « Écrans portés » du manifeste (`PARITE-MAQUETTE.md`, engendré par `parite.js`) les comptera comme portés par Flutter. Pour que la mesure soit lisible, correctif minimal proposé (non appliqué, c'est le test du coordinateur) : dans `parite_ecrans_test.dart`, ajouter

```dart
// Écrans servis par apps/web (panneau du relais), mesurés par apps/web/tests/Feature/Panneau/ParitePanneauTest.php.
const servisParWeb = {'rls-tableau', 'rls-appareils', 'rls-boites', 'rls-codes', 'rls-indicateurs', 'rls-alertes',
  'rls-journal', 'rls-superadmin', 'rls-parametres', 'rls-hebergement', 'rls-sauvegarde', 'rls-opacite'};
```

et, dans la boucle sur `statuts`, un test supplémentaire qui vérifie que tout identifiant de `servisParWeb` déclaré « porté » est bien absent de `ecransPortes()` (un écran ne peut pas être mesuré des deux côtés) et que `rapport-parite-rls.json` donne `taux == 1.0` pour chacun.
