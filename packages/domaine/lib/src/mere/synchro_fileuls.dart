/// LOT RLS-SYNC : ce que la mère publie au relais sur la synchronisation de ses fileuls, et la LISTE BLANCHE qui l'encadre.
///
/// L'écran « Synchronisation » du panneau du relais montre un fileul par ligne. Le relais est OPAQUE et les fileuls ne lui parlent pas : c'est la mère qui publie, dans ses indicateurs de
/// battement (`POST /mere/indicateurs`, tableau `fileuls`), des COMPTEURS ET DES HORODATAGES, rien d'autre. Décision de la Direction du 13/11/2026 : jamais un identifiant de patient, un
/// nom de personne, un libellé de pièce ni un motif. Les cinq clés ci-dessous sont les seules permises, leurs types sont fermés, et la même règle est vérifiée trois fois : la mère OMET
/// ce qui sort de la liste ([synchroAssainirFileuls]), le relais REFUSE en nommant ([synchroVerifierIndicateurs]), les deux sur les mêmes vecteurs
/// (`test/vecteurs/synchro_fileuls.json`, lus aussi par le banc Node et par les tests du relais Laravel).
///
/// Le seul texte permis est le NOM TECHNIQUE du poste (l'étiquette de l'appairage) : 40 caractères au plus, lettres, chiffres, espace, point, deux-points, tiret et tiret bas. Ce jeu de
/// caractères exclut l'identifiant d'un dossier (`CNT/12/26`) et tout ce qui ressemble à une adresse ou à une phrase ponctuée ; il ne peut pas distinguer le nom d'une personne d'un nom de
/// poste, et l'étiquette est choisie par l'administrateur à l'appairage (hypothèse à confirmer, `ECARTS-MAQUETTE.md` E2558).
library;

/// Nombre maximal de fileuls publiés. Une clinique en compte quelques dizaines au plus ; au-delà, le relais refuse plutôt que d'enregistrer un tableau sans borne.
const int synchroFileulsMax = 200;

/// Les clés permises d'un fileul publié, dans l'ordre où elles sont publiées. Toute autre est refusée au relais ET omise par la mère.
const List<String> synchroClesFileul = ['poste', 'dernierContact', 'retardJournal', 'conflitsOuverts', 'demandesImportEnAttente'];

/// Les clés qui peuvent valoir `null` (valeur non calculable : jamais vu, retard inconnu). Les autres compteurs sont des entiers, toujours.
const List<String> synchroClesNullables = ['dernierContact', 'retardJournal'];

/// Le nom technique d'un poste. `À-ÿ` : les lettres accentuées du français.
final RegExp synchroPosteTechnique = RegExp(r'^[A-Za-z0-9À-ÿ][A-Za-z0-9À-ÿ _.:-]{0,39}$');
final RegExp _cleSure = RegExp(r'^[a-z][A-Za-z0-9_]{0,39}$');

/// Un refus du relais, nommé : code, motif lisible, geste de correction, chemin de la valeur en cause (jamais la valeur recopiée).
class RefusSynchro {
  const RefusSynchro(this.code, this.motif, this.geste, this.chemin);
  final String code, motif, geste, chemin;
}

bool _entier(Object? v) => v is int && v >= 0;

/// Vérifie la partie « synchronisation » d'un envoi d'indicateurs : le tableau `fileuls` et la version `protocole`. Les autres clés de l'envoi (les compteurs anciens) ne sont pas jugées ici.
/// Rend `null` si tout est permis, sinon le PREMIER refus.
RefusSynchro? synchroVerifierIndicateurs(Map<String, Object?> indicateurs) {
  if (indicateurs.containsKey('protocole')) {
    final p = indicateurs['protocole'];
    if (p is! int || p < 1 || p > 9999) {
      return const RefusSynchro('indicateur_valeur_invalide', 'La version du protocole est un entier de 1 à 9999.', 'Publier un entier, ou ne rien publier.', 'protocole');
    }
  }
  if (!indicateurs.containsKey('fileuls')) return null;
  final liste = indicateurs['fileuls'];
  if (liste is! List || liste.length > synchroFileulsMax) {
    return RefusSynchro('indicateur_forme_invalide', 'fileuls doit être une liste de $synchroFileulsMax éléments au plus.', 'Publier un tableau d\'objets de cinq clés permises.', 'fileuls');
  }
  for (var i = 0; i < liste.length; i++) {
    final f = liste[i];
    if (f is! Map) {
      return RefusSynchro('indicateur_forme_invalide', 'Chaque élément de fileuls doit être un objet.', 'Publier un objet par fileul.', 'fileuls[$i]');
    }
    for (final cle in f.keys) {
      if (!synchroClesFileul.contains(cle)) {
        final nom = cle is String && _cleSure.hasMatch(cle) ? cle : '(cle non conforme)';
        return RefusSynchro('indicateur_cle_inconnue', 'La clé « ${nom == '(cle non conforme)' ? 'non conforme' : nom} » n\'est pas permise : seuls un nom de poste, des compteurs et des horodatages sont publiés.',
            'Retirer la clé ; les clés permises sont ${synchroClesFileul.join(', ')}.', 'fileuls[$i].$nom');
      }
    }
    final poste = f['poste'];
    if (poste is! String || !synchroPosteTechnique.hasMatch(poste)) {
      return RefusSynchro('indicateur_valeur_invalide', 'Le nom du poste est absent ou n\'est pas un nom technique (40 caractères, lettres, chiffres, espace, point, deux-points, tiret).',
          'Publier l\'étiquette de l\'appairage du poste.', 'fileuls[$i].poste');
    }
    for (final cle in synchroClesFileul.skip(1)) {
      if (!f.containsKey(cle)) continue;
      final v = f[cle];
      if (v == null && synchroClesNullables.contains(cle)) continue;
      if (!_entier(v)) {
        return RefusSynchro('indicateur_valeur_invalide', 'La valeur de $cle doit être un entier positif ou nul${synchroClesNullables.contains(cle) ? ' (ou null quand elle n\'est pas calculable)' : ''}.',
            'Publier un compteur numérique.', 'fileuls[$i].$cle');
      }
    }
  }
  return null;
}

/// Le nom technique publié d'un poste : son étiquette d'appairage rognée et tronquée à 40 caractères ; à défaut (absente, vide, hors du jeu de caractères permis), le début de son identifiant d'appareil.
String synchroNomPoste(String? etiquette, String uuid) {
  var e = (etiquette ?? '').trim();
  if (e.length > 40) e = e.substring(0, 40).trimRight();
  if (e.isNotEmpty && synchroPosteTechnique.hasMatch(e)) return e;
  final repli = 'Poste ${uuid.length > 8 ? uuid.substring(0, 8) : uuid}';
  return synchroPosteTechnique.hasMatch(repli) ? repli : 'Poste inconnu';
}

/// Ce que la mère publie d'un fileul : compteurs et horodatages seulement. `dernierContact` est `null` tant que la mère n'a jamais vu le poste, et le retard de journal l'est alors aussi
/// (un retard n'est pas calculable sans curseur connu : « non calculable » n'est pas zéro). Un curseur en avance sur la mère se ramène à zéro.
Map<String, Object?> synchroFileulPublie({
  required String? etiquette,
  required String uuid,
  required int? dernierContact,
  required int dernierSeq,
  required int seqMax,
  required int conflitsOuverts,
  required int demandesEnAttente,
}) =>
    {
      'poste': synchroNomPoste(etiquette, uuid),
      'dernierContact': dernierContact,
      'retardJournal': dernierContact == null ? null : (seqMax - dernierSeq < 0 ? 0 : seqMax - dernierSeq),
      'conflitsOuverts': conflitsOuverts,
      'demandesImportEnAttente': demandesEnAttente,
    };

/// Dernière barrière côté mère : ne laisse sortir que la liste blanche. Une clé hors liste ou une valeur invalide est OMISE (jamais publiée), un fileul sans nom technique valide est écarté,
/// ce qui n'est pas une liste donne une liste vide, au plus [synchroFileulsMax] éléments.
List<Map<String, Object?>> synchroAssainirFileuls(Object? brut) {
  if (brut is! List) return const [];
  final out = <Map<String, Object?>>[];
  for (final f in brut) {
    if (out.length >= synchroFileulsMax) break;
    if (f is! Map) continue;
    final poste = f['poste'];
    if (poste is! String || !synchroPosteTechnique.hasMatch(poste)) continue;
    final propre = <String, Object?>{'poste': poste};
    for (final cle in synchroClesFileul.skip(1)) {
      if (!f.containsKey(cle)) continue;
      final v = f[cle];
      if (v == null && synchroClesNullables.contains(cle)) {
        propre[cle] = null;
      } else if (_entier(v)) {
        propre[cle] = v;
      }
    }
    out.add(propre);
  }
  return out;
}
