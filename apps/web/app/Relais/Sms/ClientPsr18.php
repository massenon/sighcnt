<?php

namespace App\Relais\Sms;

use Illuminate\Support\Facades\Http;
use Laminas\Diactoros\Response as Reponse;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestInterface;
use Psr\Http\Message\ResponseInterface;

/** Client PSR-18 de la bibliothèque Vonage par le client HTTP de Laravel : `Http::fake()` le remplace dans les tests, AUCUN envoi réel. */
class ClientPsr18 implements ClientInterface
{
    public function sendRequest(RequestInterface $request): ResponseInterface
    {
        $entetes = [];
        foreach ($request->getHeaders() as $nom => $valeurs) {
            $entetes[$nom] = implode(', ', $valeurs);
        }
        $corps = (string) $request->getBody();
        $r = Http::withHeaders($entetes)->timeout(15)->withBody($corps, $entetes['Content-Type'] ?? 'application/json')->send($request->getMethod(), (string) $request->getUri());
        $reponse = new Reponse();
        $reponse->getBody()->write($r->body());
        $reponse->getBody()->rewind();

        return $reponse->withStatus($r->status());
    }
}
