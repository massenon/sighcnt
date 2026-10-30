/// POSTE D'IMAGERIE MÉDICALE — états des demandes et modalités, tels que la maquette les déclare
/// (`m2-consultations.js` : `ETATS_IMAGERIE` ; `data-imagerie.js` : `D.IMAGERIE.MODALITES`).
///
/// L'imagerie suit LES MÊMES ÉTATS que le laboratoire : demandée (la balle est à la caisse) → payée (exécutable) → exécutée (CR saisi) →
/// validée (CR rendu au prescripteur). Un état ne se déduit jamais d'un autre champ : il est écrit par le geste qui le fait naître.
library;

/// Un état du circuit : identifiant écrit au magasin, libellé affiché, ton du badge (`success`, `warning`, `info`, `navy`, `neutral`).
class EtatImagerie {
  const EtatImagerie(this.id, this.libelle, this.ton);
  final String id;
  final String libelle;
  final String ton;
}

const etatsImagerie = <EtatImagerie>[
  EtatImagerie('demandee', 'Demandée — attente caisse', 'warning'),
  EtatImagerie('payee', 'Payée — à exécuter', 'info'),
  EtatImagerie('executee', 'Exécutée — CR en rédaction', 'navy'),
  EtatImagerie('validee', 'Validée — CR rendu', 'success'),
];

/// `etatImagerie(id)` : un état inconnu s'affiche sous son identifiant, en ton neutre (jamais un libellé inventé).
EtatImagerie etatImagerie(Object? id) =>
    etatsImagerie.where((e) => e.id == id).firstOrNull ??
    EtatImagerie('$id', '$id', 'neutral');

/// Une modalité d'imagerie : l'écran de son tableau et l'icône Lucide de son pictogramme.
class ModaliteImagerie {
  const ModaliteImagerie(this.code, this.libelle, this.ecran, this.icone);
  final String code;
  final String libelle;
  final String ecran;
  final String icone;
}

/// Les cinq modalités (`D.IMAGERIE.MODALITES`) : UN socle, cinq modalités — la modalité est une PROPRIÉTÉ DE L'EXAMEN, lue au catalogue.
const modalitesImagerie = <ModaliteImagerie>[
  ModaliteImagerie('echographie', 'Échographie', 'm2-imagerie', 'scan-line'),
  ModaliteImagerie(
      'radiographie', 'Radiographie', 'm2-imagerie-radiographie', 'bone'),
  ModaliteImagerie(
      'mammographie', 'Mammographie', 'm2-imagerie-mammographie', 'ribbon'),
  ModaliteImagerie('scanner', 'Scanner', 'm2-imagerie-scanner', 'radiation'),
  ModaliteImagerie('irm', 'IRM — imagerie par résonance magnétique',
      'm2-imagerie-irm', 'magnet'),
];

/// `imModalite(code)` : une modalité inconnue s'affiche sous son code.
ModaliteImagerie modaliteImagerie(String code) =>
    modalitesImagerie.where((m) => m.code == code).firstOrNull ??
    ModaliteImagerie(code, code, '', 'scan-line');

/// `imModaliteDe(codeExamen)` : la modalité se lit au CATALOGUE (`examensImagerie`) ; un examen sans modalité déclarée — ou absent du
/// catalogue — reste à l'échographie, où il était saisi avant la vague 61.
String modaliteDeExamen(
    Iterable<Map<String, Object?>> catalogue, Object? codeExamen) {
  for (final x in catalogue) {
    if (x['statut'] == 'archive' || x['code'] != codeExamen) continue;
    final m = x['modalite'];
    return (m == null || m == '') ? 'echographie' : '$m';
  }
  return 'echographie';
}
