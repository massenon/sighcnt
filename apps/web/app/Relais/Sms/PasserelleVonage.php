<?php

namespace App\Relais\Sms;

use Throwable;
use Vonage\Client;
use Vonage\Client\Credentials\Basic;
use Vonage\Client\Exception\RequestException;
use Vonage\SMS\Message\SMS;

/**
 * Vonage par la bibliothèque officielle `vonage/client`, au travers de `ClientPsr18` (client HTTP de Laravel). Correspondance des états de l'API SMS (à confirmer en recette) :
 * 4 ou 2 : identifiants ; 9 : solde (quota) ; 3, 6, 7 : numéro ; 15 : expéditeur ; 5, 1, 429, 5xx ou réseau : fournisseur injoignable (on retente).
 */
class PasserelleVonage implements Passerelle
{
    public function __construct(private string $cle, private string $secret, private string $expediteur) {}

    public function envoyer(string $numero, string $texte): array
    {
        try {
            $client = new Client(new Basic($this->cle, $this->secret), [], new ClientPsr18);
            $reponse = $client->sms()->send(new SMS(ltrim($numero, '+'), $this->expediteur, $texte));

            return ['ok' => true, 'id' => (string) $reponse->current()->getMessageId(), 'code' => null, 'motif' => '', 'transitoire' => false];
        } catch (RequestException $e) {
            return self::refus((int) $e->getCode());
        } catch (Throwable $e) {
            return self::refus(0);
        }
    }

    public static function refus(int $statut): array
    {
        [$c, $m, $t] = match (true) {
            in_array($statut, [2, 4], true) => ['IDENTIFIANTS_REFUSES', 'Le fournisseur refuse les identifiants du relais.', false],
            $statut === 9 => ['SOLDE_INSUFFISANT', 'Le solde du compte du fournisseur est insuffisant.', false],
            in_array($statut, [3, 6, 7], true) => ['NUMERO_INVALIDE', 'Le fournisseur refuse le numéro de destination.', false],
            $statut === 15 => ['EXPEDITEUR_NON_AUTORISE', 'Le fournisseur n’autorise pas cet expéditeur pour ce pays.', false],
            default => ['FOURNISSEUR_INJOIGNABLE', 'Le fournisseur ne répond pas.', true],
        };

        return ['ok' => false, 'id' => null, 'code' => $c, 'motif' => $m, 'transitoire' => $t];
    }
}
