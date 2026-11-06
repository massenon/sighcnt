<?php

namespace Tests\Concerns;

use App\Relais\ReglagesSmtp;

/**
 * Lance le PUITS SMTP de test (tests/outils/puits_smtp.php) dans un vrai processus : les courriels du relais traversent le transport SMTP réel et arrivent dans un
 * dossier que le test relit. Aucune simulation du transport.
 */
trait AvecPuitsSmtp
{
    /** @var resource|null */
    private $puitsProcessus = null;

    private string $puitsDossier = '';

    private int $puitsPort = 0;

    private ?string $puitsCert = null;

    /** @param array<string,string> $options user, pass, tls */
    protected function demarrerPuits(array $options = []): void
    {
        $this->puitsDossier = sys_get_temp_dir().'/puits-'.bin2hex(random_bytes(6));
        mkdir($this->puitsDossier, 0777, true);
        $args = ['--port=0', '--dossier='.$this->puitsDossier];
        if (($options['tls'] ?? 'aucun') !== 'aucun') {
            $this->puitsCert = $this->puitsDossier.'/cert.pem';
            $cmd = sprintf('openssl req -x509 -newkey rsa:2048 -nodes -keyout %1$s -out %1$s.crt -days 1 -subj /CN=127.0.0.1 2>/dev/null && cat %1$s.crt >> %1$s && mv %1$s %2$s', escapeshellarg($this->puitsDossier.'/k.pem'), escapeshellarg($this->puitsCert));
            exec($cmd);
            $args[] = '--cert='.$this->puitsCert;
        }
        foreach ($options as $k => $v) {
            $args[] = "--$k=$v";
        }
        $cmd = array_merge([PHP_BINARY, __DIR__.'/../outils/puits_smtp.php'], $args);
        $this->puitsProcessus = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['file', '/dev/null', 'a']], $pipes);
        stream_set_timeout($pipes[1], 10);
        $ligne = fgets($pipes[1]);
        if (! $ligne || ! preg_match('/PRET (\d+)/', $ligne, $m)) {
            $this->fail('le puits SMTP n\'a pas démarré');
        }
        $this->puitsPort = (int) $m[1];
    }

    protected function arreterPuits(): void
    {
        if ($this->puitsProcessus) {
            proc_terminate($this->puitsProcessus);
            proc_close($this->puitsProcessus);
            $this->puitsProcessus = null;
        }
        if ($this->puitsDossier !== '' && is_dir($this->puitsDossier)) {
            array_map('unlink', glob($this->puitsDossier.'/*') ?: []);
            @rmdir($this->puitsDossier);
        }
    }

    /** Règle le relais sur le puits. */
    protected function reglerSmtp(array $v = [], ?string $mdp = null): void
    {
        ReglagesSmtp::enregistrer($v + [
            'hote' => '127.0.0.1', 'port' => $this->puitsPort, 'chiffrement' => 'aucun', 'utilisateur' => '',
            'expediteur' => 'relais@clinique.bj', 'expediteur_nom' => 'Relais SIGH-CNT', 'verifier_certificat' => false,
        ], $mdp);
    }

    /** @return list<array{de:string,a:array<int,string>,chiffre:bool,data:string}> */
    protected function messagesRecus(): array
    {
        $out = [];
        foreach (glob($this->puitsDossier.'/*.json') ?: [] as $f) {
            $out[] = json_decode((string) file_get_contents($f), true);
        }

        return $out;
    }

    /** Le texte lisible d'un message reçu : sujet décodé et corps décodé (quoted-printable ou base64 selon l'en-tête). */
    protected function lire(array $message): array
    {
        [$entetes, $corps] = array_pad(preg_split("/\r\n\r\n/", $message['data'], 2), 2, '');
        $sujet = '';
        if (preg_match('/^Subject:\s*((?:.+\r\n(?:[ \t].+\r\n)*))/mi', $entetes."\r\n", $m)) {
            $sujet = iconv_mime_decode(preg_replace('/\r\n[ \t]+/', ' ', trim($m[1])), 0, 'UTF-8');
        }
        if (stripos($entetes, 'quoted-printable') !== false) {
            $corps = quoted_printable_decode($corps);
        } elseif (stripos($entetes, 'base64') !== false) {
            $corps = (string) base64_decode($corps);
        }

        return ['sujet' => $sujet, 'corps' => $corps, 'entetes' => $entetes];
    }
}
