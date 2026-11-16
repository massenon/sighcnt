<?php

namespace App\Relais\Sms;

/** Choisit le fournisseur d'après le `.env` (jamais la base). Rend le refus nommé quand les identifiants manquent : le panneau ne dit que « défini » ou « non défini ». */
class Fabrique
{
    public static function fournisseur(): string
    {
        $f = strtolower((string) config('relais.sms.fournisseur'));

        return in_array($f, ['twilio', 'vonage'], true) ? $f : '';
    }

    public static function identifiantsDefinis(): bool
    {
        return match (self::fournisseur()) {
            'twilio' => config('relais.sms.twilio_sid') !== '' && config('relais.sms.twilio_token') !== '',
            'vonage' => config('relais.sms.vonage_key') !== '' && config('relais.sms.vonage_secret') !== '',
            default => false,
        };
    }

    public static function expediteurDefini(): bool
    {
        return (string) config('relais.sms.expediteur') !== '';
    }

    /** @return array{0: ?Passerelle, 1: ?string, 2: string} passerelle, code de refus, motif */
    public static function passerelle(): array
    {
        if (self::fournisseur() === '') {
            return [null, 'SMS_NON_CONFIGUREE', 'Le fournisseur (RELAIS_SMS_FOURNISSEUR) n’est ni twilio ni vonage.'];
        }
        if (! self::identifiantsDefinis()) {
            return [null, 'SECRET_NON_DEFINI', 'Les identifiants du fournisseur ne sont pas définis dans le .env du relais (RELAIS_SMS_*).'];
        }
        if (! self::expediteurDefini()) {
            return [null, 'SMS_NON_CONFIGUREE', 'L’expéditeur (RELAIS_SMS_EXPEDITEUR) n’est pas défini dans le .env du relais.'];
        }
        $exp = (string) config('relais.sms.expediteur');

        return [self::fournisseur() === 'twilio'
            ? new PasserelleTwilio((string) config('relais.sms.twilio_sid'), (string) config('relais.sms.twilio_token'), $exp)
            : new PasserelleVonage((string) config('relais.sms.vonage_key'), (string) config('relais.sms.vonage_secret'), $exp), null, ''];
    }
}
