<div>
    @include('livewire.panneau._entete', ['titre' => 'Sauvegarde du relais', 'description' => 'Export de la base du relais avant toute migration ; le journal chiffré qu’elle contient sert à restaurer la mère.', 'regle' => 'Avant chaque migrate : export de la base (commande relais:exporter --avant-migration, par cron). Le contenu est déjà chiffré : un export ne contient aucune donnée lisible. Les fichiers sont déposés dans storage/app/exports.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    <div class="grille">
        <div class="carte"><h2>Dernier export</h2><div class="valeur">{{ $dernier ? \App\Relais\Format::depuis((int) $dernier->quand) : 'Aucun' }}</div></div>
        <div class="carte"><h2>Taille</h2><div class="valeur">{{ $dernier ? \App\Relais\Format::taille((int) $dernier->taille) : 'n/d' }}</div></div>
    </div>
    <div class="carte">
        <h2>Exports</h2>
        @if($exports->isEmpty())
            <p class="vide">Aucun export.</p>
        @else
            <div class="defile" role="region" tabindex="0" aria-label="Tableau défilant"><table>
                <thead><tr><th>Date</th><th class="num">Taille</th><th>Avant migration</th></tr></thead>
                <tbody>@foreach($exports as $e)<tr><td>{{ \App\Relais\Format::date((int) $e->quand) }}</td><td class="num">{{ \App\Relais\Format::taille((int) $e->taille) }}</td><td>{{ $e->avant_migration ? 'oui' : 'non' }}</td></tr>@endforeach</tbody>
            </table></div>
        @endif
    </div>
    <p><button class="btn" type="button" wire:click="exporter" wire:loading.attr="disabled">Exporter maintenant</button></p>
    <p class="note">Cet export contient les enveloppes du journal, les appareils, les réglages et l’audit. Il <strong>n’embarque PAS les blocs des copies hors site</strong> (ni les tables qui les décrivent, inutiles sans eux) : ils sont déjà des copies, chiffrées, sur le disque du relais (<code>storage/app/sauvegardes</code>).</p>
    <div class="carte" id="hors-site">
        <h2>Sauvegardes hors site</h2>
        <p>Copies chiffrées de la base de la mère et des fichiers numérisés, déposées par le poste mère en blocs opaques. Le relais ne voit que des identifiants, des tailles, des dates et des compteurs : jamais un contenu, jamais la clé de la clinique.</p>
        <div class="grille">
            <div class="carte"><h2>Espace utilisé</h2><div class="valeur">{{ \App\Relais\Format::taille($horsSite['utilise']) }}</div><p>sur {{ \App\Relais\Format::taille($horsSite['quota']) }} ({{ $horsSite['pct'] === null ? 'n/d' : number_format($horsSite['pct'], 1, ',', ' ').' %' }})</p><span class="puce {{ ($horsSite['pct'] ?? 0) >= 90 ? 'alerte' : (($horsSite['pct'] ?? 0) >= 75 ? 'attention' : 'ok') }}">{{ ($horsSite['pct'] ?? 0) >= 90 ? 'ESPACE FAIBLE' : (($horsSite['pct'] ?? 0) >= 75 ? 'À SURVEILLER' : 'OK') }}</span></div>
            <div class="carte"><h2>Libérable sans toucher une copie courante</h2><div class="valeur">{{ \App\Relais\Format::taille($horsSite['liberable']) }}</div><p>{{ $horsSite['nb_blocs'] }} bloc(s) au total</p></div>
        </div>
        <div class="defile" role="region" tabindex="0" aria-label="Tableau défilant"><table>
            <thead><tr><th>Type</th><th class="num">Courantes</th><th class="num">Archivées</th><th class="num">Purgées</th><th>Dernière copie</th><th class="num">Taille</th><th class="num">Blocs</th></tr></thead>
            <tbody>
            @foreach(['magasin' => 'Magasin (base de la mère)', 'fichiers' => 'Fichiers numérisés'] as $t => $lib)
                @php($c = $horsSite['copies'][$t])
                <tr><td>{{ $lib }}</td><td class="num">{{ $c['completes'] }}</td><td class="num">{{ $c['archivees'] }}</td><td class="num">{{ $c['purgees'] }}</td><td>{{ $c['derniere'] ? \App\Relais\Format::depuis($c['derniere']['date']) : 'aucune' }}</td><td class="num">{{ $c['derniere'] ? \App\Relais\Format::taille($c['derniere']['taille']) : 'n/d' }}</td><td class="num">{{ $c['derniere'] ? $c['derniere']['nb_blocs'] : 'n/d' }}</td></tr>
            @endforeach
            </tbody>
        </table></div>
        <p class="note">Une copie <strong>archivée</strong> reste restaurable ; elle n’est <strong>purgée</strong> (supprimée, sa ligne gardée) que si l’espace manque, la plus ancienne d’abord, jamais l’une des copies courantes ni l’une des {{ $horsSite['limites']['rotationPlancher'] }} plus récentes. Quand même cela ne suffit pas, le dépôt est refusé en le disant (ESPACE_RELAIS_INSUFFISANT) : rien d’actuel n’est détruit.</p>
        @if($limitesRefus)<ul class="refus" role="alert">@foreach($limitesRefus as $r)<li>{{ $r }}</li>@endforeach</ul>@endif
        <div class="defile" role="region" tabindex="0" aria-label="Tableau défilant"><table>
            <thead><tr><th>Limite</th><th>Valeur</th></tr></thead>
            <tbody>@foreach($defauts as $cle => $d)<tr><td><label for="limite-{{ $cle }}">{{ $d['libelle'] }}</label></td><td><input id="limite-{{ $cle }}" type="number" wire:model="limites.{{ $cle }}" min="{{ $d['min'] }}" max="{{ $d['max'] }}" step="1"> {{ $d['unite'] }} <small>(de {{ $d['min'] }} à {{ $d['max'] }})</small></td></tr>@endforeach</tbody>
        </table></div>
        <p><button class="btn" type="button" wire:click="enregistrerLimites">Enregistrer les limites</button></p>
    </div>
</div>
