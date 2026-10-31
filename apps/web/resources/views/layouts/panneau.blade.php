<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $titre ?? 'Panneau du relais' }} — SIGH-CNT</title>
    <link rel="stylesheet" href="{{ asset('css/panneau.css') }}">
    @livewireStyles
</head>
<body>
<header class="entete">
    <strong>SIGH-CNT · Relais</strong>
    <nav aria-label="Navigation du panneau">
        <a href="{{ route('panneau.tableau') }}" @if(request()->routeIs('panneau.tableau')) aria-current="page" @endif>Tableau de bord</a>
        <a href="{{ route('panneau.appareils') }}" @if(request()->routeIs('panneau.appareils')) aria-current="page" @endif>Appareils</a>
        <a href="{{ route('panneau.codes') }}" @if(request()->routeIs('panneau.codes')) aria-current="page" @endif>Codes d'appairage</a>
        <a href="{{ route('panneau.journal') }}" @if(request()->routeIs('panneau.journal')) aria-current="page" @endif>Journal</a>
    </nav>
    <form method="post" action="{{ route('panneau.deconnexion') }}">@csrf <button type="submit">Se déconnecter</button></form>
</header>
<main>
    {{ $slot }}
</main>
@livewireScripts
</body>
</html>
