<?php

namespace App\Relais\Sauvegarde;

use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\DB;

/**
 * L'ENTREPÔT DES BLOCS OPAQUES (lot 5, ADR-0007). Contrat : `packages/sync/banc/relais-sauvegarde.js` (implémentation de référence, éprouvée par les scénarios SAUVHS du banc).
 * Ce fichier n'importe AUCUNE fonction de chiffrement et ne détient aucune clé : il stocke des blocs dont il ne voit que l'identifiant (empreinte du chiffré), la taille et la date.
 * Les blocs sont sur DISQUE, jamais en base. Il ne juge jamais un contenu.
 */
class Entrepot
{
    private const ID = '/^[0-9a-f]{64}$/';

    public static function refus(int $statut, string $code, string $motif, string $geste, array $plus = []): never
    {
        throw new HttpResponseException(response()->json(['code' => $code, 'motif' => $motif, 'geste' => $geste] + $plus, $statut));
    }

    private static function maintenant(): int
    {
        return (int) (microtime(true) * 1000);
    }

    public static function dossier(): string
    {
        return (string) config('relais.sauvegardes_dir');
    }

    public static function chemin(string $id): string
    {
        return self::dossier().'/blocs/'.substr($id, 0, 2).'/'.$id;
    }

    public static function octets(int $n): string
    {
        return $n >= 1073741824 ? number_format($n / 1073741824, 1, ',', ' ').' Gio' : ($n >= 1048576 ? number_format($n / 1048576, 1, ',', ' ').' Mio' : ($n >= 1024 ? round($n / 1024).' Kio' : $n.' o'));
    }

    /** Les limites au format que lit le client (camelCase). */
    public static function limites(): array
    {
        $r = Reglages::toutes();

        return ['tailleBlocMax' => $r['taille_bloc_max'], 'tailleMaxCopie' => $r['taille_max_copie'], 'quotaOctets' => $r['quota_octets'], 'rotationPlancher' => $r['rotation_plancher'], 'rotationPlafond' => $r['rotation_plafond'], 'orphelinsHeures' => $r['orphelins_heures']];
    }

    public static function utilise(): int
    {
        return (int) DB::table('relais_sauv_blocs')->sum('taille');
    }

    /** Les copies « ouvertes » depuis plus que le délai des orphelins sont ABANDONNÉES : leurs blocs ne sont plus épinglés. */
    public static function abandonner(): void
    {
        $seuil = self::maintenant() - Reglages::toutes()['orphelins_heures'] * 3600 * 1000;
        DB::table('relais_sauv_copies')->where('etat', 'ouverte')->where('recu', '<', $seuil)->update(['etat' => 'abandonnee', 'motif' => 'jamais validée dans le délai des orphelins']);
    }

    private static function epingles()
    {
        return DB::table('relais_sauv_liens as l')->join('relais_sauv_copies as c', 'c.id', '=', 'l.copie')->whereIn('c.etat', ['ouverte', 'complete'])->select('l.bloc');
    }

    public static function liberable(): int
    {
        self::abandonner();
        $seuil = self::maintenant() - Reglages::toutes()['orphelins_heures'] * 3600 * 1000;

        return (int) DB::table('relais_sauv_blocs')->whereNotIn('id', self::epingles())
            ->where(fn ($q) => $q->whereIn('id', DB::table('relais_sauv_liens')->select('bloc'))->orWhere('recu', '<', $seuil))->sum('taille');
    }

    private static function supprimerBloc(string $id): void
    {
        @unlink(self::chemin($id));
        DB::table('relais_sauv_blocs')->where('id', $id)->delete();
    }

    /** LIBÉRER de la place : orphelins vieux d'abord, puis les copies archivées ou abandonnées, la plus ancienne d'abord (jamais une copie courante, en cours, ni l'une des `plancher` plus récentes). */
    public static function liberer(int $besoin): void
    {
        $lim = self::limites();
        $reste = fn () => self::utilise() + $besoin - $lim['quotaOctets'];
        self::abandonner();
        $seuil = self::maintenant() - $lim['orphelinsHeures'] * 3600 * 1000;
        foreach (DB::table('relais_sauv_blocs')->whereNotIn('id', DB::table('relais_sauv_liens')->select('bloc'))->where('recu', '<', $seuil)->orderBy('recu')->pluck('id') as $id) {
            if ($reste() <= 0) {
                break;
            }
            self::supprimerBloc($id);
        }
        $copies = DB::table('relais_sauv_copies')->whereIn('etat', ['complete', 'archivee', 'abandonnee'])->get(['id', 'type', 'etat', 'date'])->map(fn ($c) => (array) $c)->all();
        foreach (Regles::ordrePurge($copies, $lim['rotationPlancher']) as $id) {
            if ($reste() <= 0) {
                break;
            }
            DB::table('relais_sauv_copies')->where('id', $id)->update(['etat' => 'purgee', 'motif' => 'purgée pour libérer de la place']);
            $siens = DB::table('relais_sauv_liens')->where('copie', $id)->pluck('bloc');
            DB::table('relais_sauv_liens')->where('copie', $id)->delete();
            /* seuls les blocs de CETTE copie, et seulement ceux qu'aucune autre copie ne tient : un orphelin récent (copie en cours de dépôt) n'est jamais touché */
            foreach ($siens as $bloc) {
                if (! DB::table('relais_sauv_liens')->where('bloc', $bloc)->exists()) {
                    self::supprimerBloc($bloc);
                }
            }
            DB::table('relais_audit')->insert(['quand' => self::maintenant(), 'acteur' => 'relais', 'action' => 'sauvegarde_purgee', 'detail' => substr($id, 0, 12)]);
        }
    }

    public static function vue(object $c): array
    {
        return ['id' => $c->id, 'type' => $c->type, 'etat' => $c->etat, 'date' => (int) $c->date, 'recu' => (int) $c->recu, 'garder' => (int) $c->garder, 'nb_blocs' => (int) $c->nb_blocs, 'taille' => (int) $c->taille, 'motif' => $c->motif];
    }

    public static function etat(): array
    {
        $copies = [];
        foreach (Regles::TYPES as $t) {
            $cs = DB::table('relais_sauv_copies')->where('type', $t)->orderByDesc('date')->orderBy('id')->get();
            $derniere = $cs->firstWhere('etat', 'complete');
            $copies[$t] = [
                'completes' => $cs->where('etat', 'complete')->count(), 'archivees' => $cs->where('etat', 'archivee')->count(), 'purgees' => $cs->where('etat', 'purgee')->count(),
                'ouvertes' => $cs->where('etat', 'ouverte')->count(), 'derniere' => $derniere ? self::vue($derniere) : null,
            ];
        }

        return ['format' => 1, 'limites' => self::limites(), 'utilise' => self::utilise(), 'liberable' => self::liberable(), 'nb_blocs' => (int) DB::table('relais_sauv_blocs')->count(), 'copies' => $copies];
    }

    public static function manquants(array $ids): array
    {
        $ids = array_values(array_filter(array_map('strval', $ids), fn ($i) => preg_match(self::ID, $i)));
        if (count($ids) > 2000) {
            self::refus(413, 'TROP_D_IDENTIFIANTS', 'plus de 2000 identifiants dans une demande', 'Demander par paquets de 2000 au plus.');
        }
        $ont = array_flip(DB::table('relais_sauv_blocs')->whereIn('id', $ids)->pluck('id')->all());

        return array_values(array_filter($ids, fn ($i) => ! isset($ont[$i])));
    }

    public static function deposerBloc(string $id, string $brut): array
    {
        if (! preg_match(self::ID, $id)) {
            self::refus(422, 'BLOC_ID_INVALIDE', 'l\'identifiant d\'un bloc est une empreinte SHA-256 en hexadécimal', 'Utiliser l\'empreinte du bloc chiffré.');
        }
        $lim = self::limites();
        $taille = strlen($brut);
        if ($taille === 0 || $taille > $lim['tailleBlocMax']) {
            self::refus(413, 'BLOC_TROP_GROS', "un bloc fait de 1 à {$lim['tailleBlocMax']} octets, celui-ci en porte $taille", 'Réduire la taille de bloc du réglage (1 Mio par défaut).', ['limite' => $lim['tailleBlocMax']]);
        }
        if (hash('sha256', $brut) !== $id) {
            self::refus(422, 'BLOC_ALTERE_EN_ROUTE', 'les octets reçus n\'ont pas l\'empreinte annoncée : le bloc a été altéré en route', 'Renvoyer le bloc.');
        }
        if (DB::table('relais_sauv_blocs')->where('id', $id)->exists()) {
            return ['id' => $id, 'taille' => $taille, 'rejeu' => true];
        }
        if (self::utilise() + $taille > $lim['quotaOctets']) {
            self::liberer($taille);
            if (self::utilise() + $taille > $lim['quotaOctets']) {
                self::refus(507, 'ESPACE_RELAIS_INSUFFISANT', 'le quota du relais ('.self::octets($lim['quotaOctets']).') est atteint, rien d\'actuel n\'a été supprimé', 'Relever le quota du relais, réduire le nombre de copies gardées, ou choisir un dossier distant.', ['utilise' => self::utilise(), 'quota' => $lim['quotaOctets']]);
            }
        }
        $chemin = self::chemin($id);
        if (! is_dir(dirname($chemin))) {
            mkdir(dirname($chemin), 0770, true);
        }
        file_put_contents($chemin.'.tmp', $brut);
        rename($chemin.'.tmp', $chemin);
        DB::table('relais_sauv_blocs')->insertOrIgnore(['id' => $id, 'taille' => $taille, 'recu' => self::maintenant()]);

        return ['id' => $id, 'taille' => $taille];
    }

    /** Les octets d'un bloc, après REVÉRIFICATION de l'empreinte (le disque du relais peut s'altérer). */
    public static function lireBloc(string $id): string
    {
        if (! preg_match(self::ID, $id)) {
            self::refus(422, 'BLOC_ID_INVALIDE', 'l\'identifiant d\'un bloc est une empreinte SHA-256 en hexadécimal', 'Utiliser l\'empreinte du bloc chiffré.');
        }
        if (! DB::table('relais_sauv_blocs')->where('id', $id)->exists() || ! is_file(self::chemin($id))) {
            self::refus(404, 'BLOC_ABSENT', 'ce bloc n\'est pas (ou plus) sur le relais', 'Choisir une autre copie.');
        }
        $octets = (string) file_get_contents(self::chemin($id));
        if (hash('sha256', $octets) !== $id) {
            self::refus(409, 'BLOC_ALTERE_AU_RELAIS', 'le bloc stocké ne correspond plus à son empreinte', 'Choisir une autre copie ; signaler la panne du disque du relais.');
        }

        return $octets;
    }

    public static function copie(string $id): object
    {
        $c = DB::table('relais_sauv_copies')->where('id', $id)->first();
        if (! $c) {
            self::refus(404, 'COPIE_INCONNUE', 'cette copie n\'existe pas sur le relais', 'Relire la liste des copies.');
        }

        return $c;
    }

    public static function ouvrir(string $id, string $type, int $date, mixed $garder): array
    {
        if (! preg_match(self::ID, $id) || ! in_array($type, Regles::TYPES, true)) {
            self::refus(422, 'COPIE_INVALIDE', 'identifiant ou type de copie invalide', 'Utiliser l\'identifiant calculé par le poste mère (empreinte du manifeste) et un type connu.');
        }
        $lim = self::limites();
        $rot = Regles::rotation([], $garder, $lim['rotationPlancher'], $lim['rotationPlafond']);
        if (! $rot['ok']) {
            self::refus(422, $rot['code'], $rot['motif'], $rot['geste'], ['plancher' => $rot['plancher'], 'plafond' => $rot['plafond']]);
        }
        $garder = (int) $garder;
        $c = DB::table('relais_sauv_copies')->where('id', $id)->first();
        if ($c) {
            if (in_array($c->etat, ['purgee', 'abandonnee'], true)) {
                DB::table('relais_sauv_copies')->where('id', $id)->update(['etat' => 'ouverte', 'recu' => self::maintenant(), 'motif' => null]);

                return ['etat' => 'ouverte', 'reprise' => true];
            }

            return ['etat' => $c->etat, 'rejeu' => true];
        }
        DB::table('relais_sauv_copies')->insert(['id' => $id, 'type' => $type, 'etat' => 'ouverte', 'date' => $date ?: self::maintenant(), 'recu' => self::maintenant(), 'garder' => $garder]);

        return ['etat' => 'ouverte'];
    }

    public static function attacher(string $id, array $ids): array
    {
        $c = self::copie($id);
        if ($c->etat === 'complete') {
            return ['rejeu' => true];
        }
        if ($c->etat !== 'ouverte') {
            self::refus(409, 'COPIE_NON_OUVERTE', "cette copie est {$c->etat}", 'Rouvrir la copie par le poste mère.');
        }
        $ids = array_map('strval', $ids);
        foreach ($ids as $i) {
            if (! preg_match(self::ID, $i)) {
                self::refus(422, 'BLOC_ID_INVALIDE', 'au plus 2000 empreintes valides par demande', 'Rattacher par paquets de 2000 au plus.');
            }
        }
        if (count($ids) > 2000) {
            self::refus(422, 'BLOC_ID_INVALIDE', 'au plus 2000 empreintes valides par demande', 'Rattacher par paquets de 2000 au plus.');
        }
        $manquants = self::manquants($ids);
        if ($manquants) {
            self::refus(409, 'BLOC_MANQUANT', count($manquants).' bloc(s) ne sont pas sur le relais', 'Déposer d\'abord les blocs manquants.', ['manquants' => array_slice($manquants, 0, 50)]);
        }
        $lim = self::limites();
        DB::transaction(function () use ($c, $ids, $lim) {
            foreach ($ids as $i) {
                DB::table('relais_sauv_liens')->insertOrIgnore(['copie' => $c->id, 'bloc' => $i]);
            }
            $t = DB::table('relais_sauv_liens as l')->join('relais_sauv_blocs as b', 'b.id', '=', 'l.bloc')->where('l.copie', $c->id)->selectRaw('COUNT(*) as n, COALESCE(SUM(b.taille),0) as s')->first();
            if ((int) $t->s > $lim['tailleMaxCopie']) {
                self::refus(413, 'SAUVEGARDE_TROP_GROSSE', 'la copie pèse '.self::octets((int) $t->s).', le maximum par copie est '.self::octets($lim['tailleMaxCopie']), 'Relever la limite par copie du relais, ou choisir un dossier distant.', ['limite' => $lim['tailleMaxCopie']]);
            }
            DB::table('relais_sauv_copies')->where('id', $c->id)->update(['nb_blocs' => (int) $t->n, 'taille' => (int) $t->s]);
        });

        return ['rattaches' => count($ids)];
    }

    public static function valider(string $id, array $racine): array
    {
        $c = self::copie($id);
        if ($c->etat === 'complete') {
            return ['etat' => 'complete', 'rejeu' => true, 'archivees' => []];
        }
        if ($c->etat !== 'ouverte') {
            self::refus(409, 'COPIE_NON_OUVERTE', "cette copie est {$c->etat}", 'Rouvrir la copie par le poste mère.');
        }
        $racine = array_map('strval', $racine);
        if ($racine === []) {
            self::refus(422, 'RACINE_ABSENTE', 'une copie complète désigne les blocs de son manifeste', 'Déposer et désigner les blocs du manifeste.');
        }
        $lies = array_flip(DB::table('relais_sauv_liens')->where('copie', $c->id)->pluck('bloc')->all());
        $manquants = array_values(array_filter($racine, fn ($i) => ! isset($lies[$i])));
        if ($manquants) {
            self::refus(409, 'BLOC_MANQUANT', count($manquants).' bloc(s) du manifeste ne sont pas rattachés à cette copie', 'Rattacher les blocs du manifeste.', ['manquants' => array_slice($manquants, 0, 50)]);
        }
        $lim = self::limites();
        $rot = Regles::rotation([], (int) $c->garder, $lim['rotationPlancher'], $lim['rotationPlafond']);
        if (! $rot['ok']) {
            self::refus(422, $rot['code'], $rot['motif'], $rot['geste']);
        }
        $archiver = [];
        DB::transaction(function () use ($c, $racine, $lim, &$archiver) {
            DB::table('relais_sauv_copies')->where('id', $c->id)->update(['etat' => 'complete', 'racine' => json_encode($racine)]);
            $toutes = DB::table('relais_sauv_copies')->where('type', $c->type)->get(['id', 'type', 'etat', 'date'])->map(fn ($x) => (array) $x)->all();
            $r = Regles::rotation($toutes, (int) $c->garder, $lim['rotationPlancher'], $lim['rotationPlafond']);
            $archiver = $r['archiver'];
            foreach ($archiver as $a) {
                DB::table('relais_sauv_copies')->where('id', $a)->update(['etat' => 'archivee']);
            }
            DB::table('relais_audit')->insert(['quand' => self::maintenant(), 'acteur' => 'mere', 'action' => 'sauvegarde_copie_validee', 'detail' => $c->type.' '.substr($c->id, 0, 12).' : '.$c->nb_blocs.' blocs, '.$c->taille.' o']);
        });

        return ['etat' => 'complete', 'archivees' => $archiver];
    }

    public static function copies(?string $type): array
    {
        $q = DB::table('relais_sauv_copies')->orderByDesc('date')->orderBy('id');
        if ($type) {
            $q->where('type', $type);
        }

        return $q->get()->map(fn ($c) => self::vue($c))->all();
    }

    public static function lireCopie(string $id): array
    {
        $c = self::copie($id);
        if ($c->etat === 'purgee') {
            self::refus(410, 'COPIE_PURGEE', 'cette copie a été purgée pour libérer de la place, elle n\'est plus restaurable', 'Choisir une copie plus récente.');
        }
        if (! in_array($c->etat, ['complete', 'archivee'], true)) {
            self::refus(409, 'COPIE_INCOMPLETE', 'cette copie n\'a jamais été validée', 'Choisir une copie complète.');
        }

        return self::vue($c) + ['racine' => json_decode((string) $c->racine, true) ?: []];
    }

    /** Ce que le panneau montre : compteurs, dates, tailles, espace. Jamais un contenu. */
    public static function resume(): array
    {
        $e = self::etat();
        $e['quota'] = $e['limites']['quotaOctets'];
        $e['pct'] = $e['quota'] > 0 ? round(100 * $e['utilise'] / $e['quota'], 1) : null;

        return $e;
    }
}
