<?php

use App\Relais\Sms\Reglages;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * LOT SMS-R (ADR-0008) : la file des SMS du relais. Une ligne = un message DÉJÀ COMPOSÉ à la mère, gardé planifié puis envoyé par la tâche `relais:sms-envoyer`.
 *
 *  - `id` : l'identifiant OPAQUE (HMAC de la clé de clinique calculé à la mère, 64 caractères hexadécimaux) : le relais ne peut ni le défaire ni le relier à un patient ou à un rendez-vous.
 *  - `numero` et `texte` : le CLAIR n'existe que le temps de l'envoi ; dès qu'un état est final (envoyé, refusé, retiré) les deux colonnes sont EFFACÉES (`numero_masque` garde les quatre derniers chiffres pour le journal).
 *  - jamais de nom, de date de naissance, de code patient, de rendez-vous, de médecin.
 *  - les limites (plafond du jour, tentatives, délai de reprise, péremption) sont SEMÉES dans `relais_meta`, réglables au panneau.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('relais_sms', function (Blueprint $t) {
            $t->string('id', 64)->primary();
            $t->string('numero', 20)->nullable();
            $t->string('numero_masque', 24);
            $t->text('texte')->nullable();
            $t->unsignedInteger('longueur')->default(0);
            $t->string('type', 32);
            $t->unsignedBigInteger('heure_envoi');
            $t->string('etat', 12);
            $t->string('code', 40)->nullable();
            $t->unsignedSmallInteger('tentatives')->default(0);
            $t->unsignedBigInteger('prochaine')->nullable();
            $t->string('fournisseur', 12)->nullable();
            $t->string('id_fournisseur', 64)->nullable();
            $t->string('jour', 10)->nullable();
            $t->unsignedBigInteger('cree');
            $t->unsignedBigInteger('maj');
            $t->index(['etat', 'heure_envoi']);
            $t->index(['jour', 'etat']);
        });
        Reglages::semer();
    }

    public function down(): void
    {
        Schema::dropIfExists('relais_sms');
        \Illuminate\Support\Facades\DB::table('relais_meta')->where('k', 'like', 'reglage.sms.%')->delete();
    }
};
