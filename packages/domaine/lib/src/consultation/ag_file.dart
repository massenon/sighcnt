/// Accueil M2 — la file d'attente par poste, l'écran d'appel et la file par cabinet.
///
/// L'ordre d'ARRIVÉE gouverne, SAUF urgence. Le rang est CALCULÉ, jamais saisi : faire passer un patient devant se fait en changeant sa priorité,
/// avec un motif, ce qui est tracé. Deux listes par cabinet, jamais fondues : ceux qui attendent NOMMÉMENT un praticien, et le vivier commun.
library;

import '../format/format_fr.dart';
import 'ag_commun.dart';

/// Une priorité de triage (rang 1 = la plus pressante).
class AgPriorite {
  const AgPriorite(this.code, this.libelle, this.rang, this.ton, this.note);
  final String code;
  final String libelle;
  final int rang;
  final String ton;
  final String note;
}

const agPriorites = [
  AgPriorite('urgence_vitale', 'Urgence vitale', 1, 'danger',
      'Prise en charge immédiate, avant tout autre patient.'),
  AgPriorite('urgence', 'Urgence', 2, 'warning',
      'Passe devant les consultations programmées et les arrivées libres.'),
  AgPriorite('rdv', 'Sur rendez-vous', 3, 'info',
      'Le rendez-vous a réservé une plage : il prime sur l’arrivée libre.'),
  AgPriorite('ordre_arrivee', 'Par ordre d’arrivée', 4, 'neutral',
      'Le cas courant — la sage-femme reçoit par ordre d’arrivée.'),
];

/// Une priorité inconnue retombe sur « par ordre d'arrivée ».
AgPriorite agPriorite(Object? code) =>
    agPriorites.firstWhere((p) => p.code == code, orElse: () => agPriorites[3]);

/// Les postes de la file.
const agPostes = [
  ('accueil', 'Accueil'),
  ('consultation', 'Consultation'),
  ('caisse', 'Caisse'),
  ('prelevement', 'Salle de prélèvement'),
  ('pharmacie', 'Pharmacie'),
  ('salle_soins', 'Salle de soins'),
  ('imagerie', 'Imagerie médicale'),
];

String agLibellePoste(String code) {
  for (final p in agPostes) {
    if (p.$1 == code) return p.$2;
  }
  return code;
}

bool _actif(AgFiche t) => t['statut'] != 'archive';

/// Le classement, écrit UNE fois : l'écran de gestion et l'écran d'appel affichent le même ordre. Priorité d'abord, heure d'arrivée ensuite.
List<AgFiche> agFileTriee(Iterable<AgFiche> tickets, String poste) {
  final liste = [
    for (final t in tickets)
      if (_actif(t) && t['poste'] == poste && t['etat'] == 'attente') t
  ];
  final copie = [for (final (i, l) in liste.indexed) (i, l)];
  copie.sort((a, b) {
    final pa = agPriorite(a.$2['priorite']).rang, pb = agPriorite(b.$2['priorite']).rang;
    if (pa != pb) return pa - pb;
    final c = '${a.$2['arriveeLe']}'.compareTo('${b.$2['arriveeLe']}');
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in copie) e.$2];
}

/// Le temps d'attente moyen des patients déjà servis, arrondi à la minute ; « — » s'il n'y en a aucun.
String agAttenteMoyenne(Iterable<AgFiche> servis) {
  final avec = [
    for (final t in servis)
      if (agVrai(t['arriveeLe']) && agVrai(t['serviLe'])) t
  ];
  if (avec.isEmpty) return '—';
  var total = 0;
  for (final t in avec) {
    total += agDate(t['serviLe'])!.millisecondsSinceEpoch -
        agDate(t['arriveeLe'])!.millisecondsSinceEpoch;
  }
  // Math.round de JavaScript : la moitié monte.
  return '${(total / avec.length / 60000 + 0.5).floor()} min';
}

/// Les quatre indicateurs de la file (`tous` = tickets actifs).
List<AgKpi> agKpisFile(Iterable<AgFiche> tous, DateTime maintenant) {
  final actifs = [for (final t in tous) if (_actif(t)) t];
  final attente = actifs.where((t) => t['etat'] == 'attente').toList();
  final urgences = attente.where((t) => agPriorite(t['priorite']).rang <= 2).toList();
  final servis = actifs.where((t) => t['etat'] == 'servi').toList();
  final auj = iso(maintenant);
  return [
    AgKpi('Patients en attente', agNum(attente.length)),
    AgKpi('Dont urgences', agNum(urgences.length)),
    AgKpi('Servis aujourd’hui',
        agNum(servis.where((t) => agDebutTexte(t['serviLe'], 10) == auj).length)),
    AgKpi('Attente moyenne', agAttenteMoyenne(servis), indice: 'sur les patients déjà servis'),
  ];
}

/// Minutes d'attente d'un ticket à l'instant donné.
int agAttenteMinutes(AgFiche t, DateTime maintenant) {
  final a = agDate(t['arriveeLe']);
  if (a == null) return 0;
  return ((maintenant.millisecondsSinceEpoch - a.millisecondsSinceEpoch) / 60000 + 0.5).floor();
}

/// Le numéro d'appel : l'initiale du poste puis le rang du jour (trois chiffres) — il repart à 1 chaque matin comme le ticket papier. Le rang compte
/// TOUS les tickets du poste arrivés ce jour (servis et archivés compris).
String agNumeroAppel(String poste, Iterable<AgFiche> tous, DateTime maintenant) {
  final jour = iso(maintenant);
  final n = tous
          .where((t) => t['poste'] == poste && agDebutTexte(t['arriveeLe'], 10) == jour)
          .length +
      1;
  final lib = agLibellePoste(poste);
  return '${lib.isEmpty ? '' : lib.substring(0, 1).toUpperCase()}${n.toString().padLeft(3, '0')}';
}

/// L'inscription d'un patient : le praticien n'est demandé qu'en consultation et reste facultatif (vide = file commune, une information et non un oubli).
AgFiche agTicket(
    {required String poste,
    required String patientCode,
    required String priorite,
    required String motif,
    String? praticien,
    required Iterable<AgFiche> patients,
    required Iterable<AgFiche> tous,
    required DateTime maintenant}) {
  AgFiche? pt;
  for (final p in patients) {
    if (p['code'] == patientCode) {
      pt = p;
      break;
    }
  }
  return {
    'numero': agNumeroAppel(poste, tous, maintenant),
    'poste': poste,
    'posteLabel': agLibellePoste(poste),
    'patientId': pt?['id'],
    'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : patientCode,
    'patientCode': patientCode,
    'priorite': priorite,
    'motif': motif,
    'praticien': agVrai(praticien) ? praticien : null,
    'arriveeLe': agInstant(maintenant),
    'etat': 'attente',
  };
}

/// Appeler un patient : il est servi, à cet instant, par cet agent.
AgFiche agPatchAppel(String agent, DateTime maintenant) =>
    {'etat': 'servi', 'serviLe': agInstant(maintenant), 'appelePar': agent};

/// Changer la priorité : le motif est obligatoire (faire passer un patient devant un autre doit s'expliquer).
AgFiche agPatchPriorite(String priorite, String motif) =>
    {'priorite': priorite, 'motifChangement': motif};

// --- l'écran d'appel -----------------------------------------------------------------------------------------------------------------

/// La carte d'un poste sur l'écran de salle d'attente : le DERNIER numéro appelé, les trois prochains, le nombre en attente. Des NUMÉROS, jamais un
/// nom ni un motif.
class AgCartePoste {
  const AgCartePoste(this.poste, this.libelle, this.appele, this.prochains, this.enAttente);
  final String poste;
  final String libelle;
  final String? appele;
  final List<String> prochains;
  final int enAttente;
}

List<AgCartePoste> agCartesAffichage(Iterable<AgFiche> tickets) {
  final actifs = [for (final t in tickets) if (_actif(t)) t];
  return [
    for (final (code, libelle) in agPostes)
      () {
        final f = agFileTriee(actifs, code);
        final servis = agTrierTexte(
            actifs.where((t) => t['poste'] == code && t['etat'] == 'servi'),
            (t) => agVrai(t['serviLe']) ? '${t['serviLe']}' : '');
        return AgCartePoste(
            code,
            libelle,
            servis.isEmpty ? null : '${servis.last['numero']}',
            [for (final t in f.take(3)) '${t['numero']}'],
            f.length);
      }()
  ];
}

// --- la file par cabinet ------------------------------------------------------------------------------------------------------------

/// Les deux listes jamais fondues : un cabinet par praticien nommé (ordre alphabétique), et le vivier commun. Chacune suit le classement de la file.
class AgCabinets {
  const AgCabinets(this.enFile, this.nommes, this.vivier, this.parPraticien);
  final int enFile;
  final int nommes;
  final List<AgFiche> vivier;
  final List<(String, List<AgFiche>)> parPraticien;
}

AgCabinets agCabinets(Iterable<AgFiche> tickets) {
  final liste = [
    for (final t in tickets)
      if (_actif(t) && t['poste'] == 'consultation' && t['etat'] != 'servi' && t['etat'] != 'clos') t
  ];
  final copie = [for (final (i, l) in liste.indexed) (i, l)];
  copie.sort((a, b) {
    final pa = agPriorite(a.$2['priorite']).rang, pb = agPriorite(b.$2['priorite']).rang;
    if (pa != pb) return pa - pb;
    final c = '${a.$2['arriveeLe']}'.compareTo('${b.$2['arriveeLe']}');
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  final tries = [for (final e in copie) e.$2];
  final nommes = tries.where((t) => agVrai(t['praticien'])).toList();
  final vivier = tries.where((t) => !agVrai(t['praticien'])).toList();
  final par = <String, List<AgFiche>>{};
  for (final t in nommes) {
    (par['${t['praticien']}'] ??= []).add(t);
  }
  final noms = par.keys.toList()..sort();
  return AgCabinets(tries.length, nommes.length, vivier, [for (final n in noms) (n, par[n]!)]);
}

List<AgKpi> agKpisCabinets(AgCabinets c) => [
      AgKpi('En file de consultation', agNum(c.enFile)),
      AgKpi('Attendent un praticien nommé', agNum(c.nommes)),
      AgKpi('Vivier commun', agNum(c.vivier.length), indice: 'Visibles de TOUS les cabinets'),
      AgKpi('Cabinets sollicités', agNum(c.parPraticien.length)),
    ];

/// Une ligne d'un cabinet : patient, priorité (en toutes lettres), arrivée.
List<String> agLigneCabinet(AgFiche t) {
  final d = agDate(t['arriveeLe']);
  return [
    agVrai(t['patient']) ? '${t['patient']}' : (agVrai(t['nom']) ? '${t['nom']}' : '—'),
    agPriorite(t['priorite']).libelle,
    agVrai(t['arriveeLe']) ? (d == null ? 'NaN/NaN/NaN à NaNhNaN' : dateHeure(d)) : '—',
  ];
}
