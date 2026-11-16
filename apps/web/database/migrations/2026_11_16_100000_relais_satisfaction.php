<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * LOT SAT (ADR-0009) : la SATISFACTION EN LIGNE. Le relais héberge un formulaire public et dépose des blocs OPAQUES : il ne détient aucune clé, il ne lit jamais une réponse.
 *
 *  - `relais_sat_cle`      : la clé PUBLIQUE de la clinique (X25519), publiée par la mère. Une seule ligne.
 *  - `relais_sat_liens`    : un lien de collecte, connu par l'EMPREINTE SHA-256 de son jeton seulement (le jeton ne s'écrit jamais ici), avec le questionnaire à afficher (aucune donnée de santé).
 *  - `relais_sat_reponses` : une enveloppe scellée (clé éphémère, vecteur, texte chiffré), son identifiant unique (anti-rejeu), l'empreinte du lien par lequel elle est venue, la date de réception.
 *  - `relais_sat_debit`    : l'EMPREINTE d'une adresse (HMAC, jamais l'adresse) et l'heure, gardée le temps de la fenêtre de limitation (10 minutes) puis effacée.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('relais_sat_cle', function (Blueprint $t) {
            $t->unsignedTinyInteger('id')->primary();
            $t->string('cle', 64);
            $t->string('cle_id', 16);
            $t->unsignedBigInteger('publiee');
        });
        Schema::create('relais_sat_liens', function (Blueprint $t) {
            $t->string('empreinte', 64)->primary();
            $t->text('charge');
            $t->unsignedBigInteger('expire')->nullable();
            $t->unsignedBigInteger('revoque')->nullable();
            $t->unsignedBigInteger('maj');
        });
        Schema::create('relais_sat_reponses', function (Blueprint $t) {
            $t->bigIncrements('seq');
            $t->string('id', 64)->unique();
            $t->string('lien', 64)->index();
            $t->text('bloc');
            $t->unsignedInteger('taille');
            $t->unsignedBigInteger('recu');
        });
        Schema::create('relais_sat_debit', function (Blueprint $t) {
            $t->string('empreinte', 64)->index();
            $t->unsignedBigInteger('t')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('relais_sat_debit');
        Schema::dropIfExists('relais_sat_reponses');
        Schema::dropIfExists('relais_sat_liens');
        Schema::dropIfExists('relais_sat_cle');
    }
};
