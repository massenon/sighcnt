<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $titre ?? 'Panneau du relais' }} · SIGH-CNT</title>
    <link rel="stylesheet" href="{{ asset('css/panneau.css') }}">
    @livewireStyles
</head>
<body>
@php
    $menu = [
        'panneau.tableau' => 'Tableau de bord du relais',
        'panneau.appareils' => 'Appareils',
        'panneau.boites' => 'Boîtes aux lettres',
        'panneau.codes' => 'Codes d’appairage',
        'panneau.indicateurs' => 'Indicateurs reçus',
        'panneau.alertes' => 'Alertes et notifications',
        'panneau.journal' => 'Journal d’audit du relais',
        'panneau.superadmin' => 'Comptes superadmin',
        'panneau.parametres' => 'Paramètres du relais',
        'panneau.hebergement' => 'Hébergement',
        'panneau.sauvegarde' => 'Sauvegarde du relais',
        'panneau.opacite' => 'Preuve d’opacité',
        'panneau.consultation' => 'Consultation des copies',
    ];
@endphp
<header class="entete">
    <strong>SIGH-CNT · Relais en ligne (apps/web)</strong>
    <nav aria-label="Navigation du panneau">
        @foreach($menu as $route => $libelle)
            <a href="{{ route($route) }}" @if(request()->routeIs($route)) aria-current="page" @endif>{{ $libelle }}</a>
        @endforeach
    </nav>
    <form method="post" action="{{ route('panneau.deconnexion') }}">@csrf <button type="submit">Se déconnecter</button></form>
</header>
<main>
    {{ $slot }}
</main>
@livewireScripts
</body>
</html>
