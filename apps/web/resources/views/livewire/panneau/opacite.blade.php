<div>
    @include('livewire.panneau._entete', ['titre' => 'Preuve d’opacité', 'description' => 'Ce que le relais détient et ne détient pas : la démonstration que l’hébergeur ne peut rien lire.', 'regle' => 'Le relais n’a aucun code de chiffrement ni clé. Cette page mesure l’entropie d’un échantillon de '.$mesure['echantillon'].' enveloppe(s) stockée(s) : du chiffrement de qualité approche 8 bits par octet. Le banc d’essai exige plus de 7 bits par octet sur de longues enveloppes.'])
    <div class="grille">
        <div class="carte"><h2>Clé de clinique au relais</h2><div class="valeur">{{ $cle ? 'Présente' : 'Aucune' }}</div><span class="puce {{ $cle ? 'alerte' : 'ok' }}">{{ $cle ? 'ALERTE' : 'OK' }}</span></div>
        <div class="carte"><h2>Entropie moyenne</h2><div class="valeur">{{ $mesure['entropie'] === null ? 'n/d' : number_format($mesure['entropie'], 2, ',', ' ').' bits/octet' }}</div>@if($mesure['entropie'] === null)<p>Aucune enveloppe à mesurer.</p>@endif</div>
        <div class="carte"><h2>Historique de synchronisation</h2><div class="valeur">{{ $synchro['lignes'] }}</div><span class="puce {{ $synchro['colonnes_hors_liste'] === [] && $synchro['refs_hors_liste'] === 0 ? 'ok' : 'alerte' }}">{{ $synchro['colonnes_hors_liste'] === [] && $synchro['refs_hors_liste'] === 0 ? 'OK' : 'ALERTE' }}</span><p>Compteurs et horodatages seulement : {{ count($synchro['colonnes_hors_liste']) }} colonne(s) hors liste, {{ $synchro['refs_hors_liste'] }} référence(s) hors forme.</p></div>
        <div class="carte"><h2>Noms de collection lisibles</h2><div class="valeur">{{ $mesure['lisibles'] }}</div><span class="puce {{ $mesure['lisibles'] === 0 ? 'ok' : 'alerte' }}">{{ $mesure['lisibles'] === 0 ? 'OK' : 'ALERTE' }}</span></div>
    </div>
    <div class="carte">
        <h2>Ce que le relais voit</h2>
        <table>
            <thead><tr><th>Information</th><th>Visible ?</th></tr></thead>
            <tbody>
                <tr><td>Identifiant et état de l’appareil</td><td>oui</td></tr>
                <tr><td>Sens, rang, taille, date d’une enveloppe</td><td>oui</td></tr>
                <tr><td>Indicateurs publiés par la mère (agrégats sans nom)</td><td>oui</td></tr>
                <tr><td>État de synchronisation des fileuls (compteurs et horodatages publiés par la mère)</td><td>oui</td></tr>
                <tr><td>Contenu d’une enveloppe</td><td><span class="puce ok">non (chiffré)</span></td></tr>
                <tr><td>Nom d’une collection ou d’un champ</td><td><span class="puce ok">non</span></td></tr>
                <tr><td>La clé de clinique</td><td><span class="puce ok">non</span></td></tr>
            </tbody>
        </table>
    </div>
</div>
