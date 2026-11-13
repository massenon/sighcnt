<div>
    @include('livewire.panneau._entete', ['titre' => 'Synchronisation', 'description' => 'La mère, ses fileuls et les mobiles : dernier contact, retard, boîtes en attente. Lecture seule.', 'regle' => 'Des compteurs et des horodatages, jamais un identifiant de patient, un nom, un libellé de pièce ni un motif. Les fileuls parlent à la mère sur le réseau local : c’est elle qui publie leur état. Les mobiles passent par le relais, qui voit leurs dépôts et leurs relèves. Une valeur que personne n’a publiée se lit « non publié », jamais zéro. Les seuils se règlent dans « Paramètres du relais ».'])
    <div class="grille">
        <div class="carte">
            <h2>Mère</h2>
            <div class="valeur"><span class="puce {{ \App\Relais\Synchro\Etat::ton($mere['etat']) }}">{{ \App\Relais\Synchro\Etat::libelle($mere['etat'], 'f') }}</span></div>
            <p>Dernier battement : {{ $mere['battement'] === null ? 'non publié' : \App\Relais\Format::depuis($mere['battement']) }}</p>
            <p>Numéro de séquence : {{ $mere['seq'] === null ? 'non publié' : number_format($mere['seq'], 0, ',', ' ') }}</p>
            <p>Version du protocole : {{ $mere['protocole'] === null ? 'non publié' : $mere['protocole'] }}</p>
            <p class="note">En retard au-delà de {{ $reglages['mere_en_retard_min'] }} min, silencieuse au-delà de {{ $reglages['mere_silencieuse_min'] }} min (réglages à valider).</p>
        </div>
    </div>
    <div class="carte">
        <h2>Fileuls</h2>
        @if($fileuls === null)
            <p class="vide">Non publié : la mère n’a encore rien publié sur ses fileuls.</p>
        @elseif($fileuls === [])
            <p class="vide">Aucun fileul actif déclaré par la mère.</p>
        @else
            @if($mereMuette)<p class="note">La mère ne publie plus : l’état de ses fileuls n’est pas établi. Voir l’alerte de battement.</p>@endif
            <table>
                <thead><tr><th>Poste</th><th>État</th><th>Dernier contact</th><th class="num">Retard de journal</th><th class="num">Conflits ouverts</th><th class="num">Demandes d’import</th></tr></thead>
                <tbody>
                @foreach($fileuls as $f)
                    <tr wire:key="fileul-{{ $loop->index }}">
                        <td>{{ $f['poste'] }}</td>
                        <td><span class="puce {{ \App\Relais\Synchro\Etat::ton($f['etat']) }}">{{ \App\Relais\Synchro\Etat::libelle($f['etat']) }}</span></td>
                        <td>{{ $f['dernier_contact'] === null ? 'jamais vu' : \App\Relais\Format::depuis($f['dernier_contact']) }}</td>
                        <td class="num">{{ $f['retard_journal'] === null ? 'non publié' : $f['retard_journal'] }}</td>
                        <td class="num">{{ $f['conflits'] === null ? 'non publié' : $f['conflits'] }}</td>
                        <td class="num">{{ $f['demandes'] === null ? 'non publié' : $f['demandes'] }}</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
            <p class="note">En retard au-delà de {{ $reglages['fileul_en_retard_min'] }} min ou de {{ $reglages['fileul_retard_journal'] }} opérations, silencieux au-delà de {{ $reglages['fileul_silencieux_min'] }} min (réglages à valider).</p>
        @endif
    </div>
    <div class="carte">
        <h2>Mobiles</h2>
        @if($mobiles === [])
            <p class="vide">Aucun mobile appairé.</p>
        @else
            <table>
                <thead><tr><th>Mobile</th><th>Fonction</th><th>État</th><th>Dernier dépôt</th><th>Dernière relève</th><th class="num">Enveloppes en attente</th></tr></thead>
                <tbody>
                @foreach($mobiles as $m)
                    <tr wire:key="mobile-{{ $m['uuid'] }}">
                        <td>Mobile {{ \Illuminate\Support\Str::limit($m['uuid'], 8, '') }}</td>
                        <td>{{ \App\Relais\Synchro\Etat::fonction($m['profil'], $m['fonction']) }}</td>
                        <td><span class="puce {{ \App\Relais\Synchro\Etat::ton($m['etat']) }}">{{ \App\Relais\Synchro\Etat::libelle($m['etat']) }}</span></td>
                        <td>{{ $m['dernier_depot'] === null ? 'jamais' : \App\Relais\Format::depuis($m['dernier_depot']) }}</td>
                        <td>{{ $m['dernier_releve'] === null ? 'jamais' : \App\Relais\Format::depuis($m['dernier_releve']) }}</td>
                        <td class="num">{{ $m['attente'] }}</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
            <p class="note">En retard au-delà de {{ $reglages['mobile_en_retard_min'] }} min, silencieux au-delà de {{ $reglages['mobile_silencieux_min'] }} min, boîte qui grossit au-delà de {{ $reglages['boite_enveloppes_max'] }} enveloppes (réglages à valider). Les enveloppes en attente sont celles que le mobile n’a pas encore relevées.</p>
        @endif
    </div>
    <div class="carte">
        <h2>Historique</h2>
        <p class="note">Conservé {{ $reglages['conservation_jours'] }} jours, un relevé toutes les {{ $reglages['echantillon_minutes'] }} min ({{ $total }} relevé(s) conservé(s)). Durée et intervalle se règlent dans « Paramètres du relais » (à valider).</p>
        <label>Période
            <select wire:model.live="periode" aria-label="Période de l’historique">
                @foreach($periodes as $cle => [$libelle])<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
            </select>
        </label>
        <label>Appareils
            <select wire:model.live="nature" aria-label="Nature des appareils">
                @foreach($natures as $cle => $libelle)<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
            </select>
        </label>
        @if($resume->isEmpty())
            <p class="vide">Aucun relevé sur la période choisie.</p>
        @else
            <table>
                <thead><tr><th>Appareil</th><th>Nature</th><th class="num">Relevés</th><th class="num">Silence maximal</th><th class="num">Retard de journal maximal</th><th class="num">Enveloppes en attente (maximum)</th></tr></thead>
                <tbody>
                @foreach($resume as $l)
                    <tr wire:key="resume-{{ $l->nature }}-{{ $l->ref }}">
                        <td>{{ $l->nature === 'mobile' ? 'Mobile '.\Illuminate\Support\Str::limit($l->ref, 8, '') : $l->ref }}</td>
                        <td>{{ $natures[$l->nature] ?? $l->nature }}</td>
                        <td class="num">{{ $l->releves }}</td>
                        <td class="num">{{ $l->silence_max === null ? 'non publié' : \App\Relais\Format::duree((int) $l->silence_max) }}</td>
                        <td class="num">{{ $l->retard_max === null ? 'non publié' : $l->retard_max }}</td>
                        <td class="num">{{ $l->attente_max === null ? 'non publié' : $l->attente_max }}</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
            <h3>Derniers relevés</h3>
            <table>
                <thead><tr><th>Heure</th><th>Appareil</th><th class="num">Silence</th><th class="num">Retard de journal</th><th class="num">Enveloppes en attente</th></tr></thead>
                <tbody>
                @foreach($releves as $h)
                    <tr wire:key="releve-{{ $h->id }}">
                        <td>{{ \App\Relais\Format::date((int) $h->quand) }}</td>
                        <td>{{ $h->nature === 'mobile' ? 'Mobile '.\Illuminate\Support\Str::limit($h->ref, 8, '') : $h->ref }}</td>
                        <td class="num">{{ $h->dernier_contact === null ? 'jamais vu' : \App\Relais\Format::duree(max(0, (int) $h->quand - (int) $h->dernier_contact)) }}</td>
                        <td class="num">{{ $h->retard_journal === null ? 'non publié' : $h->retard_journal }}</td>
                        <td class="num">{{ $h->attente === null ? 'non publié' : $h->attente }}</td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        @endif
    </div>
</div>
