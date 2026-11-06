<?php

/**
 * PUITS SMTP DE TEST (sans dépendance) : un serveur SMTP minimal qui reçoit VRAIMENT les messages sur un port local et les range, un par fichier JSON, dans un
 * dossier. Il parle le protocole (EHLO, STARTTLS, AUTH PLAIN et LOGIN, MAIL FROM, RCPT TO, DATA, RSET, NOOP, QUIT) : ce que les tests du relais exercent est donc le
 * transport SMTP réel de Symfony, pas une simulation.
 *
 * Usage : php puits_smtp.php --port=2525 --dossier=/tmp/boite [--user=u --pass=p] [--tls=aucun|starttls|ssl] [--cert=/chemin/cert.pem]
 *   --tls=starttls|ssl exige --cert (certificat ET clé dans le même fichier PEM, auto-signé).
 *   Un destinataire contenant « inconnu » est refusé (550) ; un expéditeur contenant « refuse » est refusé (553).
 * Annonce « PRET <port> » sur la sortie standard quand il écoute.
 */
$o = [];
foreach (array_slice($argv, 1) as $a) {
    if (preg_match('/^--([a-z]+)=(.*)$/', $a, $m)) {
        $o[$m[1]] = $m[2];
    }
}
$port = (int) ($o['port'] ?? 0);
$dossier = $o['dossier'] ?? sys_get_temp_dir().'/puits-smtp';
$user = $o['user'] ?? null;
$pass = $o['pass'] ?? null;
$tls = $o['tls'] ?? 'aucun';
$cert = $o['cert'] ?? null;
@mkdir($dossier, 0777, true);

$ctx = stream_context_create();
$adresse = 'tcp://127.0.0.1:'.$port;
if ($tls !== 'aucun') {
    stream_context_set_option($ctx, 'ssl', 'local_cert', $cert);
    stream_context_set_option($ctx, 'ssl', 'verify_peer', false);
}
if ($tls === 'ssl') {
    $adresse = 'ssl://127.0.0.1:'.$port;
}
$serveur = stream_socket_server($adresse, $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $ctx);
if (! $serveur) {
    fwrite(STDERR, "écoute impossible : $errstr\n");
    exit(1);
}
$port = (int) substr(strrchr(stream_socket_get_name($serveur, false), ':'), 1);
echo "PRET $port\n";
flush();

function repondre($c, string $ligne): void
{
    fwrite($c, $ligne."\r\n");
}

function lire($c): ?string
{
    $l = fgets($c, 65536);

    return $l === false ? null : rtrim($l, "\r\n");
}

while (true) {
    $c = @stream_socket_accept($serveur, 3600);
    if (! $c) {
        continue;
    }
    stream_set_timeout($c, 10);
    $chiffre = $tls === 'ssl';
    $auth = $user === null;
    $de = null;
    $a = [];
    repondre($c, '220 puits.test ESMTP');
    while (($l = lire($c)) !== null) {
        $cmd = strtoupper(substr($l, 0, 4));
        if ($cmd === 'EHLO' || $cmd === 'HELO') {
            repondre($c, '250-puits.test');
            if ($tls === 'starttls' && ! $chiffre) {
                repondre($c, '250-STARTTLS');
            }
            repondre($c, '250-AUTH PLAIN LOGIN');
            repondre($c, '250 8BITMIME');
        } elseif ($cmd === 'STAR' && $tls === 'starttls') {
            repondre($c, '220 Go ahead');
            $ok = stream_socket_enable_crypto($c, true, STREAM_CRYPTO_METHOD_TLS_SERVER);
            if (! $ok) {
                break;
            }
            $chiffre = true;
        } elseif ($cmd === 'AUTH') {
            $p = preg_split('/\s+/', $l);
            $methode = strtoupper($p[1] ?? '');
            $u = $m = null;
            if ($methode === 'PLAIN') {
                $b = $p[2] ?? null;
                if ($b === null) {
                    repondre($c, '334 ');
                    $b = lire($c);
                }
                $x = explode("\0", (string) base64_decode((string) $b));
                $u = $x[1] ?? null;
                $m = $x[2] ?? null;
            } elseif ($methode === 'LOGIN') {
                repondre($c, '334 '.base64_encode('Username:'));
                $u = base64_decode((string) lire($c));
                repondre($c, '334 '.base64_encode('Password:'));
                $m = base64_decode((string) lire($c));
            }
            if ($user !== null && $u === $user && $m === $pass) {
                $auth = true;
                repondre($c, '235 2.7.0 Authentication successful');
            } else {
                repondre($c, '535 5.7.8 Authentication credentials invalid');
            }
        } elseif ($cmd === 'MAIL') {
            if (! $auth) {
                repondre($c, '530 5.7.0 Authentication required');
            } elseif (stripos($l, 'refuse') !== false) {
                repondre($c, '553 5.1.8 Sender address rejected');
            } else {
                $de = $l;
                $a = [];
                repondre($c, '250 OK');
            }
        } elseif ($cmd === 'RCPT') {
            if (stripos($l, 'inconnu') !== false) {
                repondre($c, '550 5.1.1 Mailbox unavailable');
            } else {
                $a[] = $l;
                repondre($c, '250 OK');
            }
        } elseif ($cmd === 'DATA') {
            repondre($c, '354 Go');
            $data = '';
            while (($d = lire($c)) !== null && $d !== '.') {
                $data .= (str_starts_with($d, '..') ? substr($d, 1) : $d)."\r\n";
            }
            $n = count(glob($dossier.'/*.json')) + 1;
            file_put_contents(sprintf('%s/%04d.json', $dossier, $n), json_encode(['de' => $de, 'a' => $a, 'chiffre' => $chiffre, 'data' => $data], JSON_UNESCAPED_UNICODE));
            repondre($c, '250 2.0.0 Queued');
        } elseif ($cmd === 'RSET' || $cmd === 'NOOP') {
            repondre($c, '250 OK');
        } elseif ($cmd === 'QUIT') {
            repondre($c, '221 Bye');
            break;
        } else {
            repondre($c, '502 Commande inconnue');
        }
    }
    @fclose($c);
}
