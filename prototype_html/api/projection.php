<?php
/* =============================================================================
 * SIGH-CNT — Projection du magasin en TABLES relationnelles (PostgreSQL)
 * -----------------------------------------------------------------------------
 * Le magasin (table `collections`, une ligne JSON par collection) reste
 * l'AUTORITÉ DU PROTOTYPE : c'est lui que lisent les écrans, de façon
 * synchrone. Ce fichier en tient une COPIE RELATIONNELLE à jour — une table par
 * collection, rangée dans le schéma de son module (`m1.patients`,
 * `m8.factures`…), des tables filles pour les lignes, des clés étrangères là où
 * les données les respectent. Ce que cela apporte : requêter, rapprocher,
 * exporter et sauvegarder les données SANS passer par du JSON, et préparer le
 * schéma que le projet cible reprendra tel quel (packages/schema/postgres).
 *
 * TROIS GARANTIES, DANS L'ORDRE DE LEUR IMPORTANCE :
 *   1. La projection ne fait JAMAIS échouer une écriture. Elle s'exécute dans un
 *      SAVEPOINT : si elle échoue, on revient au savepoint, l'erreur est notée
 *      dans `projection_erreurs`, et le magasin a bien reçu son delta.
 *   2. Rien n'est perdu : un champ que le schéma ne connaît pas, ou dont le type
 *      a changé, tombe dans la colonne `extra` (jsonb) au lieu d'être refusé.
 *   3. Une collection inconnue du schéma est NOMMÉE dans le journal d'erreurs :
 *      relancer `node build/gen-schema-pg.js` la prend en compte.
 * ========================================================================== */

function sigh_proj_manifeste(): ?array
{
    static $m = false;
    if ($m === false) {
        $f = __DIR__ . '/schema/manifeste.json';
        $m = is_file($f) ? json_decode((string) file_get_contents($f), true) : null;
    }
    return $m;
}

/** Crée les tables au premier usage ; le script est rejouable. */
function sigh_proj_installer(PDO $pdo): bool
{
    static $fait = null;
    if ($fait !== null) {
        return $fait;
    }
    $fait = false;
    if (!sigh_est_postgres() || sigh_proj_manifeste() === null) {
        return false;
    }
    $pdo->exec('CREATE TABLE IF NOT EXISTS projection_erreurs (
        id BIGSERIAL PRIMARY KEY, collection TEXT, message TEXT, le TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)');
    $pdo->exec('CREATE TABLE IF NOT EXISTS projection_etat (
        collection VARCHAR(64) PRIMARY KEY, lignes INT NOT NULL DEFAULT 0, ecartees INT NOT NULL DEFAULT 0,
        dans_extra INT NOT NULL DEFAULT 0, maj TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)');
    /* Première version de la copie : des clés étrangères entre collections, retirées (voir 0002_cles_etrangeres.sql). */
    $heritees = $pdo->query("SELECT n.nspname, c.relname, k.conname FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace WHERE k.contype = 'f' AND k.conname LIKE 'fk\\_%'")->fetchAll(PDO::FETCH_NUM);
    foreach ($heritees as $h) {
        $pdo->exec('ALTER TABLE "' . $h[0] . '"."' . $h[1] . '" DROP CONSTRAINT "' . $h[2] . '"');
    }
    $existe = $pdo->query("SELECT to_regclass('m1.patients')")->fetchColumn();
    if (!$existe) {
        $pdo->exec((string) file_get_contents(__DIR__ . '/schema/schema.sql'));
    }
    $fait = true;
    return true;
}

/** Une valeur du magasin → la valeur attendue par la colonne, ou null + [false] si le type ne convient pas. */
function sigh_proj_valeur($v, string $typ, bool &$ok)
{
    $ok = true;
    if ($v === null) {
        return null;
    }
    switch ($typ) {
        case 'boolean':
            if (is_bool($v)) {
                return $v ? 'true' : 'false';
            }
            break;
        case 'integer':
        case 'bigint':
            if (is_int($v)) {
                return $v;
            }
            if (is_float($v) && floor($v) == $v) {
                return (int) $v;
            }
            break;
        case 'numeric':
            if (is_int($v) || is_float($v)) {
                return is_float($v) ? rtrim(rtrim(number_format($v, 8, '.', ''), '0'), '.') : $v;
            }
            break;
        case 'date':
            if (is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}/', $v)) {
                return substr($v, 0, 10);
            }
            break;
        case 'timestamp':
        case 'timestamptz':
            if (is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}.*)?$/', $v)) {
                return $v;
            }
            break;
        case 'text':
            if (is_string($v)) {
                return $v;
            }
            if (is_int($v) || is_float($v)) {
                return (string) $v;
            }
            break;
        case 'jsonb':
            return json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
    $ok = false;
    return null;
}

/** Insère par lots ; un paramètre par cellule, 60 000 au plus par instruction. */
function sigh_proj_inserer(PDO $pdo, string $table, array $cols, array $lignes): void
{
    if (!$lignes) {
        return;
    }
    $n = count($cols);
    $par = max(1, intdiv(60000, $n));
    $nomsCols = implode(',', array_map(function ($c) { return '"' . $c . '"'; }, $cols));
    foreach (array_chunk($lignes, $par) as $lot) {
        $un = '(' . implode(',', array_fill(0, $n, '?')) . ')';
        $sql = 'INSERT INTO ' . $table . ' (' . $nomsCols . ') VALUES ' . implode(',', array_fill(0, count($lot), $un));
        $st = $pdo->prepare($sql);
        $i = 1;
        foreach ($lot as $ligne) {
            foreach ($ligne as $v) {
                if ($v === null) {
                    $st->bindValue($i++, null, PDO::PARAM_NULL);
                } elseif (is_int($v)) {
                    $st->bindValue($i++, $v, PDO::PARAM_INT);
                } else {
                    $st->bindValue($i++, (string) $v, PDO::PARAM_STR);
                }
            }
        }
        $st->execute();
    }
}

/** Projette UNE collection : remplace le contenu de sa table et de ses tables filles. */
function sigh_proj_collection(PDO $pdo, string $nom, array $fiches, array $t, ?array $ciblage = null): array
{
    $tab = '"' . $t['schema'] . '"."' . $t['table'] . '"';
    $connus = [];
    foreach ($t['colonnes'] as $c) {
        $connus[$c['champ']] = true;
    }
    $filles = [];
    foreach ($t['enfants'] as $e) {
        $connus[$e['champ']] = true;
        $filles[$e['champ']] = $e;
    }
    $colsSql = array_map(function ($c) { return $c['col']; }, $t['colonnes']);
    $colsSql[] = 'extra';
    if (!$t['aId']) {
        array_unshift($colsSql, '_rang');
    }
    $lignes = [];
    $enfLignes = [];
    foreach ($filles as $champ => $e) {
        $enfLignes[$champ] = [];
    }
    $ok = true;
    $vus = [];
    $ecartees = 0;
    $dansExtra = 0;
    $rang = 0;
    foreach ($fiches as $fiche) {
        if (!is_array($fiche) || (array_keys($fiche) === range(0, count($fiche) - 1) && $fiche)) {
            $ecartees++;
            continue;
        }
        $extra = [];
        $ligne = [];
        if ($t['aId']) {
            if (!isset($fiche['id']) || isset($vus[(string) $fiche['id']])) {
                $ecartees++;
                continue;
            }
            $vus[(string) $fiche['id']] = true;
        } else {
            $ligne[] = ++$rang;
        }
        foreach ($t['colonnes'] as $c) {
            $v = array_key_exists($c['champ'], $fiche) ? $fiche[$c['champ']] : null;
            $v = ($c['champ'] === 'id' && $t['aId'] && $v !== null) ? (string) $v : $v;
            $conv = sigh_proj_valeur($v, $c['typ'], $ok);
            if (!$ok) {
                $extra[$c['champ']] = $v;
                $conv = null;
            }
            $ligne[] = $conv;
        }
        foreach ($fiche as $k => $v) {
            if (!isset($connus[$k])) {
                $extra[$k] = $v;
            }
        }
        foreach ($filles as $champ => $e) {
            if (!isset($fiche[$champ]) || !is_array($fiche[$champ])) {
                continue;
            }
            $r = 0;
            foreach ($fiche[$champ] as $obj) {
                $r++;
                $lf = [$t['aId'] ? (string) $fiche['id'] : (string) $rang, $r];
                $ex = [];
                $connusF = [];
                foreach ($e['colonnes'] as $cf) {
                    $connusF[$cf['champ']] = true;
                    $val = is_array($obj) && array_key_exists($cf['champ'], $obj) ? $obj[$cf['champ']] : null;
                    $conv = sigh_proj_valeur($val, $cf['typ'], $ok);
                    if (!$ok) {
                        $ex[$cf['champ']] = $val;
                        $conv = null;
                    }
                    $lf[] = $conv;
                }
                if (is_array($obj)) {
                    foreach ($obj as $k => $v) {
                        if (!isset($connusF[$k])) {
                            $ex[$k] = $v;
                        }
                    }
                }
                $lf[] = $ex ? json_encode($ex, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null;
                $enfLignes[$champ][] = $lf;
            }
        }
        $dansExtra += $extra ? 1 : 0;
        $ligne[] = $extra ? json_encode($extra, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null;
        $lignes[] = $ligne;
    }
    if ($ciblage !== null && $t['aId']) {
        /* Une seule fiche a changé : on ne réécrit pas toute la collection. */
        $in = implode(',', array_fill(0, count($ciblage), '?'));
        if ($ciblage) {
            foreach ($filles as $e) {
                $pdo->prepare('DELETE FROM "' . $t['schema'] . '"."' . $e['table'] . '" WHERE "parent_id" IN (' . $in . ')')->execute(array_map('strval', $ciblage));
            }
            $pdo->prepare('DELETE FROM ' . $tab . ' WHERE "id" IN (' . $in . ')')->execute(array_map('strval', $ciblage));
        }
    } else {
        foreach ($filles as $e) {
            $pdo->exec('DELETE FROM "' . $t['schema'] . '"."' . $e['table'] . '"');
        }
        $pdo->exec('DELETE FROM ' . $tab);
    }
    sigh_proj_inserer($pdo, $tab, $colsSql, $lignes);
    foreach ($filles as $champ => $e) {
        $cf = ['parent_id', 'rang'];
        foreach ($e['colonnes'] as $c) {
            $cf[] = $c['col'];
        }
        $cf[] = 'extra';
        sigh_proj_inserer($pdo, '"' . $t['schema'] . '"."' . $e['table'] . '"', $cf, $enfLignes[$champ]);
    }
    return ['lignes' => count($lignes), 'ecartees' => $ecartees, 'dans_extra' => $dansExtra];
}

/**
 * Projette les collections d'un delta. N'ÉCHOUE JAMAIS vers l'appelant : le
 * magasin a déjà reçu son écriture, la copie relationnelle se rattrape.
 */
function sigh_proj_projeter(PDO $pdo, array $collections): array
{
    $bilan = ['ok' => 0, 'inconnues' => [], 'erreur' => null];
    try {
        if (!sigh_proj_installer($pdo)) {
            return $bilan;
        }
        $m = sigh_proj_manifeste();
        $pdo->exec('SAVEPOINT projection');
        try {
            $pdo->exec('SET CONSTRAINTS ALL DEFERRED');
            foreach ($collections as $nom => $fiches) {
                if (!is_array($fiches)) {
                    continue;
                }
                if (in_array($nom, $m['ignorees'] ?? [], true)) {
                    continue;
                }
                if (!isset($m['tables'][$nom])) {
                    $bilan['inconnues'][] = $nom;
                    continue;
                }
                $r = sigh_proj_collection($pdo, $nom, $fiches, $m['tables'][$nom]);
                $pdo->prepare('INSERT INTO projection_etat (collection, lignes, ecartees, dans_extra) VALUES (?,?,?,?)
                    ON CONFLICT (collection) DO UPDATE SET lignes = EXCLUDED.lignes, ecartees = EXCLUDED.ecartees,
                    dans_extra = EXCLUDED.dans_extra, maj = CURRENT_TIMESTAMP')
                    ->execute([$nom, $r['lignes'], $r['ecartees'], $r['dans_extra']]);
                $bilan['ok']++;
            }
            /* Les clés étrangères sont vérifiées ICI, dans le savepoint : une violation se rattrape,
               alors qu'au COMMIT elle ferait échouer aussi l'écriture du magasin. */
            $pdo->exec('SET CONSTRAINTS ALL IMMEDIATE');
            $pdo->exec('RELEASE SAVEPOINT projection');
        } catch (Throwable $e) {
            $pdo->exec('ROLLBACK TO SAVEPOINT projection');
            $bilan['erreur'] = $e->getMessage();
            $pdo->prepare('INSERT INTO projection_erreurs (collection, message) VALUES (?, ?)')
                ->execute([implode(',', array_keys($collections)), mb_substr($e->getMessage(), 0, 900)]);
        }
        foreach ($bilan['inconnues'] as $inc) {
            $pdo->prepare('INSERT INTO projection_erreurs (collection, message) VALUES (?, ?)')
                ->execute([$inc, 'Collection absente du schéma relationnel : relancer node build/gen-schema-pg.js']);
        }
        $pdo->exec('DELETE FROM projection_erreurs WHERE id NOT IN (SELECT id FROM (SELECT id FROM projection_erreurs ORDER BY id DESC LIMIT 200) x)');
    } catch (Throwable $e) {
        $bilan['erreur'] = $e->getMessage();
    }
    return $bilan;
}

/**
 * Projette ce que la BASE contient, pour les écritures par fiche (api/crud.php) :
 * une fiche si on la désigne, la collection entière sinon. N'échoue jamais.
 */
function sigh_proj_depuis_base(PDO $pdo, string $nom, ?string $id = null): void
{
    try {
        if (!sigh_proj_installer($pdo)) {
            return;
        }
        $m = sigh_proj_manifeste();
        if (in_array($nom, $m['ignorees'] ?? [], true) || !isset($m['tables'][$nom])) {
            if (!isset($m['tables'][$nom]) && !in_array($nom, $m['ignorees'] ?? [], true)) {
                $pdo->prepare('INSERT INTO projection_erreurs (collection, message) VALUES (?, ?)')
                    ->execute([$nom, 'Collection absente du schéma relationnel : relancer node build/gen-schema-pg.js']);
            }
            return;
        }
        $t = $m['tables'][$nom];
        $pdo->exec('SAVEPOINT projection_fiche');
        try {
            $pdo->exec('SET CONSTRAINTS ALL DEFERRED');
            if ($id !== null && $t['aId']) {
                $f = sigh_lire_fiche($pdo, $nom, $id);
                sigh_proj_collection($pdo, $nom, $f === null ? [] : [$f], $t, [$id]);
            } else {
                $q = $pdo->prepare('SELECT donnees FROM collections WHERE nom = ?');
                $q->execute([$nom]);
                sigh_proj_collection($pdo, $nom, json_decode((string) $q->fetchColumn(), true) ?: [], $t);
            }
            $pdo->exec('SET CONSTRAINTS ALL IMMEDIATE');
            $pdo->exec('RELEASE SAVEPOINT projection_fiche');
        } catch (Throwable $e) {
            $pdo->exec('ROLLBACK TO SAVEPOINT projection_fiche');
            $pdo->prepare('INSERT INTO projection_erreurs (collection, message) VALUES (?, ?)')
                ->execute([$nom, mb_substr($e->getMessage(), 0, 900)]);
        }
    } catch (Throwable $e) {
        /* la copie se rattrapera à la prochaine écriture de la collection */
    }
}

/** Remise à zéro du magasin : les tables suivent. */
function sigh_proj_vider(PDO $pdo): void
{
    try {
        if (!sigh_proj_installer($pdo)) {
            return;
        }
        foreach (sigh_proj_manifeste()['tables'] as $t) {
            foreach ($t['enfants'] as $e) {
                $pdo->exec('DELETE FROM "' . $t['schema'] . '"."' . $e['table'] . '"');
            }
        }
        $pdo->exec('SET CONSTRAINTS ALL DEFERRED');
        foreach (sigh_proj_manifeste()['tables'] as $t) {
            $pdo->exec('DELETE FROM "' . $t['schema'] . '"."' . $t['table'] . '"');
        }
        $pdo->exec('SET CONSTRAINTS ALL IMMEDIATE');
        $pdo->exec('DELETE FROM projection_etat');
    } catch (Throwable $e) {
        /* la copie se reconstruira à la prochaine écriture */
    }
}

/** Parité magasin ↔ tables : le contrôle que le banc et l'exploitation lancent. */
function sigh_proj_verifier(PDO $pdo): array
{
    sigh_proj_installer($pdo);
    $m = sigh_proj_manifeste();
    $ecarts = [];
    $total = ['collections' => 0, 'fiches' => 0];
    foreach ($pdo->query('SELECT nom, donnees FROM collections ORDER BY nom') as $l) {
        $nom = $l['nom'];
        $fiches = json_decode($l['donnees'], true);
        if (!is_array($fiches)) {
            continue;
        }
        if (in_array($nom, $m['ignorees'] ?? [], true)) {
            continue;
        }
        if (!isset($m['tables'][$nom])) {
            $ecarts[] = $nom . ' : absente du schéma';
            continue;
        }
        $t = $m['tables'][$nom];
        $attendu = 0;
        $vus = [];
        foreach ($fiches as $f) {
            if (is_array($f) && !($f && array_keys($f) === range(0, count($f) - 1))) {
                if ($t['aId']) {
                    if (isset($f['id']) && !isset($vus[(string) $f['id']])) {
                        $vus[(string) $f['id']] = true;
                        $attendu++;
                    }
                } else {
                    $attendu++;
                }
            }
        }
        $reel = (int) $pdo->query('SELECT count(*) FROM "' . $t['schema'] . '"."' . $t['table'] . '"')->fetchColumn();
        $total['collections']++;
        $total['fiches'] += $reel;
        if ($reel !== $attendu) {
            $ecarts[] = $nom . ' : magasin ' . $attendu . ' fiche(s), table ' . $reel;
        }
        foreach ($t['enfants'] as $e) {
            $att = 0;
            foreach ($fiches as $f) {
                if (is_array($f) && isset($f[$e['champ']]) && is_array($f[$e['champ']]) && (!$t['aId'] || isset($f['id']))) {
                    $att += count($f[$e['champ']]);
                }
            }
            $r = (int) $pdo->query('SELECT count(*) FROM "' . $t['schema'] . '"."' . $e['table'] . '"')->fetchColumn();
            if ($r !== $att && $t['aId']) {
                $ecarts[] = $nom . '.' . $e['champ'] . ' : magasin ' . $att . ' ligne(s), table ' . $r;
            }
        }
    }
    return ['ecarts' => $ecarts] + $total;
}

/* Lancé en ligne de commande : reconstruit TOUTES les tables depuis le magasin. */
if (PHP_SAPI === 'cli' && realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    require_once __DIR__ . '/config.php';
    $pdo = sigh_pdo();
    sigh_installer($pdo);
    if (!in_array('--verifier', $argv ?? [], true)) {
        $tout = [];
        foreach ($pdo->query('SELECT nom, donnees FROM collections') as $l) {
            $tout[$l['nom']] = json_decode($l['donnees'], true);
        }
        $pdo->beginTransaction();
        $b = sigh_proj_projeter($pdo, $tout);
        $pdo->commit();
        fwrite(STDOUT, 'Projection : ' . $b['ok'] . " collection(s)" . ($b['inconnues'] ? ', inconnues : ' . implode(',', $b['inconnues']) : '')
            . ($b['erreur'] ? "\nERREUR : " . $b['erreur'] : '') . "\n");
    }
    $v = sigh_proj_verifier($pdo);
    fwrite(STDOUT, 'Parité : ' . $v['collections'] . ' collection(s), ' . $v['fiches'] . ' fiche(s), ' . count($v['ecarts']) . " écart(s)\n");
    foreach ($v['ecarts'] as $e) {
        fwrite(STDOUT, '  - ' . $e . "\n");
    }
    exit($v['ecarts'] ? 1 : 0);
}
