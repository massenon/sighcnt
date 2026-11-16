<?php

namespace App\Relais\Sms;

use Illuminate\Support\Facades\Http;
use Twilio\Http\Client;
use Twilio\Http\Response;

/** Transport HTTP de la bibliothèque Twilio par le client HTTP de Laravel : `Http::fake()` le remplace dans les tests, AUCUN envoi réel. */
class TransportTwilio implements Client
{
    public function request(string $method, string $url, array $params = [], array $data = [], array $headers = [], ?string $user = null, ?string $password = null, ?int $timeout = null, $authStrategy = null): Response
    {
        $req = Http::withHeaders($headers)->timeout($timeout ?: 15)->acceptJson();
        if ($user !== null) {
            $req = $req->withBasicAuth($user, (string) $password);
        }
        if ($params !== []) {
            $url .= (str_contains($url, '?') ? '&' : '?').http_build_query($params);
        }
        $r = strtoupper($method) === 'GET' ? $req->get($url) : $req->asForm()->send(strtoupper($method), $url, ['form_params' => $data]);

        return new Response($r->status(), $r->body(), $r->headers());
    }
}
