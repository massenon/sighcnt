<?php

namespace App\Relais;

use RuntimeException;
use Throwable;

/** Un envoi SMTP qui a échoué, avec l'ÉTAPE en cause (connexion, chiffrement, authentification, expéditeur, destinataire, envoi) : un refus nommé, jamais muet. */
class EnvoiEchoue extends RuntimeException
{
    public function __construct(public string $etape, public string $motif, ?Throwable $precedent = null)
    {
        parent::__construct($motif, 0, $precedent);
    }
}
