<?php

namespace App\Relais\Sms;

use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\DB;

/**
 * LA FILE DES SMS DU RELAIS (ADR-0008). Exception BORNÉE à « relais opaque » : le relais voit, d'un message déjà composé à la mère, seulement le numéro, le texte, l'heure d'envoi, le type et un
 * identifiant OPAQUE (HMAC de la clé de clinique), le temps de l'envoi ; puis il EFFACE le clair (numéro et texte). Il ne reçoit JAMAIS l'annuaire, une date de naissance, un code patient, un rendez-vous.
 * Le relais ne porte aucune règle métier (consentement, heures calmes, mots interdits : décidés à la mère) ; il porte le plafond du jour, le format du numéro et la longueur du texte.
 */
class Messages
{
    public const TYPES = ['rappel_rdv', 'anniversaire_patient', 'anniversaire_personnel', 'test'];

    private const ID = '/^[0-9a-f]{64}$/';

    private const E164 = '/^\+[1-9][0-9]{7,14}$/';

    public const TEXTE_TEST = 'Test SIGH-CNT : la passerelle SMS fonctionne.';

    public static function refus(int $statut, string $code, string $motif, string $geste): never
    {
        throw new HttpResponseException(response()->json(['code' => $code, 'motif' => $motif, 'geste' => $geste], $statut));
    }

    public static function maintenant(): int
    {
        return (int) (microtime(true) * 1000);
    }

    /** Le jour du plafond : la date de l'heure du Bénin (config relais.sms.fuseau). */
    public static function jour(int $ms): string
    {
        return \Carbon\CarbonImmutable::createFromTimestampMs($ms, (string) config('relais.sms.fuseau'))->format('Y-m-d');
    }

    public static function masquer(string $numero): string
    {
        return '••••'.substr($numero, -4);
    }

    /** Le refus d'un message à déposer, ou null. */
    public static function controle(array $m): ?array
    {
        $id = $m['id'] ?? null;
        if (! is_string($id) || preg_match(self::ID, $id) !== 1) {
            return ['IDENTIFIANT_NON_OPAQUE', 'L’identifiant doit être une empreinte opaque de 64 caractères hexadécimaux calculée à la mère, jamais un code de patient ni de rendez-vous.'];
        }
        if (! in_array($m['type'] ?? null, self::TYPES, true)) {
            return ['TYPE_INCONNU', 'Le type de message n’est pas dans la liste admise ('.implode(', ', self::TYPES).').'];
        }
        if (! is_string($m['numero'] ?? null) || preg_match(self::E164, $m['numero']) !== 1) {
            return ['NUMERO_INVALIDE', 'Le numéro doit être au format international E.164 (+229...).'];
        }
        $t = $m['texte'] ?? null;
        if (! is_string($t) || trim($t) === '') {
            return ['TEXTE_VIDE', 'Le texte du message est vide.'];
        }
        if (mb_strlen($t) > Reglages::TEXTE_MAX) {
            return ['TEXTE_TROP_LONG', 'Le texte dépasse '.Reglages::TEXTE_MAX.' caractères.'];
        }
        if (! is_int($m['heureEnvoi'] ?? null) || $m['heureEnvoi'] <= 0) {
            return ['HEURE_INVALIDE', 'L’heure d’envoi doit être un horodatage en millisecondes.'];
        }

        return null;
    }

    /** Dépose des messages composés à la mère. Idempotent : un identifiant déjà connu n'est jamais redéposé (un message retiré peut être replanifié, un message parti ou refusé jamais). */
    public static function deposer(array $messages): array
    {
        $now = self::maintenant();
        $rendu = [];
        foreach (array_slice($messages, 0, 500) as $m) {
            $m = is_array($m) ? $m : [];
            if (($refus = self::controle($m)) !== null) {
                $rendu[] = ['id' => (string) ($m['id'] ?? ''), 'etat' => 'refuse', 'code' => $refus[0], 'motif' => $refus[1]];

                continue;
            }
            $ligne = DB::table('relais_sms')->where('id', $m['id'])->first();
            if ($ligne !== null && $ligne->etat !== 'retire') {
                $rendu[] = ['id' => $m['id'], 'etat' => 'existant', 'etatMessage' => $ligne->etat, 'code' => $ligne->code];

                continue;
            }
            $champs = ['numero' => $m['numero'], 'numero_masque' => self::masquer($m['numero']), 'texte' => $m['texte'], 'longueur' => mb_strlen($m['texte']), 'type' => $m['type'], 'heure_envoi' => $m['heureEnvoi'],
                'etat' => 'planifie', 'code' => null, 'tentatives' => 0, 'prochaine' => null, 'maj' => $now];
            if ($ligne === null) {
                DB::table('relais_sms')->insert(['id' => $m['id'], 'cree' => $now] + $champs);
            } else {
                DB::table('relais_sms')->where('id', $m['id'])->update($champs);
            }
            $rendu[] = ['id' => $m['id'], 'etat' => 'planifie'];
        }

        return $rendu;
    }

    /** Retire un envoi encore planifié (rendez-vous annulé ou déplacé, consentement retiré, numéro corrigé). Un envoi PARTI ne se retire pas : on le dit. */
    public static function annuler(array $ids): array
    {
        $rendu = [];
        foreach (array_slice($ids, 0, 500) as $id) {
            $id = (string) $id;
            $l = DB::table('relais_sms')->where('id', $id)->first();
            if ($l === null) {
                $rendu[] = ['id' => $id, 'etat' => 'inconnu'];
            } elseif ($l->etat === 'planifie') {
                $n = DB::table('relais_sms')->where('id', $id)->where('etat', 'planifie')->update(['etat' => 'retire', 'numero' => null, 'texte' => null, 'maj' => self::maintenant()]);
                $rendu[] = ['id' => $id, 'etat' => $n === 1 ? 'retire' : 'deja_parti'];
            } else {
                $rendu[] = ['id' => $id, 'etat' => $l->etat === 'retire' ? 'retire' : 'deja_parti', 'etatMessage' => $l->etat];
            }
        }

        return $rendu;
    }

    public static function envoyesAujourdhui(?int $ms = null): int
    {
        return DB::table('relais_sms')->where('etat', 'envoye')->where('jour', self::jour($ms ?? self::maintenant()))->count();
    }

    /** Termine un message : l'état est final, le CLAIR est effacé (numéro et texte), seul le numéro masqué reste. */
    private static function finir(string $id, string $etat, ?string $code, array $plus = []): void
    {
        DB::table('relais_sms')->where('id', $id)->update(['etat' => $etat, 'code' => $code, 'numero' => null, 'texte' => null, 'prochaine' => null, 'maj' => self::maintenant()] + $plus);
    }

    /** Envoie UN message dû. Rend l'état d'arrivée (envoye, refuse, planifie pour une reprise ou une passerelle non configurée, passe pour un message pris par un autre passage). */
    public static function expedier(object $l, ?Passerelle $passerelle): string
    {
        $now = self::maintenant();
        $r = Reglages::toutes();
        if ($now - (int) $l->heure_envoi > $r['peremption_minutes'] * 60000) {
            self::finir($l->id, 'refuse', 'HEURE_DEPASSEE');

            return 'refuse';
        }
        if (self::envoyesAujourdhui($now) >= $r['plafond_jour']) {
            // Un message bloqué par le plafond n'est PAS reporté au lendemain (Direction, 16/11/2026) : il est refusé, nommé.
            self::finir($l->id, 'refuse', 'PLAFOND_ATTEINT');

            return 'refuse';
        }
        if ($passerelle === null) {
            return 'planifie';
        }
        // Prise du message par UN seul passage (le cron ne chevauche pas, le test non plus).
        if (DB::table('relais_sms')->where('id', $l->id)->where('etat', 'planifie')->update(['etat' => 'encours', 'maj' => $now]) !== 1) {
            return 'passe';
        }
        $res = $passerelle->envoyer((string) $l->numero, (string) $l->texte);
        if ($res['ok']) {
            self::finir($l->id, 'envoye', null, ['fournisseur' => Fabrique::fournisseur(), 'id_fournisseur' => $res['id'], 'jour' => self::jour($now), 'tentatives' => $l->tentatives + 1]);

            return 'envoye';
        }
        $n = $l->tentatives + 1;
        if ($res['transitoire'] && $n < $r['tentatives_max']) {
            DB::table('relais_sms')->where('id', $l->id)->update(['etat' => 'planifie', 'tentatives' => $n, 'code' => $res['code'], 'prochaine' => $now + $r['reprise_secondes'] * 1000, 'maj' => $now]);

            return 'planifie';
        }
        self::finir($l->id, 'refuse', $res['code'], ['fournisseur' => Fabrique::fournisseur(), 'tentatives' => $n]);

        return 'refuse';
    }

    /** Le passage du cron : tous les messages dus, dans l'ordre. */
    public static function passer(): array
    {
        $now = self::maintenant();
        DB::table('relais_meta')->updateOrInsert(['k' => 'sms.dernier_passage'], ['v' => (string) $now]);
        [$passerelle] = Fabrique::passerelle();
        $dus = DB::table('relais_sms')->where('etat', 'planifie')->where('heure_envoi', '<=', $now)
            ->where(fn ($q) => $q->whereNull('prochaine')->orWhere('prochaine', '<=', $now))->orderBy('heure_envoi')->limit(200)->get();
        $bilan = ['envoye' => 0, 'refuse' => 0, 'planifie' => 0, 'passe' => 0];
        foreach ($dus as $l) {
            $bilan[self::expedier($l, $passerelle)]++;
        }

        return $bilan;
    }

    /** Le test d'envoi : message imposé, même passerelle, même plafond ; garde une ligne au journal (sans numéro ni texte). */
    public static function tester(string $numero): array
    {
        if (preg_match(self::E164, $numero) !== 1) {
            return ['ok' => false, 'code' => 'NUMERO_INVALIDE', 'motif' => 'Le numéro doit être au format international E.164 (+229...).', 'geste' => 'Saisir le numéro avec l’indicatif, par exemple +22900000000.'];
        }
        [$passerelle, $code, $motif] = Fabrique::passerelle();
        if ($passerelle === null) {
            return ['ok' => false, 'code' => $code, 'motif' => $motif, 'geste' => 'Renseigner les variables RELAIS_SMS_* du .env du relais, puis réessayer.'];
        }
        $id = hash('sha256', 'test|'.random_bytes(16));
        $now = self::maintenant();
        DB::table('relais_sms')->insert(['id' => $id, 'numero' => $numero, 'numero_masque' => self::masquer($numero), 'texte' => self::TEXTE_TEST, 'longueur' => mb_strlen(self::TEXTE_TEST), 'type' => 'test', 'heure_envoi' => $now,
            'etat' => 'planifie', 'tentatives' => 0, 'cree' => $now, 'maj' => $now]);
        $etat = self::expedier(DB::table('relais_sms')->where('id', $id)->first(), $passerelle);
        $l = DB::table('relais_sms')->where('id', $id)->first();
        if ($etat === 'envoye') {
            return ['ok' => true, 'code' => null, 'idFournisseur' => $l->id_fournisseur, 'motif' => '', 'geste' => ''];
        }
        // Un test n'est jamais retenté en silence : un échec transitoire est rendu et le message est retiré.
        if ($etat === 'planifie') {
            $code = $l->code ?? 'FOURNISSEUR_INJOIGNABLE';
            self::finir($id, 'refuse', $code, ['fournisseur' => Fabrique::fournisseur()]);
        } else {
            $code = $l->code;
        }

        return ['ok' => false, 'code' => $code, 'motif' => self::MOTIFS[$code] ?? $code, 'geste' => self::GESTES[$code] ?? ''];
    }

    public const MOTIFS = [
        'IDENTIFIANTS_REFUSES' => 'Le fournisseur refuse les identifiants du relais.',
        'SOLDE_INSUFFISANT' => 'Le solde du compte du fournisseur est insuffisant.',
        'NUMERO_INVALIDE' => 'Le fournisseur refuse le numéro de destination.',
        'EXPEDITEUR_NON_AUTORISE' => 'Le fournisseur n’autorise pas cet expéditeur pour ce pays.',
        'FOURNISSEUR_INJOIGNABLE' => 'Le fournisseur ne répond pas.',
        'FOURNISSEUR_REFUSE' => 'Le fournisseur a refusé le message.',
        'PLAFOND_ATTEINT' => 'Le plafond de messages du jour est atteint.',
        'HEURE_DEPASSEE' => 'Le message est resté planifié trop longtemps après son heure.',
    ];

    public const GESTES = [
        'IDENTIFIANTS_REFUSES' => 'Vérifier les identifiants RELAIS_SMS_* du .env du relais.',
        'SOLDE_INSUFFISANT' => 'Approvisionner le compte du fournisseur (la Directrice Administrative gère le solde).',
        'NUMERO_INVALIDE' => 'Vérifier le numéro, avec l’indicatif.',
        'EXPEDITEUR_NON_AUTORISE' => 'Utiliser un numéro expéditeur accepté pour le Bénin (RELAIS_SMS_EXPEDITEUR).',
        'FOURNISSEUR_INJOIGNABLE' => 'Réessayer plus tard ; vérifier la connexion du relais.',
        'FOURNISSEUR_REFUSE' => 'Consulter le compte du fournisseur.',
        'PLAFOND_ATTEINT' => 'Attendre demain ou relever le plafond au panneau (Passerelle SMS).',
        'HEURE_DEPASSEE' => 'Le poste mère recalcule et redépose les envois du jour.',
    ];

    public static function etat(): array
    {
        $now = self::maintenant();
        $r = Reglages::toutes();
        $jour = self::jour($now);
        $dernier = DB::table('relais_meta')->where('k', 'sms.dernier_passage')->value('v');

        return [
            'fournisseur' => Fabrique::fournisseur(),
            'identifiantsDefinis' => Fabrique::identifiantsDefinis(),
            'expediteurDefini' => Fabrique::expediteurDefini(),
            'configuree' => Fabrique::passerelle()[0] !== null,
            'reglages' => $r,
            'jour' => $jour,
            'envoyesAujourdhui' => self::envoyesAujourdhui($now),
            'plafondRestant' => max(0, $r['plafond_jour'] - self::envoyesAujourdhui($now)),
            'planifies' => DB::table('relais_sms')->where('etat', 'planifie')->count(),
            'enCours' => DB::table('relais_sms')->where('etat', 'encours')->count(),
            'refusesAujourdhui' => DB::table('relais_sms')->where('etat', 'refuse')->where('maj', '>=', $now - 86400000)->count(),
            'dernierPassage' => is_numeric($dernier) ? (int) $dernier : null,
        ];
    }

    /** Le journal, SANS texte ni numéro en clair (numéro masqué seulement). */
    public static function journal(int $limite = 200, ?int $depuis = null): array
    {
        $q = DB::table('relais_sms')->orderByDesc('maj')->limit(max(1, min(500, $limite)));
        if ($depuis !== null) {
            $q->where('maj', '>=', $depuis);
        }

        return $q->get(['id', 'type', 'etat', 'code', 'heure_envoi', 'numero_masque', 'longueur', 'fournisseur', 'id_fournisseur', 'tentatives', 'jour', 'maj'])->map(fn ($l) => [
            'id' => $l->id, 'type' => $l->type, 'etat' => $l->etat, 'code' => $l->code, 'heureEnvoi' => (int) $l->heure_envoi, 'numeroMasque' => $l->numero_masque, 'longueur' => (int) $l->longueur,
            'fournisseur' => $l->fournisseur, 'idFournisseur' => $l->id_fournisseur, 'tentatives' => (int) $l->tentatives, 'jour' => $l->jour, 'maj' => (int) $l->maj,
        ])->all();
    }

    /** Conservation du journal : les lignes finales plus vieilles que le réglage sont supprimées du RELAIS (déjà sans numéro ni texte ; la mère garde son journal). */
    public static function purger(): int
    {
        $limite = self::maintenant() - Reglages::toutes()['conservation_jours'] * 86400000;

        return DB::table('relais_sms')->whereIn('etat', ['envoye', 'refuse', 'retire'])->where('maj', '<', $limite)->delete();
    }
}
