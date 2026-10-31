<div>
    @include('livewire.panneau._entete', ['titre' => 'Codes d’appairage', 'description' => 'Codes à usage unique créés par la mère : ils expirent, ne servent qu’une fois, ne sont jamais conservés en clair.', 'regle' => 'Le relais ne stocke que l’empreinte d’un code. Un code utilisé est refusé. L’expiration est tenue par la mère (elle ne déclare un code que pour la durée qu’elle fixe) : le relais n’en applique aucune de son côté.'])
    <div class="grille">
        <div class="carte"><h2>Codes valides</h2><div class="valeur">{{ $valides }}</div></div>
        <div class="carte"><h2>Utilisés (30 j)</h2><div class="valeur">{{ $utilises }}</div></div>
        <div class="carte"><h2>Expirés</h2><div class="valeur">{{ $expires }}</div></div>
    </div>
    <div class="carte">
        <h2>Codes</h2>
        @if($codes->isEmpty())
            <p class="vide">Aucun code déclaré.</p>
        @else
            <table>
                <thead><tr><th>Empreinte</th><th>Créé</th><th>Expire</th><th>État</th></tr></thead>
                <tbody>
                @foreach($codes as $c)
                    <tr>
                        <td><code>{{ substr($c->hash, 0, 4) }}…{{ substr($c->hash, -4) }}</code></td>
                        <td>{{ $c->cree ? \App\Relais\Format::depuis((int) $c->cree) : 'avant le suivi' }}</td>
                        <td>pas de limite au relais</td>
                        <td><span class="puce {{ $c->utilise ? 'ok' : 'attention' }}">{{ $c->utilise ? 'Utilisé' : 'Valide' }}</span></td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
</div>
