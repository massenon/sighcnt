<?php
/* =============================================================================
 * SIGH-CNT : extracteur LOCAL du texte d'un PDF (lot D4 du plan documents numérisés)
 * -----------------------------------------------------------------------------
 * ÉCRIT POUR LE PROJET, sans bibliothèque ni appel réseau : la règle de la clinique est que du texte médical ne sort jamais d'elle
 * (PRD documents, section 9). Il lit ce qu'un PDF PORTE comme couche texte et rien d'autre.
 *
 * CE QU'IL FAIT : repère les objets, décompresse les flux Flate, lit l'arbre des pages (ressources héritées comprises), suit les polices
 * de chaque page, décode les chaînes des opérateurs Tj, TJ, ' et " par la table ToUnicode de la police (polices Type0 à codes de deux
 * octets) ou par Windows-1252 (polices simples), et rend les MOTS distincts.
 *
 * CE QU'IL NE FAIT PAS, et qu'il dit : un scan est une IMAGE, il n'a pas de couche texte, donc rien à lire (la reconnaissance de
 * caractères est la phase 2 du PRD). Un PDF chiffré, une police sans table ToUnicode à codes multiples ou un flux illisible
 * donnent « texte non indexé » : jamais une liste vide présentée comme « le document ne contient aucun mot ».
 *
 * Retour : ['pages' => int|null, 'indexe' => bool, 'mots' => string[], 'raison' => ?string]
 * ========================================================================== */

/** Décompresse un flux Flate ; null si illisible. */
function sigh_pdf_inflate(string $d): ?string
{
    $r = @gzuncompress($d);
    if ($r === false) {
        $r = @gzinflate(substr($d, 2));
    }
    if ($r === false) {
        $r = @gzinflate($d);
    }
    return $r === false ? null : $r;
}

/** Un petit analyseur de valeurs PDF : dictionnaire, tableau, nom, chaîne, nombre, référence. */
function sigh_pdf_valeur(string $s, int &$i)
{
    $n = strlen($s);
    while ($i < $n && strpos(" \t\r\n\f\0", $s[$i]) !== false) {
        $i++;
    }
    if ($i >= $n) {
        return null;
    }
    $c = $s[$i];
    if ($c === '%') {
        while ($i < $n && $s[$i] !== "\n" && $s[$i] !== "\r") {
            $i++;
        }
        return sigh_pdf_valeur($s, $i);
    }
    if ($c === '<' && ($s[$i + 1] ?? '') === '<') {
        $i += 2;
        $d = [];
        while ($i < $n) {
            while ($i < $n && strpos(" \t\r\n\f\0", $s[$i]) !== false) {
                $i++;
            }
            if (substr($s, $i, 2) === '>>') {
                $i += 2;
                break;
            }
            $cle = sigh_pdf_valeur($s, $i);
            if (!is_array($cle) || !isset($cle['nom'])) {
                break;
            }
            $d[$cle['nom']] = sigh_pdf_valeur($s, $i);
        }
        return ['dict' => $d];
    }
    if ($c === '[') {
        $i++;
        $a = [];
        while ($i < $n) {
            while ($i < $n && strpos(" \t\r\n\f\0", $s[$i]) !== false) {
                $i++;
            }
            if (($s[$i] ?? '') === ']') {
                $i++;
                break;
            }
            $v = sigh_pdf_valeur($s, $i);
            if ($v === null && $i >= $n) {
                break;
            }
            $a[] = $v;
        }
        return ['tab' => $a];
    }
    if ($c === '/') {
        $j = $i + 1;
        while ($j < $n && strpos(" \t\r\n\f\0()<>[]{}/%", $s[$j]) === false) {
            $j++;
        }
        $nom = substr($s, $i + 1, $j - $i - 1);
        $i = $j;
        return ['nom' => $nom];
    }
    if ($c === '(') {
        $prof = 1;
        $j = $i + 1;
        $out = '';
        while ($j < $n && $prof > 0) {
            $ch = $s[$j];
            if ($ch === '\\') {
                $j++;
                $e = $s[$j] ?? '';
                if ($e === 'n') { $out .= "\n"; } elseif ($e === 'r') { $out .= "\r"; } elseif ($e === 't') { $out .= "\t"; }
                elseif ($e === 'b') { $out .= "\x08"; } elseif ($e === 'f') { $out .= "\x0c"; }
                elseif ($e >= '0' && $e <= '7') {
                    $o = $e;
                    for ($k = 0; $k < 2; $k++) {
                        $p = $s[$j + 1] ?? '';
                        if ($p >= '0' && $p <= '7') { $o .= $p; $j++; } else { break; }
                    }
                    $out .= chr(octdec($o) & 255);
                } elseif ($e === "\r" || $e === "\n") {
                    if ($e === "\r" && ($s[$j + 1] ?? '') === "\n") { $j++; }
                } else { $out .= $e; }
                $j++;
                continue;
            }
            if ($ch === '(') { $prof++; }
            if ($ch === ')') { $prof--; if ($prof === 0) { $j++; break; } }
            $out .= $ch;
            $j++;
        }
        $i = $j;
        return ['chaine' => $out];
    }
    if ($c === '<') {
        $j = strpos($s, '>', $i);
        if ($j === false) { $j = $n; }
        $hex = preg_replace('/[^0-9A-Fa-f]/', '', substr($s, $i + 1, $j - $i - 1));
        if (strlen($hex) % 2) { $hex .= '0'; }
        $i = $j + 1;
        return ['chaine' => (string) hex2bin($hex)];
    }
    if (preg_match('/\G(\d+)\s+(\d+)\s+R(?![A-Za-z])/', $s, $m, 0, $i)) {
        $i += strlen($m[0]);
        return ['ref' => (int) $m[1]];
    }
    if (preg_match('/\G[+-]?(?:\d+\.?\d*|\.\d+)/', $s, $m, 0, $i)) {
        $i += strlen($m[0]);
        return ['num' => (float) $m[0]];
    }
    if (preg_match('/\G[A-Za-z\'"*]+/', $s, $m, 0, $i)) {
        $i += strlen($m[0]);
        if ($m[0] === 'true') { return ['bool' => true]; }
        if ($m[0] === 'false') { return ['bool' => false]; }
        if ($m[0] === 'null') { return null; }
        return ['op' => $m[0]];
    }
    $i++;
    return null;
}

/** Tous les objets du fichier : numéro => ['dict' => ..., 'flux' => ?string brut], flux d'objets compris. */
function sigh_pdf_objets(string $pdf): array
{
    $objets = [];
    if (!preg_match_all('/(?<![0-9])(\d+)\s+(\d+)\s+obj\b/', $pdf, $mm, PREG_OFFSET_CAPTURE)) {
        return [];
    }
    foreach ($mm[0] as $k => $m0) {
        $num = (int) $mm[1][$k][0];
        $debut = $m0[1] + strlen($m0[0]);
        $i = $debut;
        $v = sigh_pdf_valeur($pdf, $i);
        $objet = ['val' => $v, 'flux' => null];
        $reste = substr($pdf, $i, 12);
        if (is_array($v) && isset($v['dict']) && preg_match('/^\s*stream\r?\n/', $reste, $ms)) {
            $d0 = $i + strlen($ms[0]);
            $fin = strpos($pdf, 'endstream', $d0);
            if ($fin !== false) {
                $flux = substr($pdf, $d0, $fin - $d0);
                $flux = preg_replace('/\r?\n$/', '', $flux);
                $objet['flux'] = $flux;
            }
        }
        $objets[$num] = $objet;
    }
    /* Flux d'objets (PDF 1.5) : leurs objets internes rejoignent la table. */
    foreach ($objets as $num => $o) {
        $d = $o['val']['dict'] ?? null;
        if (is_array($d) && ($d['Type']['nom'] ?? '') === 'ObjStm' && $o['flux'] !== null) {
            $dec = sigh_pdf_flux($o);
            if ($dec === null) { continue; }
            $nb = (int) ($d['N']['num'] ?? 0);
            $premier = (int) ($d['First']['num'] ?? 0);
            if (!preg_match_all('/(\d+)\s+(\d+)/', substr($dec, 0, $premier), $pp, PREG_SET_ORDER)) { continue; }
            $pp = array_slice($pp, 0, $nb);
            foreach ($pp as $idx => $p) {
                $deb = $premier + (int) $p[2];
                $suiv = isset($pp[$idx + 1]) ? $premier + (int) $pp[$idx + 1][2] : strlen($dec);
                $sub = substr($dec, $deb, $suiv - $deb);
                $j = 0;
                $objets[(int) $p[1]] = ['val' => sigh_pdf_valeur($sub, $j), 'flux' => null];
            }
        }
    }
    return $objets;
}

/** Le contenu décodé d'un objet à flux, ou null (filtre inconnu, flux illisible). */
function sigh_pdf_flux(array $o): ?string
{
    if ($o['flux'] === null) { return null; }
    $d = $o['val']['dict'] ?? [];
    $f = $d['Filter'] ?? null;
    $filtres = [];
    if (is_array($f) && isset($f['nom'])) { $filtres = [$f['nom']]; }
    elseif (is_array($f) && isset($f['tab'])) { foreach ($f['tab'] as $x) { $filtres[] = $x['nom'] ?? '?'; } }
    $data = $o['flux'];
    foreach ($filtres as $nom) {
        if ($nom === 'FlateDecode' || $nom === 'Fl') {
            $data = sigh_pdf_inflate($data);
            if ($data === null) { return null; }
        } else {
            return null;
        }
    }
    return $data;
}

/** Résout une valeur : suit une référence vers le dictionnaire ou la valeur de l'objet. */
function sigh_pdf_res(array $objets, $v)
{
    $garde = 0;
    while (is_array($v) && isset($v['ref']) && $garde++ < 20) {
        $v = $objets[$v['ref']]['val'] ?? null;
    }
    return $v;
}

/** Table ToUnicode : ['larg' => octets par code, 'carte' => code => texte UTF-8]. */
function sigh_pdf_tounicode(string $cmap): array
{
    $carte = [];
    $larg = 0;
    $u16 = function (string $hex): string {
        $b = (string) hex2bin(strlen($hex) % 2 ? $hex . '0' : $hex);
        return (string) mb_convert_encoding($b, 'UTF-8', 'UTF-16BE');
    };
    if (preg_match('/begincodespacerange(.*?)endcodespacerange/s', $cmap, $m) && preg_match('/<([0-9A-Fa-f]+)>/', $m[1], $c)) {
        $larg = (int) (strlen($c[1]) / 2);
    }
    if (preg_match_all('/beginbfchar(.*?)endbfchar/s', $cmap, $blocs)) {
        foreach ($blocs[1] as $b) {
            if (preg_match_all('/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>/', $b, $p, PREG_SET_ORDER)) {
                foreach ($p as $e) {
                    $carte[hexdec($e[1])] = $u16($e[2]);
                    $larg = $larg ?: (int) (strlen($e[1]) / 2);
                }
            }
        }
    }
    if (preg_match_all('/beginbfrange(.*?)endbfrange/s', $cmap, $blocs)) {
        foreach ($blocs[1] as $b) {
            if (preg_match_all('/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(\[[^\]]*\]|<[0-9A-Fa-f]*>)/', $b, $p, PREG_SET_ORDER)) {
                foreach ($p as $e) {
                    $lo = hexdec($e[1]); $hi = hexdec($e[2]);
                    $larg = $larg ?: (int) (strlen($e[1]) / 2);
                    if ($hi - $lo > 65535) { continue; }
                    if ($e[3][0] === '[') {
                        preg_match_all('/<([0-9A-Fa-f]*)>/', $e[3], $ds);
                        foreach ($ds[1] as $k => $h) { $carte[$lo + $k] = $u16($h); }
                    } else {
                        $base = trim($e[3], '<>');
                        $texte = $u16($base);
                        for ($c = $lo; $c <= $hi; $c++) {
                            if ($c === $lo) { $carte[$c] = $texte; continue; }
                            $chars = preg_split('//u', $texte, -1, PREG_SPLIT_NO_EMPTY);
                            if ($chars) {
                                $dernier = array_pop($chars);
                                $chars[] = mb_chr(mb_ord($dernier, 'UTF-8') + ($c - $lo), 'UTF-8');
                                $carte[$c] = implode('', $chars);
                            }
                        }
                    }
                }
            }
        }
    }
    return ['larg' => $larg ?: 2, 'carte' => $carte];
}

/** Décode une chaîne montrée avec une police : texte UTF-8. */
function sigh_pdf_decoder(string $chaine, ?array $police): string
{
    if ($police === null) {
        return (string) mb_convert_encoding($chaine, 'UTF-8', 'Windows-1252');
    }
    if ($police['tounicode'] !== null) {
        $larg = $police['tounicode']['larg'];
        $carte = $police['tounicode']['carte'];
        $out = '';
        $n = strlen($chaine);
        for ($i = 0; $i + $larg <= $n; $i += $larg) {
            $code = 0;
            for ($k = 0; $k < $larg; $k++) { $code = ($code << 8) | ord($chaine[$i + $k]); }
            if (isset($carte[$code])) { $out .= $carte[$code]; }
        }
        return $out;
    }
    if ($police['type0']) {
        return '';
    }
    return (string) mb_convert_encoding($chaine, 'UTF-8', 'Windows-1252');
}

/** Les mots (UTF-8, en minuscules) du texte montré par UN flux de contenu. */
function sigh_pdf_contenu(string $c, array $polices): string
{
    $i = 0;
    $n = strlen($c);
    $pile = [];
    $texte = '';
    $courante = null;
    $ops = ['Tf', 'Tj', 'TJ', "'", '"', 'T*', 'Td', 'TD', 'Tm', 'ET', 'BT'];
    $essais = 0;
    while ($i < $n && $essais++ < 2000000) {
        $debut = $i;
        $v = sigh_pdf_valeur($c, $i);
        if ($i <= $debut) { $i = $debut + 1; continue; }
        if (is_array($v) && isset($v['op'])) {
            $op = $v['op'];
            if ($op === 'Tf') {
                $nom = null;
                foreach ($pile as $x) { if (is_array($x) && isset($x['nom'])) { $nom = $x['nom']; } }
                $courante = $nom !== null ? ($polices[$nom] ?? null) : null;
            } elseif ($op === 'Tj' || $op === "'" || $op === '"') {
                $s = null;
                foreach ($pile as $x) { if (is_array($x) && isset($x['chaine'])) { $s = $x['chaine']; } }
                if ($s !== null) { $texte .= sigh_pdf_decoder($s, $courante) . ($op === 'Tj' ? '' : ' '); }
            } elseif ($op === 'TJ') {
                foreach ($pile as $x) {
                    if (is_array($x) && isset($x['tab'])) {
                        foreach ($x['tab'] as $e) {
                            if (isset($e['chaine'])) { $texte .= sigh_pdf_decoder($e['chaine'], $courante); }
                            elseif (isset($e['num']) && $e['num'] < -200) { $texte .= ' '; }
                        }
                    }
                }
            } elseif (in_array($op, ['T*', 'Td', 'TD', 'Tm', 'ET', 'BT'], true)) {
                $texte .= ' ';
            }
            $pile = [];
            continue;
        }
        $pile[] = $v;
        if (count($pile) > 64) { array_shift($pile); }
    }
    return $texte;
}

/** Extrait pages et mots d'un PDF. */
function sigh_pdf_texte(string $pdf): array
{
    $vide = ['pages' => null, 'indexe' => false, 'mots' => [], 'raison' => null];
    if (strncmp($pdf, '%PDF-', 5) !== 0) {
        $vide['raison'] = 'pas un PDF';
        return $vide;
    }
    $objets = sigh_pdf_objets($pdf);
    if (!$objets) {
        $vide['raison'] = 'structure du PDF illisible';
        return $vide;
    }
    $pages = [];
    foreach ($objets as $num => $o) {
        $d = $o['val']['dict'] ?? null;
        if (is_array($d) && ($d['Type']['nom'] ?? '') === 'Page') { $pages[$num] = $d; }
    }
    $res = ['pages' => $pages ? count($pages) : null, 'indexe' => false, 'mots' => [], 'raison' => null];
    if (preg_match('#/Encrypt\b#', substr($pdf, -4096)) || preg_match('#/Encrypt\s+\d+\s+\d+\s+R#', $pdf)) {
        $res['raison'] = 'PDF chiffré : texte non lisible';
        return $res;
    }
    $tout = '';
    $lu = false;
    foreach ($pages as $num => $d) {
        /* Ressources : celles de la page, sinon héritées de ses parents. */
        $ressources = null;
        $courant = $d;
        for ($g = 0; $g < 12 && is_array($courant); $g++) {
            if (isset($courant['Resources'])) { $ressources = sigh_pdf_res($objets, $courant['Resources']); break; }
            $parent = isset($courant['Parent']) ? sigh_pdf_res($objets, $courant['Parent']) : null;
            $courant = is_array($parent) ? ($parent['dict'] ?? null) : null;
        }
        $fontDict = [];
        if (is_array($ressources) && isset($ressources['dict']['Font'])) {
            $f = sigh_pdf_res($objets, $ressources['dict']['Font']);
            $fontDict = is_array($f) ? ($f['dict'] ?? []) : [];
        }
        $polices = [];
        foreach ($fontDict as $nom => $ref) {
            $fo = sigh_pdf_res($objets, $ref);
            $fd = is_array($fo) ? ($fo['dict'] ?? null) : null;
            if (!is_array($fd)) { continue; }
            $tu = null;
            if (isset($fd['ToUnicode']) && isset($fd['ToUnicode']['ref'])) {
                $o = $objets[$fd['ToUnicode']['ref']] ?? null;
                $cm = $o ? sigh_pdf_flux($o) : null;
                if ($cm !== null) { $tu = sigh_pdf_tounicode($cm); }
            }
            $polices[$nom] = ['tounicode' => $tu, 'type0' => (($fd['Subtype']['nom'] ?? '') === 'Type0')];
        }
        $contenus = [];
        if (isset($d['Contents'])) {
            $c = $d['Contents'];
            if (isset($c['ref'])) {
                $r = sigh_pdf_res($objets, $c);
                if (is_array($r) && isset($r['tab'])) { $c = $r; } else { $contenus[] = $c['ref']; $c = null; }
            }
            if (is_array($c) && isset($c['tab'])) { foreach ($c['tab'] as $x) { if (isset($x['ref'])) { $contenus[] = $x['ref']; } } }
        }
        foreach ($contenus as $ref) {
            $o = $objets[$ref] ?? null;
            $data = $o ? sigh_pdf_flux($o) : null;
            if ($data === null) { continue; }
            $lu = true;
            $tout .= ' ' . sigh_pdf_contenu($data, $polices);
        }
    }
    $tout = mb_strtolower($tout, 'UTF-8');
    preg_match_all('/[\p{L}\p{N}][\p{L}\p{N}\'’-]*/u', $tout, $mots);
    $uniques = [];
    foreach ($mots[0] as $m) {
        $m = trim($m, "'’-");
        if (mb_strlen($m, 'UTF-8') >= 2) { $uniques[$m] = true; }
    }
    $res['mots'] = array_keys($uniques);
    $res['indexe'] = count($res['mots']) > 0;
    if (!$res['indexe']) {
        $res['raison'] = $lu ? 'aucune couche texte lisible : scan image' : 'contenu des pages illisible';
    }
    return $res;
}
