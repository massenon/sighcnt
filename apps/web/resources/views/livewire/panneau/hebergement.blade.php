<div>
    @include('livewire.panneau._entete', ['titre' => 'Hébergement', 'description' => 'Santé de l’hébergement mutualisé : PHP, base, cron, disque, certificat.', 'regle' => 'Contraintes connues : PHP 8.2 ou plus, PostgreSQL, cron toutes les minutes, pas de SSH, pas de Redis, pas de WebSocket (la mère interroge, le relais n’appelle jamais).'])
    @php $etats = ['ok' => ['OK', 'ok'], 'attention' => ['À surveiller', 'attention'], 'alerte' => ['ALERTE', 'alerte']]; @endphp
    <div class="grille">
        <div class="carte"><h2>PHP</h2><div class="valeur">{{ $php }}</div><span class="puce {{ version_compare($php, '8.2.0', '>=') ? 'ok' : 'alerte' }}">{{ version_compare($php, '8.2.0', '>=') ? 'OK' : 'ALERTE' }}</span></div>
        <div class="carte"><h2>Base</h2><div class="valeur">{{ $base }}</div></div>
        <div class="carte"><h2>Cron</h2><div class="valeur">{{ $cron }}</div><span class="puce {{ $cronEtat }}">{{ $etats[$cronEtat][0] }}</span></div>
        <div class="carte"><h2>Disque</h2><div class="valeur">{{ $disque }}</div><span class="puce {{ $disqueEtat }}">{{ $etats[$disqueEtat][0] }}</span><p>occupé</p></div>
    </div>
    <div class="carte">
        <h2>Contrôles</h2>
        <table>
            <thead><tr><th>Contrôle</th><th>État</th><th>Détail</th></tr></thead>
            <tbody>
            @foreach($controles as [$nom, $etat, $detail])
                <tr><td>{{ $nom }}</td><td><span class="puce {{ $etat }}">{{ $etats[$etat][0] }}</span></td><td>{{ $detail }}</td></tr>
            @endforeach
            </tbody>
        </table>
    </div>
</div>
