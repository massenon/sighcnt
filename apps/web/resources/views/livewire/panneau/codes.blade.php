<div>
    @include('livewire.panneau._entete', ['titre' => 'Codes d’appairage', 'description' => 'Codes à usage unique créés par la mère : ils expirent, ne servent qu’une fois, ne sont jamais conservés en clair.', 'regle' => 'Le relais ne stocke que l’empreinte d’un code, et le profil et la fonction que la mère y a attachés, à titre d’étiquette : la fonction du soignant est fixée et relue par la mère, jamais par le relais. Un code utilisé est refusé. Un code expire : la mère déclare son échéance (15 minutes) et le relais refuse un code échu.'])
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
                <thead><tr><th>Empreinte</th><th>Destiné à</th><th>Créé</th><th>Expire</th><th>État</th></tr></thead>
                <tbody>
                @foreach($codes as $c)
                    <tr>
                        <td><code>{{ substr($c->hash, 0, 4) }}…{{ substr($c->hash, -4) }}</code></td>
                        <td>{{ $c->profil ? ($c->profil === 'reception' ? 'Réception de secours' : 'Soignant'.($c->fonction ? ' · '.str_replace('_', ' ', $c->fonction) : '')) : 'non précisé' }}</td>
                        <td>{{ $c->cree ? \App\Relais\Format::depuis((int) $c->cree) : 'avant le suivi' }}</td>
                        <td>{{ $c->expire_le ? \App\Relais\Format::date((int) $c->expire_le) : 'avant la règle d’expiration' }}</td>
                        <td>@php($expire = ! $c->utilise && $c->expire_le && (int) $c->expire_le < \App\Relais\Format::maintenant())
                        <span class="puce {{ $c->utilise ? 'ok' : ($expire ? 'alerte' : 'attention') }}">{{ $c->utilise ? 'Utilisé' : ($expire ? 'Expiré' : 'Valide') }}</span></td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
</div>
