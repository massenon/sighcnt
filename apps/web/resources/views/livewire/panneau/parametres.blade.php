<div>
    @include('livewire.panneau._entete', ['titre' => 'Paramètres du relais', 'description' => 'Secret de la mère, seuil de battement, rétention de l’audit, crochets du banc d’essai (fermés).', 'regle' => 'Le secret de la mère se pose dans le .env du relais (jamais en base). Les crochets du banc d’essai sont fermés en production.'])
    <div class="carte">
        <h2>Paramètres</h2>
        <table>
            <thead><tr><th>Paramètre</th><th>Valeur</th><th>Où</th></tr></thead>
            <tbody>
                <tr><td>Seuil de battement</td><td>{{ $seuil }} min</td><td><code>RELAIS_SEUIL_BATTEMENT_MS</code></td></tr>
                <tr><td>Secret de la mère</td><td>@if($secretDefini)•••••••• (défini, non affichable)@else<span class="puce alerte">Non défini</span>@endif</td><td><code>RELAIS_SECRET_MERE</code></td></tr>
                <tr><td>Rétention de l’audit</td><td>{{ $retention }} jours</td><td><code>RELAIS_RETENTION_AUDIT_JOURS</code>, commande <code>relais:purger</code></td></tr>
                <tr><td>Espace disque minimal</td><td>{{ $disque }} %</td><td><code>RELAIS_SEUIL_DISQUE_PCT</code></td></tr>
                <tr><td>Crochets du banc</td><td><span class="puce {{ $banc ? 'alerte' : 'ok' }}">{{ $banc ? 'OUVERTS' : 'Fermés' }}</span></td><td><code>RELAIS_BANC={{ $banc ? 'true' : 'false' }}</code></td></tr>
            </tbody>
        </table>
    </div>
    <p class="note">Faire tourner le secret : le changer dans le .env du relais <strong>et</strong> dans la configuration de la mère, dans la même minute.</p>
</div>
