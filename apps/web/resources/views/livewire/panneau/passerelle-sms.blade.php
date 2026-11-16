<div>
    @include('livewire.panneau._entete', ['titre' => 'Passerelle SMS', 'description' => 'Envois automatiques déposés par le poste mère, envoyés par la tâche planifiée du relais.', 'regle' => 'Le relais voit un SMS seulement le temps de l’envoi : numéro, texte, heure, type et un identifiant opaque. Puis il efface le clair. Les identifiants du fournisseur se posent dans le .env, jamais ici.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    <div class="grille">
        <div class="carte"><h2>Fournisseur</h2><div class="valeur">{{ $etat['fournisseur'] !== '' ? ucfirst($etat['fournisseur']) : 'Non choisi' }}</div><p>Identifiants : {{ $etat['identifiantsDefinis'] ? 'défini' : 'non défini' }} · Expéditeur : {{ $etat['expediteurDefini'] ? 'défini' : 'non défini' }}</p><span class="puce {{ $etat['configuree'] ? 'ok' : 'alerte' }}">{{ $etat['configuree'] ? 'PRÊTE' : 'NON CONFIGURÉE' }}</span></div>
        <div class="carte"><h2>Aujourd’hui ({{ $etat['jour'] }}, heure du Bénin)</h2><div class="valeur">{{ $etat['envoyesAujourdhui'] }} / {{ $etat['reglages']['plafond_jour'] }}</div><p>{{ $etat['plafondRestant'] }} restant(s) avant le plafond</p></div>
        <div class="carte"><h2>Envois planifiés</h2><div class="valeur">{{ $etat['planifies'] }}</div><p>{{ $etat['refusesAujourdhui'] }} refusé(s) sur 24 h</p></div>
        <div class="carte"><h2>Dernier passage de la tâche</h2><div class="valeur">{{ $etat['dernierPassage'] ? $format::depuis($etat['dernierPassage']) : 'Aucun' }}</div></div>
    </div>
    <div class="carte">
        <h2>Tester l’envoi</h2>
        <p>Envoie un message de contrôle imposé à un numéro au format international (+229...). Le résultat est nommé.</p>
        <p><label for="numero-test">Numéro</label> <input id="numero-test" type="text" wire:model="numeroTest" placeholder="+229..." autocomplete="off"> <button class="btn" type="button" wire:click="tester">Tester l’envoi</button></p>
        @if($resultatTest)
            @if($resultatTest['ok'])<p class="message" role="status">Accepté par le fournisseur (identifiant {{ $resultatTest['idFournisseur'] }}).</p>
            @else<p class="refus" role="alert"><strong>{{ $resultatTest['code'] }}</strong> : {{ $resultatTest['motif'] }} {{ $resultatTest['geste'] }}</p>@endif
        @endif
    </div>
    <div class="carte">
        <h2>Envois planifiés</h2>
        @if($planifies->isEmpty())<p class="vide">Aucun envoi planifié.</p>
        @else
            <table><thead><tr><th>Heure d’envoi</th><th>Type</th><th>Numéro</th><th class="num">Tentatives</th></tr></thead>
            <tbody>@foreach($planifies as $p)<tr><td>{{ $format::date((int) $p->heure_envoi) }}</td><td>{{ $p->type }}</td><td>{{ $p->numero_masque }}</td><td class="num">{{ $p->tentatives }}</td></tr>@endforeach</tbody></table>
        @endif
    </div>
    <div class="carte">
        <h2>Journal des envois</h2>
        @if(count($journal) === 0)<p class="vide">Aucun envoi.</p>
        @else
            <table><thead><tr><th>Mis à jour</th><th>Type</th><th>Numéro</th><th>État</th><th>Code</th></tr></thead>
            <tbody>@foreach($journal as $j)<tr><td>{{ $format::date($j['maj']) }}</td><td>{{ $j['type'] }}</td><td>{{ $j['numeroMasque'] }}</td><td>{{ $j['etat'] }}</td><td>{{ $j['code'] }}</td></tr>@endforeach</tbody></table>
        @endif
        <p class="note">Le journal ne garde ni le numéro en clair ni le texte.</p>
    </div>
    <div class="carte">
        <h2>Limites</h2>
        @if($limitesRefus)<ul class="refus" role="alert">@foreach($limitesRefus as $r)<li>{{ $r }}</li>@endforeach</ul>@endif
        <table><thead><tr><th>Limite</th><th>Valeur</th></tr></thead>
        <tbody>@foreach($defauts as $cle => $d)<tr><td><label for="limite-sms-{{ $cle }}">{{ $d['libelle'] }}</label></td><td><input id="limite-sms-{{ $cle }}" type="number" wire:model="limites.{{ $cle }}" min="{{ $d['min'] }}" max="{{ $d['max'] }}" step="1"> {{ $d['unite'] }} <small>(de {{ $d['min'] }} à {{ $d['max'] }})</small></td></tr>@endforeach</tbody></table>
        <p><button class="btn" type="button" wire:click="enregistrerLimites">Enregistrer les limites</button></p>
    </div>
    <div class="carte">
        <h2>Ce que le relais ne voit jamais</h2>
        <ul>
            <li>l’annuaire des patients ou du personnel ;</li>
            <li>une date de naissance ;</li>
            <li>un code de patient ou de dossier ;</li>
            <li>un rendez-vous, un médecin, un service, un motif ;</li>
            <li>une donnée de santé (le texte des messages n’en contient aucune : la règle est appliquée au poste mère).</li>
        </ul>
        <p class="note">L’identifiant de chaque message est une empreinte calculée à la mère avec la clé de la clinique, que le relais ne détient pas : il ne peut pas la relier à une personne.</p>
    </div>
</div>
