<?php

namespace App\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/** Le message de test du panneau : il ne contient aucun secret, seulement de quoi vérifier l'acheminement et l'encodage (accents). */
class TestSmtpMail extends Mailable
{
    public function envelope(): Envelope
    {
        return new Envelope(subject: 'SIGH-CNT : message de test de la messagerie du relais');
    }

    public function content(): Content
    {
        return new Content(text: 'mail.test-smtp');
    }
}
