<?php

namespace App\Relais\Sms;

/** Un fournisseur de SMS. Rend toujours un tableau : `ok`, `id` (identifiant du fournisseur), `code` (refus nommé), `motif`, `transitoire` (vrai : on retente). Ne lève jamais. */
interface Passerelle
{
    /** @return array{ok: bool, id: ?string, code: ?string, motif: string, transitoire: bool} */
    public function envoyer(string $numero, string $texte): array;
}
