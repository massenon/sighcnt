<?php
/* =============================================================================
 * SIGH-CNT — Socle commun des points d'entrée
 * -----------------------------------------------------------------------------
 * Ce fichier porte ce que `auth.php`, `crud.php` et `magasin.php` partagent :
 * la table des comptes, la validation de session, l'horodatage d'auteur
 * (RG-12) et le journal d'audit.
 *
 * TROIS RÈGLES Y SONT APPLIQUÉES AU SERVEUR, ET NON DANS LE NAVIGATEUR :
 *
 *   RG-12 — aucune action anonyme. Toute écriture exige un jeton de session
 *           valide, et c'est le SERVEUR qui appose `_creePar` / `_modifiePar`
 *           depuis cette session. Le client ne peut pas se faire passer pour
 *           un autre : s'il envoie ces champs, ils sont écrasés.
 *
 *   RG-13 — le cloisonnement se décide à partir du rôle PORTÉ PAR LA SESSION,
 *           lu en base, jamais à partir de ce que le navigateur annonce.
 *
 *   RG-14 — il n'existe AUCUNE action de suppression physique. Le verbe
 *           `archiver` pose `statut = 'archive'` ; `restaurer` le retire. Une
 *           demande de suppression est refusée en le disant.
 * ========================================================================== */

require_once __DIR__ . '/config.php';

/* --------------------------------------------------------------------------
 * LA TABLE DES COMPTES.
 * Les comptes vivaient dans le magasin JSON, et la page de connexion portait
 * la liste EN DUR — elle ne vérifiait d'ailleurs aucun mot de passe. Ils ont
 * désormais leur table, et le mot de passe y est HACHÉ : une base que l'on
 * exporte et que l'on s'échange ne doit jamais porter de secret en clair.
 * ------------------------------------------------------------------------ */
function sigh_installer_comptes(PDO $pdo): void
{
    if (sigh_est_postgres()) {
        $pdo->exec('CREATE TABLE IF NOT EXISTS utilisateurs (
            identifiant VARCHAR(64) PRIMARY KEY,
            nom         VARCHAR(128) NOT NULL,
            role        VARCHAR(48)  NOT NULL,
            fonction    VARCHAR(48),
            secteur     VARCHAR(48),
            mdp         VARCHAR(255) NOT NULL,
            statut      VARCHAR(16)  NOT NULL DEFAULT \'actif\',
            doit_changer BOOLEAN     NOT NULL DEFAULT FALSE,
            cree_le     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            vu_le       TIMESTAMP
        )');
        return;
    }
    $pdo->exec('CREATE TABLE IF NOT EXISTS utilisateurs (
        identifiant  VARCHAR(64) NOT NULL PRIMARY KEY,
        nom          VARCHAR(128) NOT NULL,
        role         VARCHAR(48)  NOT NULL,
        fonction     VARCHAR(48),
        secteur      VARCHAR(48),
        mdp          VARCHAR(255) NOT NULL,
        statut       VARCHAR(16)  NOT NULL DEFAULT "actif",
        doit_changer TINYINT(1)   NOT NULL DEFAULT 0,
        cree_le      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        vu_le        DATETIME
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
}

/**
 * La session du poste, lue EN BASE à partir du jeton.
 *
 * Le jeton arrive par l'en-tête `X-Sigh-Jeton` ou dans le corps. Il est
 * ENGENDRÉ PAR LE SERVEUR à la connexion : un client qui en choisirait un
 * se désignerait lui-même, ce qui viderait RG-12 de son sens.
 *
 * Retourne null si la session est absente, inconnue ou périmée.
 */
function sigh_session(PDO $pdo, ?array $corps = null): ?array
{
    $jeton = $_SERVER['HTTP_X_SIGH_JETON'] ?? '';
    if ($jeton === '' && is_array($corps)) {
        $jeton = (string) ($corps['jeton'] ?? '');
    }
    if ($jeton === '') {
        return null;
    }
    $q = $pdo->prepare('SELECT * FROM sessions_poste WHERE jeton = ?');
    $q->execute([$jeton]);
    $s = $q->fetch();
    if (!$s) {
        return null;
    }
    $pdo->prepare('UPDATE sessions_poste SET vue = CURRENT_TIMESTAMP WHERE jeton = ?')
        ->execute([$jeton]);
    return $s;
}

/** Refus NOMMÉ : un rejet muet se lit comme une panne. */
function sigh_exiger_session(PDO $pdo, ?array $corps = null): array
{
    $s = sigh_session($pdo, $corps);
    if ($s === null) {
        sigh_repondre([
            'erreur' => 'session absente',
            'detail' => 'Aucune session de poste ouverte : la connexion doit être établie avant toute écriture (RG-12).',
        ], 401);
    }
    return $s;
}

/**
 * L'ESTAMPILLE D'AUTEUR, APPOSÉE PAR LE SERVEUR (RG-12).
 * Les champs envoyés par le client sont écrasés : c'est la session qui fait
 * foi, jamais ce que le navigateur prétend.
 */
function sigh_estampiller(array $fiche, array $session, bool $creation): array
{
    $qui = $session['nom'] ?: ($session['identifiant'] ?: 'inconnu');
    $maintenant = date('c');
    if ($creation) {
        $fiche['_creePar'] = $qui;
        $fiche['_creeLe']  = $maintenant;
    } else {
        $fiche['_modifiePar'] = $qui;
        $fiche['_modifieLe']  = $maintenant;
    }
    return $fiche;
}

/**
 * LE JOURNAL D'AUDIT, ÉCRIT PAR LE SERVEUR (RG-12).
 * Il est plafonné à 400 entrées comme dans le magasin : un journal qui grossit
 * sans fin finit par n'être plus lu — et c'est la DERNIÈRE entrée qui sert.
 */
function sigh_journaliser(PDO $pdo, array $session, string $action, string $collection, string $reference, $avant, $apres): void
{
    $entree = [
        'id'          => 'AUD' . bin2hex(random_bytes(6)),
        'horodatage'  => date('c'),
        'utilisateur' => $session['nom'] ?: $session['identifiant'],
        'role'        => $session['role'],
        'action'      => $action,
        'entite'      => $collection,
        'reference'   => $reference,
        'avant'       => $avant === null ? null : mb_substr(json_encode($avant, JSON_UNESCAPED_UNICODE), 0, 100),
        'apres'       => $apres === null ? null : mb_substr(json_encode($apres, JSON_UNESCAPED_UNICODE), 0, 100),
        'statut'      => 'actif',
    ];
    sigh_ajouter_fiche($pdo, 'audit', $entree, 400);
}

/** Ajoute une fiche EN TÊTE de la collection, en UNE instruction atomique. */
function sigh_ajouter_fiche(PDO $pdo, string $collection, array $fiche, ?int $plafond = null): void
{
    $json = json_encode([$fiche], JSON_UNESCAPED_UNICODE);
    if (sigh_est_postgres()) {
        $pdo->prepare('INSERT INTO collections (nom, donnees, fiches)
                       VALUES (:nom, :j::jsonb, 1)
                       ON CONFLICT (nom) DO UPDATE
                          SET donnees = EXCLUDED.donnees || collections.donnees,
                              fiches  = collections.fiches + 1,
                              maj     = CURRENT_TIMESTAMP')
            ->execute([':nom' => $collection, ':j' => $json]);
        if ($plafond !== null) {
            /* Le plafond se taille côté base : rapporter 400 entrées pour en
               retirer une coûterait plus que l'écriture elle-même. */
            $pdo->prepare('UPDATE collections
                              SET donnees = (SELECT COALESCE(jsonb_agg(e), \'[]\'::jsonb)
                                               FROM (SELECT e FROM jsonb_array_elements(donnees) WITH ORDINALITY t(e, i)
                                                      ORDER BY i LIMIT :n) s(e))
                            WHERE nom = :nom AND jsonb_array_length(donnees) > :n2')
                ->execute([':n' => $plafond, ':n2' => $plafond, ':nom' => $collection]);
        }
        return;
    }
    $pdo->prepare('INSERT INTO collections (nom, donnees, fiches) VALUES (:nom, :j, 1)
                   ON DUPLICATE KEY UPDATE donnees = JSON_MERGE_PRESERVE(VALUES(donnees), donnees),
                                           fiches  = fiches + 1')
        ->execute([':nom' => $collection, ':j' => $json]);
}

/**
 * Applique un correctif à la fiche désignée, EN UNE instruction.
 * Deux postes qui touchent la même collection ne s'écrasent donc pas l'un
 * l'autre : on ne rapporte pas la collection pour la réécrire entière.
 * Retourne la fiche telle qu'elle est APRÈS écriture, ou null si introuvable.
 */
function sigh_modifier_fiche(PDO $pdo, string $collection, string $id, array $correctif): ?array
{
    $avant = sigh_lire_fiche($pdo, $collection, $id);
    if ($avant === null) {
        return null;
    }
    $json = json_encode($correctif, JSON_UNESCAPED_UNICODE);
    if (sigh_est_postgres()) {
        $pdo->prepare('UPDATE collections
                          SET donnees = (SELECT COALESCE(jsonb_agg(
                                           CASE WHEN e->>\'id\' = :id THEN e || :c::jsonb ELSE e END
                                         ), \'[]\'::jsonb) FROM jsonb_array_elements(donnees) e),
                              maj = CURRENT_TIMESTAMP
                        WHERE nom = :nom')
            ->execute([':id' => $id, ':c' => $json, ':nom' => $collection]);
    } else {
        /* MySQL : pas d'agrégat jsonb — on relit, on modifie, on réécrit. */
        $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
        $q->execute([$collection]);
        $arr = json_decode((string) $q->fetchColumn(), true) ?: [];
        foreach ($arr as &$e) {
            if (($e['id'] ?? null) === $id) {
                $e = array_merge($e, $correctif);
            }
        }
        unset($e);
        $pdo->prepare('UPDATE collections SET donnees = ? WHERE nom = ?')
            ->execute([json_encode($arr, JSON_UNESCAPED_UNICODE), $collection]);
    }
    return sigh_lire_fiche($pdo, $collection, $id);
}

/** Une fiche, par son identifiant. */
function sigh_lire_fiche(PDO $pdo, string $collection, string $id): ?array
{
    if (sigh_est_postgres()) {
        $q = $pdo->prepare('SELECT e FROM collections c, jsonb_array_elements(c.donnees) e
                             WHERE c.nom = :nom AND e->>\'id\' = :id LIMIT 1');
        $q->execute([':nom' => $collection, ':id' => $id]);
        $brut = $q->fetchColumn();
        return $brut === false ? null : json_decode((string) $brut, true);
    }
    $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
    $q->execute([$collection]);
    $arr = json_decode((string) $q->fetchColumn(), true) ?: [];
    foreach ($arr as $e) {
        if (($e['id'] ?? null) === $id) {
            return $e;
        }
    }
    return null;
}

/** Un identifiant d'enregistrement, de la même forme que celui du magasin. */
function sigh_uid(string $prefixe): string
{
    return $prefixe . 'x' . base_convert((string) time(), 10, 36) . bin2hex(random_bytes(3));
}
