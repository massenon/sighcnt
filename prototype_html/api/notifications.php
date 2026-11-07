<?php
/* =============================================================================
 * SIGH-CNT — Les notifications du serveur
 * -----------------------------------------------------------------------------
 * GET                  → les alertes OUVERTES produites par le planificateur,
 *                        pour le poste qui les demande. Le serveur exécute
 *                        lui-même le planificateur s'il n'a pas tourné depuis
 *                        plus de 5 minutes (pseudo-cron).
 * GET ?action=taches   → le registre des tâches et leurs dernières exécutions
 *                        (administration : écran « Tâches planifiées »).
 * POST action=executer → lance une tâche maintenant (administrateur).
 *
 * Le filtrage par poste se fait ICI : une alerte ne quitte pas le serveur
 * pour un rôle qui n'est pas dans sa liste (RG-13).
 * ========================================================================== */

require __DIR__ . '/_commun.php';
require_once __DIR__ . '/cron.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
    sigh_cron_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}

$corps = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' ? sigh_corps() : null;
$session = sigh_exiger_session($pdo, $corps);
$role = (string) ($session['role'] ?? '');
$action = $_GET['action'] ?? ($corps['action'] ?? '');

/* Pseudo-cron : seulement si le planificateur du système n'a pas tourné. */
$derniere = $pdo->query('SELECT MAX(derniere_le) FROM taches_planifiees')->fetchColumn();
if (!$derniere || time() - strtotime((string) $derniere) > 300) {
    try {
        sigh_cron_executer($pdo, 'pseudo-cron');
    } catch (Throwable $e) { /* une panne du planificateur ne ferme pas la cloche */ }
}

if ($action === 'taches') {
    if (!in_array($role, ['admin', 'da', 'direction'], true)) {
        sigh_repondre(['erreur' => 'accès refusé', 'detail' => 'Le registre des tâches est réservé à l’administration.'], 403);
    }
    $taches = $pdo->query('SELECT * FROM taches_planifiees ORDER BY code')->fetchAll();
    $histo = $pdo->query('SELECT * FROM executions_taches ORDER BY id DESC LIMIT 40')->fetchAll();
    sigh_repondre(['taches' => $taches, 'executions' => $histo]);
}

if ($action === 'executer') {
    if ($role !== 'admin') {
        sigh_repondre(['erreur' => 'accès refusé', 'detail' => 'Seul l’administrateur système lance une tâche à la main.'], 403);
    }
    $code = (string) ($corps['code'] ?? '');
    $rapport = sigh_cron_executer($pdo, 'manuel:' . ($session['identifiant'] ?? '?'), true, $code !== '' ? $code : null);
    sigh_repondre(['ok' => true, 'rapport' => $rapport]);
}

$lignes = $pdo->query('SELECT id, cle, tache, priorite, titre, detail, lien, postes, cree_le FROM notifications_serveur WHERE resolue_le IS NULL ORDER BY id')->fetchAll();
$sortie = [];
foreach ($lignes as $l) {
    $postes = json_decode((string) $l['postes'], true) ?: [];
    if ($postes && !in_array($role, $postes, true) && $role !== 'admin') {
        continue;
    }
    $l['postes'] = $postes;
    $sortie[] = $l;
}
sigh_repondre(['notifications' => $sortie, 'serveur_le' => gmdate('c')]);
