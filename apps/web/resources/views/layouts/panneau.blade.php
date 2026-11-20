<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="color-scheme" content="light">
    <title>{{ $titre ?? 'Panneau du relais' }} · SIGH-CNT</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <link rel="stylesheet" href="{{ asset('css/jetons.css') }}">
    <link rel="stylesheet" href="{{ asset('css/panneau.css') }}">
    <script>document.documentElement.classList.add('js')</script>
    @livewireStyles
</head>
<body>
@php
    // Réservé au superadmin : un compte qui ne l'est pas ne voit aucune entrée (et n'ouvre aucune route).
    $groupes = [
        'Exploitation' => [
            'panneau.tableau' => 'Tableau de bord du relais',
            'panneau.appareils' => 'Appareils',
            'panneau.boites' => 'Boîtes aux lettres',
            'panneau.codes' => 'Codes d’appairage',
            'panneau.indicateurs' => 'Indicateurs reçus',
            'panneau.synchronisation' => 'Synchronisation',
            'panneau.alertes' => 'Alertes et notifications',
        ],
        'Administration' => [
            'panneau.journal' => 'Journal d’audit du relais',
            'panneau.superadmin' => 'Comptes superadmin',
            'panneau.parametres' => 'Paramètres du relais',
            'panneau.hebergement' => 'Hébergement',
            'panneau.sauvegarde' => 'Sauvegarde du relais',
            'panneau.sms' => 'Passerelle SMS',
        ],
        'Confidentialité' => [
            'panneau.opacite' => 'Preuve d’opacité',
            'panneau.consultation' => 'Consultation des copies',
        ],
    ];
    $superadmin = auth()->user()?->superadmin === true;
@endphp
<a class="aller-au-contenu" href="#contenu">Aller au contenu</a>
<div class="coque">
    <div class="barre-haut">
        <button type="button" data-menu-bouton aria-controls="barre" aria-expanded="false" aria-label="Menu">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M3 5h14M3 10h14M3 15h14"/></svg>
            <span>Menu</span>
        </button>
        <strong>SIGH-CNT · Relais</strong>
    </div>
    <div class="voile" data-voile></div>
    <aside class="barre" id="barre" data-barre>
        <div class="marque"><strong>SIGH-CNT</strong><span>Relais en ligne</span></div>
        <nav aria-label="Navigation du panneau">
            @if($superadmin)
                @foreach($groupes as $nomGroupe => $entrees)
                    <p class="groupe" id="groupe-{{ $loop->index }}">{{ $nomGroupe }}</p>
                    <ul aria-labelledby="groupe-{{ $loop->index }}">
                        @foreach($entrees as $route => $libelle)
                            <li><a href="{{ route($route) }}" @if(request()->routeIs($route)) aria-current="page" @endif>{{ $libelle }}</a></li>
                        @endforeach
                    </ul>
                @endforeach
            @endif
        </nav>
        <div class="compte">
            @if(auth()->user()?->email)<p>{{ auth()->user()->email }}</p>@endif
            <form method="post" action="{{ route('panneau.deconnexion') }}">@csrf <button type="submit">Se déconnecter</button></form>
        </div>
    </aside>
    <main id="contenu" tabindex="-1">
        {{ $slot }}
    </main>
</div>
<script>
(function () {
    var bouton = document.querySelector('[data-menu-bouton]'), barre = document.querySelector('[data-barre]'), voile = document.querySelector('[data-voile]');
    if (!bouton || !barre) { return; }
    var large = window.matchMedia('(min-width: 1024px)');
    function ouvrir(oui) {
        barre.classList.toggle('ouverte', oui); voile.classList.toggle('ouverte', oui); document.body.classList.toggle('tiroir-ouvert', oui);
        bouton.setAttribute('aria-expanded', oui ? 'true' : 'false');
        if (oui) { var premier = barre.querySelector('a'); if (premier) { premier.focus(); } } else if (barre.contains(document.activeElement)) { bouton.focus(); }
    }
    bouton.addEventListener('click', function () { ouvrir(bouton.getAttribute('aria-expanded') !== 'true'); });
    voile.addEventListener('click', function () { ouvrir(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && bouton.getAttribute('aria-expanded') === 'true') { ouvrir(false); } });
    barre.addEventListener('click', function (e) { if (e.target.closest('a')) { ouvrir(false); } });
    (large.addEventListener ? large.addEventListener.bind(large, 'change') : large.addListener.bind(large))(function () { if (large.matches) { ouvrir(false); } });
})();
</script>
@livewireScripts
</body>
</html>
