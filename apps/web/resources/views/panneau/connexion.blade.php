<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="color-scheme" content="light">
    <title>Connexion · Relais SIGH-CNT</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <link rel="stylesheet" href="{{ asset('css/jetons.css') }}">
    <link rel="stylesheet" href="{{ asset('css/panneau.css') }}">
</head>
<body>
<main class="connexion">
<div class="carte">
    <span class="marque-claire">SIGH-CNT</span>
    <h1>Relais SIGH-CNT</h1>
    <p class="sous-titre">Accès réservé à l'administrateur système.</p>
    <form class="formulaire" method="post" action="{{ route('panneau.connexion.envoi') }}">
        @csrf
        <label for="courriel">Courriel</label>
        <input id="courriel" name="courriel" type="email" value="{{ old('courriel') }}" autocomplete="username" required autofocus @error('courriel') aria-invalid="true" aria-describedby="erreur-courriel" @enderror>
        <label for="mot_de_passe">Mot de passe</label>
        <input id="mot_de_passe" name="mot_de_passe" type="password" autocomplete="current-password" required>
        @error('courriel') <div class="erreur" id="erreur-courriel" role="alert">{{ $message }}</div> @enderror
        <p><button class="btn" type="submit">Se connecter</button></p>
    </form>
</div>
</main>
</body>
</html>
