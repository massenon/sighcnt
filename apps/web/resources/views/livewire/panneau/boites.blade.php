<div>
    @include('livewire.panneau._entete', ['titre' => 'Boîtes aux lettres', 'description' => 'Pour chaque mobile : enveloppes déposées par la mère, enveloppes envoyées par le mobile, rangs, tailles.', 'regle' => 'Chaque boîte est une suite contiguë (appareil, sens, rang). Un trou est détecté par la mère et bloque l’appareil : le relais ne supprime donc jamais une enveloppe seul.'])
    <div class="grille">
        <div class="carte"><h2>Boîtes</h2><div class="valeur">{{ $boites->count() }}</div></div>
        <div class="carte"><h2>Vers les mobiles</h2><div class="valeur">{{ $vers }}</div></div>
        <div class="carte"><h2>Depuis les mobiles</h2><div class="valeur">{{ $depuis }}</div></div>
    </div>
    <div class="carte">
        <h2>Boîtes</h2>
        @if($boites->isEmpty())
            <p class="vide">Aucune boîte.</p>
        @else
            <table>
                <thead><tr><th>Mobile</th><th class="num">Vers le mobile</th><th class="num">Depuis le mobile</th><th class="num">Dernier rang reçu</th><th class="num">Taille</th><th>Plus ancienne</th></tr></thead>
                <tbody>
                @foreach($boites as $b)
                    <tr>
                        <td><code title="{{ $b->appareil }}">{{ \Illuminate\Support\Str::limit($b->appareil, 13, '…') }}</code></td>
                        <td class="num">{{ (int) $b->vers }}</td><td class="num">{{ (int) $b->depuis }}</td>
                        <td class="num">{{ (int) $b->rang }}</td>
                        <td class="num">{{ \App\Relais\Format::taille((int) $b->taille) }}</td>
                        <td>{{ \App\Relais\Format::depuis((int) $b->ancienne) }}</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
</div>
