<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Le courriel de récupération de la clé de la clinique : il ne porte que le COFFRE (la clé chiffrée par une phrase secrète, inutilisable sans elle). Mis en file
 * (Laravel Mail) : un échec d'envoi ne bloque pas le poste qui l'a demandé.
 */
class CoffreCleMail extends Mailable implements ShouldQueue
{
    use Queueable, SerializesModels;

    /** @param array<string,mixed> $coffre */
    public function __construct(public array $coffre) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'SIGH-CNT : coffre de la clé de la clinique');
    }

    public function content(): Content
    {
        return new Content(text: 'mail.coffre-cle', with: ['texteCoffre' => json_encode($this->coffre, JSON_UNESCAPED_SLASHES)]);
    }
}
