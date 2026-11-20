<?php

use App\Relais\Sauvegarde\Reglages;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * LOT 5 (ADR-0007) : la SAUVEGARDE HORS SITE par blocs opaques. Le relais ne connaît que des identifiants de blocs (empreintes du CHIFFRÉ), des tailles, des dates, des compteurs.
 * Les blocs vivent SUR DISQUE (`storage/app/sauvegardes/blocs/<2>/<id>`), jamais en base : la base ne porte que ces trois tables de lignes.
 *
 *  - `relais_sauv_blocs`  : un bloc (identifiant, taille, date de réception).
 *  - `relais_sauv_copies` : une copie d'un type (magasin, fichiers) : état (ouverte, complete, archivee, purgee, abandonnee), date posée par la mère, racine (identifiants des blocs du manifeste).
 *  - `relais_sauv_liens`  : quels blocs une copie tient (un bloc partagé par plusieurs copies n'est gardé qu'une fois).
 *  - les limites (quota, limite par copie, taille maximale d'un bloc, plancher et plafond de rotation, délai des orphelins) sont SEMÉES dans `relais_meta`, réglables au panneau.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('relais_sauv_blocs', function (Blueprint $t) {
            $t->string('id', 64)->primary();
            $t->unsignedBigInteger('taille');
            $t->unsignedBigInteger('recu');
            $t->index('recu');
        });
        Schema::create('relais_sauv_copies', function (Blueprint $t) {
            $t->string('id', 64)->primary();
            $t->string('type', 16);
            $t->string('etat', 16);
            $t->unsignedBigInteger('date');
            $t->unsignedBigInteger('recu');
            $t->unsignedInteger('garder');
            $t->unsignedInteger('nb_blocs')->default(0);
            $t->unsignedBigInteger('taille')->default(0);
            $t->text('racine')->nullable();
            $t->string('motif', 120)->nullable();
            $t->index(['type', 'etat', 'date']);
        });
        Schema::create('relais_sauv_liens', function (Blueprint $t) {
            $t->string('copie', 64);
            $t->string('bloc', 64);
            $t->primary(['copie', 'bloc']);
            $t->index('bloc');
        });
        Reglages::semer();
    }

    public function down(): void
    {
        foreach (['relais_sauv_liens', 'relais_sauv_copies', 'relais_sauv_blocs'] as $table) {
            Schema::dropIfExists($table);
        }
        \Illuminate\Support\Facades\DB::table('relais_meta')->where('k', 'like', 'reglage.sauvegarde.%')->delete();
    }
};
