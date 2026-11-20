<?php
/* =============================================================================
 * SIGH-CNT : la lecture ÉTROITE de la page publique d'enquête (vague 84)
 * -----------------------------------------------------------------------------
 *   GET api/enquete.php?jeton=…   (SANS session)
 *
 * La page publique ne lit plus le magasin : `magasin.php` exige une session. Elle
 * demande ici UNE chose, le modèle de l'enquête que désigne le jeton, et rien
 * d'autre : ni fiche patient, ni autre enquête, ni autre jeton.
 *
 * Réponse : { enquete: { id, titre, description, questions: [{code, libelle,
 *   type, options}] }, jeton: { id, anonyme } }. L'identifiant de l'enquête et
 * celui du jeton ne servent qu'à rattacher la réponse (elle est écrite par un
 * poste connecté, jamais par cette page anonyme).
 *
 * JETON INCONNU, EXPIRÉ, RÉVOQUÉ OU ARCHIVÉ : LA MÊME RÉPONSE, 404 générique
 * (`{ "erreur": "lien invalide" }`), qui ne nomme aucune enquête : les
 * distinguer renseignerait sur ce qui existe (CLAUDE.md, vague 54). La
 * comparaison du jeton est à temps constant. La date d'expiration se juge à
 * l'horloge du SERVEUR, jamais à celle que le client annoncerait.
 * ========================================================================== */

require __DIR__ . '/config.php';

header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Methods: GET, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    sigh_repondre(['ok' => true]);
}
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    sigh_repondre(['erreur' => 'méthode non prise en charge'], 405);
}

function sigh_enquete_refus(): void
{
    sigh_repondre(['erreur' => 'lien invalide'], 404);
}

$code = (string) ($_GET['jeton'] ?? '');
if (!preg_match('/^[A-Za-z0-9]{8,64}$/', $code)) {
    sigh_enquete_refus();
}

try {
    $pdo = sigh_pdo();
    $lire = function (string $nom) use ($pdo): array {
        $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
        $q->execute([$nom]);
        $d = $q->fetchColumn();
        $a = $d === false ? [] : json_decode((string) $d, true);
        return is_array($a) ? $a : [];
    };
    $jetons = $lire('jetonsEnquete');
    $enquetes = $lire('enquetes');
} catch (Throwable $e) {
    sigh_repondre(['erreur' => 'base indisponible'], 503);
}

$aujourdhui = (new DateTime('now', new DateTimeZone('Africa/Porto-Novo')))->format('Y-m-d');
$jeton = null;
foreach ($jetons as $j) {
    if (is_array($j) && isset($j['jeton']) && hash_equals((string) $j['jeton'], $code)) {
        $jeton = $j;
        break;
    }
}
if ($jeton === null
    || ($jeton['statut'] ?? '') === 'archive'
    || !empty($jeton['revoqueLe'])
    || (!empty($jeton['expireLe']) && substr((string) $jeton['expireLe'], 0, 10) < $aujourdhui)) {
    sigh_enquete_refus();
}
$enq = null;
foreach ($enquetes as $e) {
    if (is_array($e) && ($e['id'] ?? null) === ($jeton['enqueteId'] ?? '')) {
        $enq = $e;
        break;
    }
}
if ($enq === null || ($enq['statut'] ?? '') === 'archive') {
    sigh_enquete_refus();
}

$questions = [];
foreach (($enq['questions'] ?? []) as $q) {
    if (!is_array($q)) {
        continue;
    }
    $questions[] = [
        'code'    => $q['code'] ?? null,
        'libelle' => $q['libelle'] ?? '',
        'type'    => $q['type'] ?? 'texte',
        'options' => isset($q['options']) && is_array($q['options']) ? array_values($q['options']) : null,
    ];
}
sigh_repondre([
    'enquete' => [
        'id'          => $enq['id'],
        'titre'       => $enq['titre'] ?? '',
        'description' => $enq['description'] ?? null,
        'questions'   => $questions,
    ],
    'jeton'   => ['id' => $jeton['id'] ?? null, 'anonyme' => !empty($jeton['anonyme'])],
]);
