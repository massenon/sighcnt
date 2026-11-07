<?php
/* =============================================================================
 * SIGH-CNT — Le planificateur du serveur
 * -----------------------------------------------------------------------------
 * Le serveur travaille SANS écran ouvert : ce fichier évalue des règles à
 * heure fixe et écrit des notifications que les postes liront à leur
 * ouverture, ou en continu par `api/notifications.php`.
 *
 * DEUX FAÇONS DE LE LANCER, la même fonction derrière :
 *   — le planificateur du système, toutes les 5 minutes (recommandé) :
 *       Linux    : 0-59/5 * * * *  php /chemin/prototype_html/api/cron.php
 *       Windows  : schtasks /create /sc minute /mo 5 /tn SIGH-CRON
 *                  /tr "php C:\chemin\prototype_html\api\cron.php"
 *   — à défaut, un « pseudo-cron » : `notifications.php` l'exécute lui-même
 *     quand aucune exécution n'a eu lieu depuis plus de 5 minutes. La clinique
 *     qui n'a pas encore installé de tâche système n'est donc pas privée de
 *     ses alertes — elle est seulement servie quand un poste est ouvert.
 *
 * CE QUE FONT LES TÂCHES, ET CE QU'ELLES NE FONT PAS :
 *   — une tâche LIT les collections du magasin ; elle n'en écrit aucune. Les
 *     postes réécrivent leurs collections entières (delta par collection) :
 *     une écriture serveur dans la même collection serait écrasée au geste
 *     suivant. Les notifications du serveur ont donc leur propre table.
 *   — une tâche ne décide d'aucun seuil : elle applique celui que la clinique
 *     a fixé (seuil d'alerte par article, statut de lot, échéance du
 *     calendrier fiscal). Le jour où un seuil change, rien ici ne change.
 *   — une alerte DISPARAÎT quand sa cause cesse : à chaque exécution, ce que
 *     la tâche ne produit plus est marqué résolu. Jamais supprimé (RG-14).
 *   — aucune donnée médicale dans un titre : le détail reste derrière les
 *     droits de l'écran vers lequel l'alerte renvoie.
 * ========================================================================== */

require_once __DIR__ . '/config.php';

/* --------------------------------------------------------------------------
 * LES TABLES — propres au planificateur
 * ------------------------------------------------------------------------ */
function sigh_cron_installer(PDO $pdo): void
{
    $pg = sigh_est_postgres();
    $horodate = $pg ? 'TIMESTAMP' : 'DATETIME';
    $pdo->exec('CREATE TABLE IF NOT EXISTS taches_planifiees (
        code            VARCHAR(48) PRIMARY KEY,
        libelle         VARCHAR(160) NOT NULL,
        frequence_min   INT NOT NULL DEFAULT 5,
        actif           ' . ($pg ? 'BOOLEAN NOT NULL DEFAULT TRUE' : 'TINYINT(1) NOT NULL DEFAULT 1') . ',
        derniere_le     ' . $horodate . ' NULL,
        dernier_statut  VARCHAR(16),
        dernier_message TEXT,
        duree_ms        INT,
        alertes         INT NOT NULL DEFAULT 0
    )');
    $pdo->exec('CREATE TABLE IF NOT EXISTS executions_taches (
        id         ' . ($pg ? 'BIGSERIAL' : 'BIGINT AUTO_INCREMENT') . ' PRIMARY KEY,
        code       VARCHAR(48) NOT NULL,
        debut      ' . $horodate . ' NOT NULL DEFAULT CURRENT_TIMESTAMP,
        statut     VARCHAR(16) NOT NULL,
        message    TEXT,
        duree_ms   INT,
        alertes    INT NOT NULL DEFAULT 0,
        origine    VARCHAR(24)
    )');
    $pdo->exec('CREATE TABLE IF NOT EXISTS notifications_serveur (
        id         ' . ($pg ? 'BIGSERIAL' : 'BIGINT AUTO_INCREMENT') . ' PRIMARY KEY,
        cle        VARCHAR(120) NOT NULL,
        tache      VARCHAR(48) NOT NULL,
        priorite   VARCHAR(16) NOT NULL,
        titre      VARCHAR(255) NOT NULL,
        detail     TEXT,
        lien       VARCHAR(64),
        postes     TEXT,
        cree_le    ' . $horodate . ' NOT NULL DEFAULT CURRENT_TIMESTAMP,
        resolue_le ' . $horodate . ' NULL
    )');
    try {
        $pdo->exec('CREATE UNIQUE INDEX uq_notifications_serveur_cle ON notifications_serveur (cle)');
    } catch (Throwable $e) { /* déjà posé */ }
}

/** Les collections du magasin, lues sans les modifier. */
function sigh_cron_collection(PDO $pdo, string $nom): array
{
    $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
    $q->execute([$nom]);
    $d = $q->fetchColumn();
    $o = $d ? json_decode($d, true) : [];
    if (!is_array($o)) {
        return [];
    }
    return array_values(array_filter($o, function ($f) {
        return is_array($f) && (($f['statut'] ?? '') !== 'archive') && empty($f['archive']);
    }));
}

function sigh_cron_jour(string $iso): ?int
{
    $t = strtotime(substr($iso, 0, 10));
    return $t === false ? null : (int) floor($t / 86400);
}

/* --------------------------------------------------------------------------
 * LES TÂCHES — chacune renvoie la liste COMPLÈTE de ce qui est vrai maintenant
 * ------------------------------------------------------------------------ */
function sigh_cron_taches(): array
{
    return [
        'echeances_fiscales' => [
            'libelle' => 'Échéances fiscales dépassées ou à moins de 7 jours',
            'frequence_min' => 60,
            'executer' => function (PDO $pdo, int $auj): array {
                $out = [];
                foreach (sigh_cron_collection($pdo, 'echeancesFiscales') as $e) {
                    if (!empty($e['paye'])) {
                        continue;
                    }
                    $j = sigh_cron_jour((string) ($e['echeance'] ?? ''));
                    if ($j === null) {
                        continue;
                    }
                    $ecart = $j - $auj;
                    if ($ecart > 7) {
                        continue;
                    }
                    $nom = (string) ($e['libelle'] ?? $e['obligation'] ?? 'Échéance fiscale');
                    $out[] = [
                        'cle' => 'echeance:' . ($e['id'] ?? $nom . $e['echeance']),
                        'priorite' => $ecart < 0 ? 'critique' : 'important',
                        'titre' => $ecart < 0 ? 'Échéance fiscale dépassée — ' . $nom : 'Échéance fiscale dans ' . $ecart . ' jour(s) — ' . $nom,
                        'detail' => 'Échéance du ' . substr((string) $e['echeance'], 0, 10) . '. Valider le règlement dans le suivi des échéances.',
                        'lien' => 'm12-echeances',
                        'postes' => ['comptable', 'aide_comptable', 'da', 'direction', 'dm', 'admin'],
                    ];
                }
                return $out;
            },
        ],
        'stock_seuils' => [
            'libelle' => 'Articles sous leur seuil d’alerte',
            'frequence_min' => 30,
            'executer' => function (PDO $pdo, int $auj): array {
                $out = [];
                foreach (sigh_cron_collection($pdo, 'produits') as $p) {
                    if (!isset($p['seuilAlerte']) || $p['seuilAlerte'] === null || !isset($p['stock'])) {
                        continue;
                    }
                    if ($p['stock'] > $p['seuilAlerte']) {
                        continue;
                    }
                    $out[] = [
                        'cle' => 'stock:' . $p['id'],
                        'priorite' => $p['stock'] <= 0 ? 'critique' : 'important',
                        'titre' => ($p['designation'] ?? 'Article') . ' — ' . $p['stock'] . ' en stock',
                        'detail' => 'Seuil d’alerte fixé à ' . $p['seuilAlerte'] . '. Établir un bon de commande — validation de la Direction requise (RG-04).',
                        'lien' => 'm6-alertes',
                        'postes' => ['stock', 'pharmacien', 'caissier', 'da'],
                    ];
                }
                return $out;
            },
        ],
        'lots_peremption' => [
            'libelle' => 'Lots périmés ou proches de la péremption (FEFO)',
            'frequence_min' => 60,
            'executer' => function (PDO $pdo, int $auj): array {
                $out = [];
                foreach (sigh_cron_collection($pdo, 'lots') as $l) {
                    $st = $l['statut'] ?? '';
                    if ($st !== 'perime' && $st !== 'alerte') {
                        continue;
                    }
                    $nom = (string) ($l['produit'] ?? $l['numero'] ?? 'Lot');
                    $out[] = [
                        'cle' => 'lot:' . $l['id'],
                        'priorite' => $st === 'perime' ? 'critique' : 'important',
                        'titre' => ($st === 'perime' ? 'Lot périmé — ' : 'Péremption proche — ') . $nom,
                        'detail' => $st === 'perime' ? 'À sortir du rayon et à déclarer en perte.' : 'Appliquer le principe FEFO (RG-05).',
                        'lien' => 'm6-lots',
                        'postes' => ['stock', 'pharmacien', 'caissier', 'laborantin'],
                    ];
                }
                return $out;
            },
        ],
        'rdv_lendemain' => [
            'libelle' => 'Rendez-vous du lendemain à rappeler',
            'frequence_min' => 120,
            'executer' => function (PDO $pdo, int $auj): array {
                $n = 0;
                foreach (sigh_cron_collection($pdo, 'consultations') as $r) {
                    if (($r['statut'] ?? '') !== 'planifiee') {
                        continue;
                    }
                    if (sigh_cron_jour((string) ($r['date'] ?? '')) === $auj + 1) {
                        $n++;
                    }
                }
                if ($n === 0) {
                    return [];
                }
                return [[
                    'cle' => 'rdv-demain:' . gmdate('Y-m-d', ($auj + 1) * 86400),
                    'priorite' => 'information',
                    'titre' => $n . ' rendez-vous prévu(s) demain',
                    'detail' => 'Rappeler les patients qui l’ont demandé. Le détail est à l’agenda.',
                    'lien' => 'm2-agenda',
                    'postes' => ['reception', 'medecin', 'infirmier', 'dm'],
                ]];
            },
        ],
        'creances_agees' => [
            'libelle' => 'Créances assureurs au-delà du seuil de recouvrement',
            'frequence_min' => 240,
            'executer' => function (PDO $pdo, int $auj): array {
                /* Même définition que le moteur du navigateur (alertesRecouvrement) :
                   le seuil est l'objectif « creance_agee » du pilotage, 60 jours à défaut. */
                $seuil = 60;
                foreach (sigh_cron_collection($pdo, 'objectifsPilotage') as $o) {
                    if (($o['code'] ?? $o['id'] ?? '') === 'creance_agee' && isset($o['cible'])) {
                        $seuil = (int) $o['cible'];
                    }
                }
                $par = [];
                foreach (sigh_cron_collection($pdo, 'factures') as $f) {
                    if (empty($f['assureur']) || !((float) ($f['partAssurance'] ?? 0) > 0) || empty($f['date'])) {
                        continue;
                    }
                    $j = sigh_cron_jour((string) $f['date']);
                    if ($j === null || $auj - $j <= $seuil) {
                        continue;
                    }
                    $k = (string) $f['assureur'];
                    $par[$k] = ($par[$k] ?? ['nb' => 0, 'montant' => 0.0]);
                    $par[$k]['nb']++;
                    $par[$k]['montant'] += (float) $f['partAssurance'];
                }
                $out = [];
                foreach ($par as $assureur => $e) {
                    $out[] = [
                        'cle' => 'creance-agee:' . $assureur,
                        'priorite' => 'important',
                        'titre' => $assureur . ' — ' . $e['nb'] . ' facture(s) de plus de ' . $seuil . ' jours',
                        'detail' => 'À recouvrer : ' . number_format($e['montant'], 0, ',', ' ') . ' FCFA. Relancer la compagnie.',
                        'lien' => 'm9-relances',
                        'postes' => ['da', 'comptable', 'direction', 'agentadmin'],
                    ];
                }
                return $out;
            },
        ],
        'sauvegarde_nocturne' => [
            'libelle' => 'Sauvegarde du magasin (copie compressée, 7 derniers jours)',
            'frequence_min' => 1440,
            'executer' => function (PDO $pdo, int $auj): array {
                $dossier = __DIR__ . '/sauvegardes';
                if (!is_dir($dossier) && !@mkdir($dossier, 0750, true)) {
                    throw new RuntimeException('dossier de sauvegarde non créé : ' . $dossier);
                }
                $tout = ['meta' => [], 'collections' => []];
                foreach ($pdo->query('SELECT cle, valeur FROM meta') as $l) {
                    $tout['meta'][$l['cle']] = json_decode($l['valeur'], true);
                }
                foreach ($pdo->query('SELECT nom, donnees FROM collections') as $l) {
                    $tout['collections'][$l['nom']] = json_decode($l['donnees'], true);
                }
                $fichier = $dossier . '/magasin-' . gmdate('Y-m-d', $auj * 86400) . '.json.gz';
                file_put_contents($fichier, gzencode(json_encode($tout, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 6));
                $anciens = glob($dossier . '/magasin-*.json.gz') ?: [];
                sort($anciens);
                foreach (array_slice($anciens, 0, max(0, count($anciens) - 7)) as $a) {
                    @unlink($a);
                }
                return [];
            },
        ],
    ];
}

/* --------------------------------------------------------------------------
 * L'EXÉCUTION
 * ------------------------------------------------------------------------ */
function sigh_cron_executer(PDO $pdo, string $origine = 'systeme', bool $force = false, ?string $seule = null): array
{
    sigh_cron_installer($pdo);
    $pg = sigh_est_postgres();
    $rapport = [];
    $auj = (int) floor(time() / 86400);
    foreach (sigh_cron_taches() as $code => $t) {
        if ($seule !== null && $seule !== $code) {
            continue;
        }
        $q = $pdo->prepare('SELECT * FROM taches_planifiees WHERE code = ?');
        $q->execute([$code]);
        $fiche = $q->fetch();
        if (!$fiche) {
            $pdo->prepare('INSERT INTO taches_planifiees (code, libelle, frequence_min) VALUES (?, ?, ?)')
                ->execute([$code, $t['libelle'], $t['frequence_min']]);
            $fiche = ['actif' => true, 'derniere_le' => null, 'frequence_min' => $t['frequence_min']];
        }
        if (!$pg ? !(int) $fiche['actif'] : !$fiche['actif']) {
            continue;
        }
        if (!$force && $fiche['derniere_le'] && time() - strtotime($fiche['derniere_le']) < $t['frequence_min'] * 60) {
            continue;
        }
        $debut = microtime(true);
        $statut = 'ok';
        $message = '';
        $alertes = [];
        try {
            $alertes = $t['executer']($pdo, $auj);
        } catch (Throwable $e) {
            $statut = 'erreur';
            $message = $e->getMessage();
        }
        if ($statut === 'ok' && $code !== 'sauvegarde_nocturne') {
            sigh_cron_rapprocher($pdo, $code, $alertes);
        }
        $duree = (int) round((microtime(true) - $debut) * 1000);
        $pdo->prepare('UPDATE taches_planifiees SET derniere_le = CURRENT_TIMESTAMP, dernier_statut = ?, dernier_message = ?, duree_ms = ?, alertes = ? WHERE code = ?')
            ->execute([$statut, $message, $duree, count($alertes), $code]);
        $pdo->prepare('INSERT INTO executions_taches (code, statut, message, duree_ms, alertes, origine) VALUES (?, ?, ?, ?, ?, ?)')
            ->execute([$code, $statut, $message, $duree, count($alertes), $origine]);
        /* Le journal des exécutions est borné : un historique sans limite
           finit par peser plus que les alertes qu'il retrace. */
        $pdo->exec('DELETE FROM executions_taches WHERE id NOT IN (SELECT id FROM (SELECT id FROM executions_taches ORDER BY id DESC LIMIT 500) x)');
        $rapport[$code] = ['statut' => $statut, 'alertes' => count($alertes), 'duree_ms' => $duree, 'message' => $message];
    }
    return $rapport;
}

/** Ce que la tâche produit maintenant devient ouvert ; ce qu'elle ne produit plus est résolu. */
function sigh_cron_rapprocher(PDO $pdo, string $tache, array $alertes): void
{
    $pdo->beginTransaction();
    try {
        $cles = [];
        foreach ($alertes as $a) {
            $cles[] = $a['cle'];
            $q = $pdo->prepare('SELECT id FROM notifications_serveur WHERE cle = ?');
            $q->execute([$a['cle']]);
            $id = $q->fetchColumn();
            $postes = json_encode($a['postes'] ?? [], JSON_UNESCAPED_UNICODE);
            if ($id) {
                /* Une alerte résolue qui revient redevient ouverte, avec sa date de naissance neuve. */
                $pdo->prepare('UPDATE notifications_serveur SET priorite = ?, titre = ?, detail = ?, lien = ?, postes = ?,
                    cree_le = CASE WHEN resolue_le IS NULL THEN cree_le ELSE CURRENT_TIMESTAMP END, resolue_le = NULL WHERE id = ?')
                    ->execute([$a['priorite'], $a['titre'], $a['detail'] ?? '', $a['lien'] ?? '', $postes, $id]);
            } else {
                $pdo->prepare('INSERT INTO notifications_serveur (cle, tache, priorite, titre, detail, lien, postes) VALUES (?, ?, ?, ?, ?, ?, ?)')
                    ->execute([$a['cle'], $tache, $a['priorite'], $a['titre'], $a['detail'] ?? '', $a['lien'] ?? '', $postes]);
            }
        }
        $ouvertes = $pdo->prepare('SELECT id, cle FROM notifications_serveur WHERE tache = ? AND resolue_le IS NULL');
        $ouvertes->execute([$tache]);
        foreach ($ouvertes->fetchAll() as $o) {
            if (!in_array($o['cle'], $cles, true)) {
                $pdo->prepare('UPDATE notifications_serveur SET resolue_le = CURRENT_TIMESTAMP WHERE id = ?')->execute([$o['id']]);
            }
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
}

/* Lancé en ligne de commande : le planificateur du système. */
if (PHP_SAPI === 'cli' && realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    try {
        $pdo = sigh_pdo();
        sigh_installer($pdo);
        $force = in_array('--force', $argv ?? [], true);
        $rapport = sigh_cron_executer($pdo, 'systeme', $force);
        foreach ($rapport as $code => $r) {
            fwrite(STDOUT, sprintf("%-22s %-7s %3d alerte(s) %5d ms %s\n", $code, $r['statut'], $r['alertes'], $r['duree_ms'], $r['message']));
        }
        if (!$rapport) {
            fwrite(STDOUT, "Aucune tâche à exécuter.\n");
        }
        exit(0);
    } catch (Throwable $e) {
        fwrite(STDERR, 'Planificateur : ' . $e->getMessage() . "\n");
        exit(1);
    }
}
