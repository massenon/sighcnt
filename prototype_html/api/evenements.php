<?php
/* =============================================================================
 * SIGH-CNT — Ce qui a changé ailleurs
 * -----------------------------------------------------------------------------
 * GET ?depuis=N → les événements de séquence > N écrits par D'AUTRES postes
 *                 (jamais l'écho des siens), 200 au plus, et la séquence courante.
 *
 * Le poste interroge toutes les ~3 secondes : requête courte, sans connexion
 * tenue ouverte. C'est volontaire — le serveur PHP traite une requête par
 * processus, et quinze flux tenus ouverts le saturent. Le flux poussé (SSE) est
 * pour le hub cible (ADR-0003), où une connexion ne coûte presque rien.
 * Aucun contenu de fiche ne voyage ici : collection, identifiant, séquence.
 * ========================================================================== */
require __DIR__ . '/_commun.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Sigh-Jeton');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}
try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible', 'detail' => $e->getMessage()], 503);
}
$session = sigh_exiger_session($pdo);
if (!sigh_est_postgres()) {
    sigh_repondre(['seq' => 0, 'evenements' => []]);
}
sigh_evenements_installer($pdo);
$depuis = max(0, (int) ($_GET['depuis'] ?? 0));
$q = $pdo->prepare('SELECT seq, collection, fiche_id, utilisateur, le FROM evenements
                    WHERE seq > ? AND (jeton IS DISTINCT FROM ?) ORDER BY seq LIMIT 200');
$q->execute([$depuis, $session['jeton'] ?? '']);
$lignes = $q->fetchAll(PDO::FETCH_ASSOC);
sigh_repondre(['seq' => sigh_evenement_seq($pdo), 'evenements' => $lignes, 'serveur_le' => gmdate('c')]);
