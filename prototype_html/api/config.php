<?php
/* =============================================================================
 * SIGH-CNT — Accès à la base du PROTOTYPE
 * -----------------------------------------------------------------------------
 * Le magasin vivait dans le `localStorage` du navigateur, dont le quota est de
 * 5 Mo : le jeu de démonstration y tenait à 300 Ko près, et la soupape de
 * compression s'armait au milieu d'un parcours d'essai — une écriture à
 * ~2,4 s, l'interface gelée. Cette limite est un artefact du navigateur.
 *
 * TROIS CHOSES QUE LA BASE APPORTE, ET QUE LE `localStorage` NE PEUT PAS :
 *   — plus de plafond ;
 *   — les données survivent au navigateur et se sauvegardent (`pg_dump`) ;
 *   — PLUSIEURS POSTES VOIENT LE MÊME MAGASIN. C'est cela, simuler une
 *     clinique : le stockage par navigateur en est structurellement incapable.
 *
 * UNE BASE À PART, ET C'EST LE POINT LE PLUS IMPORTANT DE CE FICHIER.
 * `sigh_cnt` porte le schéma de la CIBLE — 173 tables, 61 migrations Laravel,
 * l'application `sigh_web/`. Le prototype écrit dans `sigh_prototype`, et nulle
 * part ailleurs : y mêler ses collections en JSON polluerait un schéma
 * relationnel que personne n'a demandé de mélanger, et l'on ne saurait plus,
 * au moment de la reprise, ce qui vient de la maquette et ce qui vient du
 * produit.
 *
 * LES IDENTIFIANTS NE SONT PAS DANS LE DÉPÔT : ils vivent dans
 * `config.local.php`, ignoré par git. Ce fichier-ci ne porte que des valeurs
 * de repli, utilisables seulement sur un poste de développement.
 * ========================================================================== */

$local = __DIR__ . '/config.local.php';
$reglages = is_file($local) ? (require $local) : [];

/* LA BASE SE SURCHARGE PAR L'ENVIRONNEMENT — et c'est ce qui rend les bancs
   d'essai possibles. Depuis que le serveur est OBLIGATOIRE, un test qui
   tournerait sur la base de travail y laisserait ses fiches de sonde et
   ferait dépendre chaque exécution de la précédente. `SIGH_BASE` pointe donc
   les épreuves sur une base jetable, et la base de travail n'est jamais
   touchée par un test. */
$baseEnv = getenv('SIGH_BASE');
if (is_string($baseEnv) && $baseEnv !== '') {
    $reglages['dsn'] = preg_replace('/dbname=[^;]*/', 'dbname=' . $baseEnv,
        $reglages['dsn'] ?? 'pgsql:host=127.0.0.1;port=5432;dbname=sigh_prototype');
}

define('SIGH_DSN',  $reglages['dsn']  ?? 'pgsql:host=127.0.0.1;port=5432;dbname=sigh_prototype');
define('SIGH_USER', $reglages['user'] ?? 'postgres');
define('SIGH_PASS', $reglages['pass'] ?? '');

/** La connexion, ouverte une seule fois par requête. */
function sigh_pdo(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO(SIGH_DSN, SIGH_USER, SIGH_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }
    return $pdo;
}

/** Vrai si l'on parle à PostgreSQL — deux ou trois tournures diffèrent. */
function sigh_est_postgres(): bool
{
    return str_starts_with(SIGH_DSN, 'pgsql:');
}

/**
 * Le schéma, créé à la demande.
 *
 * UNE LIGNE PAR COLLECTION, et non par enregistrement. Le prototype charge son
 * magasin entier en mémoire au démarrage et le lit de façon SYNCHRONE — c'est
 * ce qui permet aux quelque trois cents écrans de faire
 * `S.collection('patients').active()` sans qu'aucun ne change. Découper en
 * lignes par fiche imposerait des requêtes par écran, donc de tout rendre
 * asynchrone : ce serait exactement la réécriture que l'on veut éviter.
 *
 * Le modèle relationnel complet appartient à la cible (`sigh_web`, migrations
 * Laravel). Ici la base a un rôle précis et suffisant : porter le magasin sans
 * plafond, le partager entre postes, et le rendre sauvegardable.
 */
function sigh_installer(PDO $pdo): void
{
    if (sigh_est_postgres()) {
        $pdo->exec('CREATE TABLE IF NOT EXISTS collections (
            nom     VARCHAR(64) PRIMARY KEY,
            donnees JSONB       NOT NULL,
            fiches  INTEGER     NOT NULL DEFAULT 0,
            maj     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS meta (
            cle    VARCHAR(64) PRIMARY KEY,
            valeur JSONB       NOT NULL,
            maj    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS sessions_poste (
            jeton      VARCHAR(64) PRIMARY KEY,
            identifiant VARCHAR(64),
            nom        VARCHAR(128),
            role       VARCHAR(48),
            fonction   VARCHAR(48),
            secteur    VARCHAR(48),
            poste      VARCHAR(64),
            ouverte    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            vue        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )');
        return;
    }
    $pdo->exec('CREATE TABLE IF NOT EXISTS collections (
        nom     VARCHAR(64) NOT NULL PRIMARY KEY,
        donnees JSON        NOT NULL,
        fiches  INT         NOT NULL DEFAULT 0,
        maj     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    $pdo->exec('CREATE TABLE IF NOT EXISTS meta (
        cle    VARCHAR(64) NOT NULL PRIMARY KEY,
        valeur JSON        NOT NULL,
        maj    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    $pdo->exec('CREATE TABLE IF NOT EXISTS sessions_poste (
        jeton       VARCHAR(64) NOT NULL PRIMARY KEY,
        identifiant VARCHAR(64),
        nom         VARCHAR(128),
        role        VARCHAR(48),
        fonction    VARCHAR(48),
        secteur     VARCHAR(48),
        poste       VARCHAR(64),
        ouverte     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        vue         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
}

/** Réponse JSON, en UTF-8 et sans échappement inutile. */
function sigh_repondre($donnees, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($donnees, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PARTIAL_OUTPUT_ON_ERROR);
    exit;
}

/** Le corps d'une requête, décodé. */
function sigh_corps(): array
{
    $brut = file_get_contents('php://input');
    if ($brut === '' || $brut === false) {
        return [];
    }
    $o = json_decode($brut, true);
    return is_array($o) ? $o : [];
}
