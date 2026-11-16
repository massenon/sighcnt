<?php

namespace App\Relais\Sms;

use Throwable;
use Twilio\Exceptions\RestException;
use Twilio\Rest\Client;

/**
 * Twilio par la bibliothèque officielle `twilio/sdk`, au travers de `TransportTwilio` (client HTTP de Laravel). Correspondance des refus (à confirmer en recette avec un vrai compte) :
 * 401 ou code 20003 : identifiants ; 402 : solde ; 21211, 21614 : numéro ; 21606, 21608, 21612 : expéditeur ; 429 et 5xx ou réseau : fournisseur injoignable (on retente).
 */
class PasserelleTwilio implements Passerelle
{
    public function __construct(private string $sid, private string $jeton, private string $expediteur) {}

    public function envoyer(string $numero, string $texte): array
    {
        try {
            $client = new Client($this->sid, $this->jeton, null, null, new TransportTwilio, []);
            $m = $client->messages->create($numero, ['from' => $this->expediteur, 'body' => $texte]);

            return ['ok' => true, 'id' => (string) $m->sid, 'code' => null, 'motif' => '', 'transitoire' => false];
        } catch (RestException $e) {
            return self::refus($e->getStatusCode(), (int) $e->getCode());
        } catch (Throwable $e) {
            return self::refus(0, 0);
        }
    }

    public static function refus(int $http, int $code): array
    {
        [$c, $m, $t] = match (true) {
            $http === 401 || $code === 20003 => ['IDENTIFIANTS_REFUSES', 'Le fournisseur refuse les identifiants du relais.', false],
            $http === 402 => ['SOLDE_INSUFFISANT', 'Le solde du compte du fournisseur est insuffisant.', false],
            in_array($code, [21211, 21614], true) => ['NUMERO_INVALIDE', 'Le fournisseur refuse le numéro de destination.', false],
            in_array($code, [21606, 21608, 21612], true) => ['EXPEDITEUR_NON_AUTORISE', 'Le fournisseur n’autorise pas cet expéditeur pour ce pays.', false],
            $http === 0 || $http === 429 || $http >= 500 => ['FOURNISSEUR_INJOIGNABLE', 'Le fournisseur ne répond pas.', true],
            default => ['FOURNISSEUR_REFUSE', 'Le fournisseur a refusé le message (HTTP '.$http.').', false],
        };

        return ['ok' => false, 'id' => null, 'code' => $c, 'motif' => $m, 'transitoire' => $t];
    }
}
