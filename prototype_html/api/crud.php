<?php
/* =============================================================================
 * SIGH-CNT — CRUD par ACTION, directement en base
 * -----------------------------------------------------------------------------
 * Chaque geste de l'interface arrive ici et se traduit par UNE instruction SQL
 * préparée. Ce point d'entrée remplace l'envoi du magasin entier : on n'écrit
 * plus une collection, on écrit une FICHE.
 *
 * CE QUI EST APPLIQUÉ ICI, ET QUE LE NAVIGATEUR NE PEUT PLUS CONTOURNER :
 *
 *   RG-12 — toute action exige une session valide ; l'auteur est apposé depuis
 *           cette session, et le journal d'audit est écrit par le serveur. Les
 *           champs `_creePar` / `_modifiePar` envoyés par le client sont
 *           IGNORÉS puis écrasés.
 *
 *   RG-14 — il n'existe aucune action de suppression. `supprimer` est refusé
 *           EN LE DISANT, et renvoie vers `archiver`. Un refus muet se lirait
 *           comme une panne ; un refus nommé enseigne la règle.
 *
 * Actions :
 *   POST {action:'inserer',   collection, fiche}
 *   POST {action:'modifier',  collection, id, correctif}
 *   POST {action:'archiver',  collection, id, motif?}
 *   POST {action:'restaurer', collection, id}
 *   POST {action:'lire',      collection, id}
 *   POST {action:'lister',    collection}
 * ========================================================================== */

require_once __DIR__ . '/_commun.php';

try {
    $pdo = sigh_pdo();
    sigh_installer($pdo);
} catch (Throwable $e) {
    sigh_repondre([
        'erreur' => 'base indisponible',
        'detail' => 'Connexion perdue avec le serveur de base de données.',
        'cause'  => $e->getMessage(),
    ], 503);
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    sigh_repondre(['erreur' => 'méthode', 'detail' => 'POST attendu.'], 405);
}

$corps      = sigh_corps();
$action     = (string) ($corps['action'] ?? '');
$collection = (string) ($corps['collection'] ?? '');

/* Le nom de collection vient du client : on le borne, faute de quoi il
   désignerait n'importe quelle ligne de la table. */
if ($collection === '' || !preg_match('/^[A-Za-z][A-Za-z0-9_]{0,63}$/', $collection)) {
    sigh_repondre(['erreur' => 'collection', 'detail' => 'Nom de collection absent ou mal formé.'], 400);
}

/* --- RG-14, AVANT TOUT LE RESTE -------------------------------------------
   Le refus se prononce avant même d'ouvrir la session : la règle ne dépend
   d'aucun droit, elle est structurelle. */
if ($action === 'supprimer' || $action === 'delete') {
    sigh_repondre([
        'erreur' => 'suppression interdite',
        'detail' => 'RG-14 — la suppression physique n’existe pas. Employer l’action « archiver » : '
                  . 'la fiche reçoit statut = archive et reste consultable à la corbeille.',
    ], 403);
}

/* --- Lectures : une session suffit, sans écriture -------------------------- */
if ($action === 'lire' || $action === 'lister') {
    sigh_exiger_session($pdo, $corps);
    if ($action === 'lire') {
        $f = sigh_lire_fiche($pdo, $collection, (string) ($corps['id'] ?? ''));
        sigh_repondre($f === null ? ['erreur' => 'introuvable'] : ['fiche' => $f], $f === null ? 404 : 200);
    }
    $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
    $q->execute([$collection]);
    $brut = $q->fetchColumn();
    sigh_repondre(['fiches' => $brut === false ? [] : json_decode((string) $brut, true)]);
}

/* --- Écritures : session OBLIGATOIRE (RG-12) ------------------------------- */
$session = sigh_exiger_session($pdo, $corps);

if ($action === 'inserer') {
    $fiche = $corps['fiche'] ?? null;
    if (!is_array($fiche)) {
        sigh_repondre(['erreur' => 'fiche', 'detail' => 'Aucune fiche à écrire.'], 400);
    }
    /* L'identifiant peut venir du client — le magasin l'engendre déjà et le
       rend à l'appelant de façon synchrone. S'il manque, le serveur en pose un. */
    if (empty($fiche['id'])) {
        $fiche['id'] = sigh_uid(strtoupper(substr($collection, 0, 3)));
    }
    if (empty($fiche['statut'])) {
        $fiche['statut'] = 'actif';
    }
    unset($fiche['_modifiePar'], $fiche['_modifieLe']);
    $fiche = sigh_estampiller($fiche, $session, true);

    /* L'INSERTION EST IDEMPOTENTE, et ce n'est pas un luxe : DEUX chemins
       d'écriture portent la même fiche. L'envoi global du magasin pose la
       collection entière — la fiche comprise — et l'action nommée la préfixe
       ensuite ; selon lequel arrive le premier, la fiche se retrouvait EN
       DOUBLE. Mesuré sur la matrice des droits : 25 fiches pour 23 rôles, et
       « une seule fiche RBAC par rôle » est précisément ce que le prototype
       exige pour que la matrice soit prévisible.
       Une fiche déjà présente sous le même identifiant est donc MISE À JOUR,
       jamais ajoutée une seconde fois. */
    $deja = sigh_lire_fiche($pdo, $collection, (string) $fiche['id']);

    $pdo->beginTransaction();
    try {
        if ($deja !== null) {
            sigh_modifier_fiche($pdo, $collection, (string) $fiche['id'], $fiche);
        } else {
            sigh_ajouter_fiche($pdo, $collection, $fiche);
            sigh_journaliser($pdo, $session, 'Création', $collection, (string) $fiche['id'], null, $fiche);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        sigh_repondre(['erreur' => 'écriture refusée', 'detail' => $e->getMessage()], 500);
    }
    sigh_repondre(['fiche' => $fiche]);
}

if ($action === 'modifier' || $action === 'archiver' || $action === 'restaurer') {
    $id = (string) ($corps['id'] ?? '');
    if ($id === '') {
        sigh_repondre(['erreur' => 'identifiant', 'detail' => 'Fiche non désignée.'], 400);
    }
    $avant = sigh_lire_fiche($pdo, $collection, $id);
    if ($avant === null) {
        sigh_repondre(['erreur' => 'introuvable',
            'detail' => 'Aucune fiche « ' . $id . ' » dans « ' . $collection . ' ».'], 404);
    }

    if ($action === 'modifier') {
        $correctif = $corps['correctif'] ?? [];
        if (!is_array($correctif)) {
            $correctif = [];
        }
        /* L'auteur ne se déclare pas : il se constate. */
        unset($correctif['_creePar'], $correctif['_creeLe'],
              $correctif['_modifiePar'], $correctif['_modifieLe']);
        $libelle = 'Modification';
    } elseif ($action === 'archiver') {
        $correctif = ['statut' => 'archive', '_archiveLe' => date('c')];
        if (!empty($corps['motif'])) {
            $correctif['_motifArchivage'] = (string) $corps['motif'];
        }
        $libelle = 'Archivage';
    } else {
        $correctif = ['statut' => 'actif'];
        $libelle = 'Restauration';
    }
    $correctif = sigh_estampiller($correctif, $session, false);

    $pdo->beginTransaction();
    try {
        $apres = sigh_modifier_fiche($pdo, $collection, $id, $correctif);
        sigh_journaliser($pdo, $session, $libelle, $collection, $id, $avant, $apres);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        sigh_repondre(['erreur' => 'écriture refusée', 'detail' => $e->getMessage()], 500);
    }
    sigh_repondre(['fiche' => $apres]);
}

sigh_repondre(['erreur' => 'action inconnue',
    'detail' => 'Actions acceptées : inserer, modifier, archiver, restaurer, lire, lister. '
              . 'La suppression physique n’existe pas (RG-14).'], 400);
