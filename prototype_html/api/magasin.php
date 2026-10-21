<?php
/* =============================================================================
 * SIGH-CNT — Le magasin, côté serveur
 * -----------------------------------------------------------------------------
 * GET   → rend le magasin ENTIER, dans la forme même que le prototype tient en
 *         mémoire : { "_version": 61, "patients": [...], "factures": [...] }.
 *         Le navigateur l'assigne tel quel et continue de lire de façon
 *         SYNCHRONE — aucun écran ne change.
 *
 * POST  → applique un DELTA : seules les collections modifiées voyagent.
 *         Renvoyer les 4,8 Mo à chaque geste coûterait plus cher que le
 *         localStorage qu'on remplace ; le navigateur compare donc chaque
 *         collection à ce qu'il a déjà envoyé et n'expédie que la différence.
 *
 * DELETE → vide le magasin (remise à zéro du jeu de démonstration).
 *
 * CE QUI EST VÉRIFIÉ ICI, ET CE QUI NE L'EST PAS — à ne pas confondre :
 *   — une écriture EXIGE une session ouverte (`api/session.php`), et la
 *     session est tenue par le SERVEUR : une page qui se contenterait de
 *     poster n'obtient rien. C'est déjà plus qu'un RBAC de navigateur, qui
 *     se contourne avec la console ;
 *   — la matrice des droits par module, elle, vit encore dans le manifeste
 *     JavaScript. Le serveur ne la connaît pas et ne prétend donc pas la
 *     faire respecter. La porter ici suppose de la décrire en PHP : c'est le
 *     pas suivant, et l'annoncer fait est ce qu'il ne faut pas faire.
 * ========================================================================== */

require __DIR__ . '/config.php';
require_once __DIR__ . '/projection.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}

$methode = $_SERVER['REQUEST_METHOD'] ?? 'GET';

/* --------------------------------------------------------------------------
 * LECTURE — le magasin entier
 * ------------------------------------------------------------------------ */
if ($methode === 'GET') {
    $sortie = [];
    foreach ($pdo->query('SELECT cle, valeur FROM meta') as $ligne) {
        $sortie[$ligne['cle']] = json_decode($ligne['valeur'], true);
    }
    foreach ($pdo->query('SELECT nom, donnees FROM collections ORDER BY nom') as $ligne) {
        $sortie[$ligne['nom']] = json_decode($ligne['donnees'], true);
    }
    /* Un magasin VIDE se dit, il ne se déguise pas en magasin sans patients :
       le navigateur doit savoir qu'il lui revient de semer le jeu. */
    if (!$sortie) {
        sigh_repondre(['_vide' => true]);
    }
    sigh_repondre($sortie);
}

/* --------------------------------------------------------------------------
 * ÉCRITURE — un delta, et une session
 * ------------------------------------------------------------------------ */
if ($methode === 'POST') {
    $corps = sigh_corps();
    /* Le jeton est accepté à l'en-tête OU dans le corps : un envoi de dernière
       seconde (`sendBeacon`, au départ de la page) ne peut pas poser d'en-tête
       personnalisé, et c'est précisément l'envoi qu'on ne veut pas perdre. */
    $jeton = $_SERVER['HTTP_X_SIGH_JETON'] ?? '';
    if ($jeton === '') {
        $jeton = (string) ($corps['jeton'] ?? '');
    }
    $session = null;
    if ($jeton !== '') {
        $q = $pdo->prepare('SELECT * FROM sessions_poste WHERE jeton = ?');
        $q->execute([$jeton]);
        $session = $q->fetch() ?: null;
    }
    if (!$session) {
        /* RG-12 — aucune action anonyme. Une écriture sans session ouverte
           est refusée, et le refus NOMME ce qui manque : se taire ferait
           chercher le défaut dans les écrans. */
        sigh_repondre(['erreur' => 'session absente',
            'detail' => 'Aucune session de poste ouverte : ouvrez une session avant d’écrire.'], 401);
    }
    $pdo->prepare('UPDATE sessions_poste SET vue = CURRENT_TIMESTAMP WHERE jeton = ?')->execute([$jeton]);

    $collections = $corps['collections'] ?? [];
    $meta        = $corps['meta'] ?? [];

    $pdo->beginTransaction();
    try {
        if ($collections) {
            $sql = sigh_est_postgres()
                ? 'INSERT INTO collections (nom, donnees, fiches, maj) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                   ON CONFLICT (nom) DO UPDATE SET donnees = EXCLUDED.donnees,
                       fiches = EXCLUDED.fiches, maj = CURRENT_TIMESTAMP'
                : 'INSERT INTO collections (nom, donnees, fiches) VALUES (?, ?, ?)
                   ON DUPLICATE KEY UPDATE donnees = VALUES(donnees), fiches = VALUES(fiches)';
            $ins = $pdo->prepare($sql);
            foreach ($collections as $nom => $fiches) {
                if (!is_array($fiches)) {
                    continue;
                }
                $ins->execute([
                    $nom,
                    json_encode($fiches, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                    count($fiches),
                ]);
            }
        }
        if ($meta) {
            $sql = sigh_est_postgres()
                ? 'INSERT INTO meta (cle, valeur, maj) VALUES (?, ?, CURRENT_TIMESTAMP)
                   ON CONFLICT (cle) DO UPDATE SET valeur = EXCLUDED.valeur, maj = CURRENT_TIMESTAMP'
                : 'INSERT INTO meta (cle, valeur) VALUES (?, ?)
                   ON DUPLICATE KEY UPDATE valeur = VALUES(valeur)';
            $insM = $pdo->prepare($sql);
            foreach ($meta as $cle => $valeur) {
                $insM->execute([$cle, json_encode($valeur, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)]);
            }
        }
        /* La copie RELATIONNELLE suit, dans la même transaction mais dans un savepoint :
           si elle échoue, le magasin a quand même reçu son delta (api/projection.php). */
        $projection = $collections ? sigh_proj_projeter($pdo, $collections) : null;
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        sigh_repondre(['erreur' => 'écriture refusée', 'detail' => $e->getMessage()], 500);
    }

    sigh_repondre([
        'ok'          => true,
        'collections' => count($collections),
        'meta'        => count($meta),
        'par'         => $session['identifiant'] ?? $session['nom'] ?? null,
        'projection'  => $projection ? ['tables' => $projection['ok'], 'erreur' => $projection['erreur']] : null,
    ]);
}

/* --------------------------------------------------------------------------
 * REMISE À ZÉRO — le jeu de démonstration se réamorce au prochain chargement
 * ------------------------------------------------------------------------ */
if ($methode === 'DELETE') {
    $pdo->exec('DELETE FROM collections');
    $pdo->exec('DELETE FROM meta');
    sigh_proj_vider($pdo);
    sigh_repondre(['ok' => true, 'vide' => true]);
}

sigh_repondre(['erreur' => 'méthode non prise en charge'], 405);
