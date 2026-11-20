import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// L'espace « Mes » de l'agent, la copie de la fiche de paie pour le téléphone et le pointage par badge au poste (Direction, 09/11/2026, lots L7 et L8) : la colle
/// entre les fonctions pures de `packages/domaine/lib/src/rh/espace_mes.dart` et `pointage_badge.dart` (rejouées sur les vecteurs de la maquette) et le magasin du
/// poste. Aucune règle ici : l'agent de la session, les rubriques, les refus nommés sont ceux du domaine ; les réglages se LISENT au registre des paramètres
/// (`paie.copieFichePaieTelephone`, `planning.badgeSertDePointage`, `planning.delaiEntrePointagesBadge`, versionnés par date, synchronisés par le journal), jamais une
/// constante. Ce fichier assemble les fiches, écrit ce que le domaine rend et journalise par les collections (RG-12).
///
/// L'ESPACE LIT, IL N'ÉCRIT RIEN ET NE GARDE RIEN : aucune copie persistée de ce qu'il montre (le magasin du poste est la seule source, relu à chaque rendu).
class EspaceMesPoste {
  EspaceMesPoste(this.m, {required this.auteur, required this.role, DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String role;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());
  ServiceParametres get service => serviceParametres(m, auteur: auteur, horloge: _horloge);

  /// La copie de la fiche de paie sur le téléphone est-elle active AUJOURD'HUI ? (défaut : oui ; tout ce qui n'est pas faux vaut oui, comme à la maquette).
  bool copiePaieActive() => service.valeur('paie.copieFichePaieTelephone', aujourdhui) != false;

  /// Règle la copie : une NOUVELLE VERSION du paramètre effective aujourd'hui, journalisée avec l'ancienne et la nouvelle valeur (RG-12). Réservé à l'administrateur
  /// et à la DA : le refus est nommé. Le réglage reste NON mobile (famille « paie » réservée) : la mère publie ou retire la copie, le téléphone ne lit jamais ce réglage.
  Map<String, Object?> definirCopiePaie(Object? oui, {String? motif}) {
    final refus = controlerReglageCopiePaie(role);
    if (refus != null) return refus.toJson();
    final avant = copiePaieActive();
    final r = service.regler('paie.copieFichePaieTelephone', oui == true, aujourdhui, motif: motif);
    if (!r.ok) return {'ok': false, 'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
    m.journaliser('Copie de la fiche de paie sur le téléphone', 'M11', 'reglage', 'paieCopieTelephone', {'valeur': avant}, {'valeur': oui == true, 'motif': motif});
    return {'ok': true, 'valeur': oui == true, 'avant': avant};
  }

  List<Fiche> _actives(String nom) => m.collection(nom).actives;

  List<Fiche> get _personnelActif => _actives('personnel');

  /// L'agent de la session, retrouvé par son nom (la session ne porte pas d'identifiant de personnel) ; `refus` : le refus nommé du domaine.
  ({Fiche? agent, RefusRh? refus}) agent() => agentDeMes(acteur: auteur(), personnelActif: _personnelActif);

  /// Les collections que lisent les rubriques (actives seulement), par nom.
  Map<String, List<Fiche>> _collections() => {
        for (final n in {...[for (final r in rubriquesMes) if (r.source != null) r.source!], 'participations', 'patients', 'consultations', 'demandesAnalyses', 'admissions', 'planning', 'presences'})
          n: _actives(n)
      };

  /// La lecture d'UNE rubrique par l'agent de la session : ses identifiants de fiches ou ses valeurs calculées, jamais celles d'un autre (RG-13).
  LectureMes lire(String rubriqueId) =>
      lireMes(rubriqueId: rubriqueId, acteur: auteur(), personnelActif: _personnelActif, collections: _collections(), notes: [admNs131.reference, admNs132.reference]);

  /// Les fiches d'une rubrique lues par [lire], dans l'ordre de la collection (la rubrique « notes » n'en a pas : ses lignes viennent des notes en vigueur).
  List<Fiche> fiches(RubriqueMes r, LectureMes lu) {
    if (r.source == null) return const [];
    final col = m.collection(r.source!);
    return [for (final id in lu.ids) if (col.parId(id) != null) col.parId(id)!];
  }

  /// L'assurance du personnel de l'agent de la session : montants PORTÉS ou « non renseigné », jamais le prix courant (lecture seule, rien ne remonte à la compta).
  AssuranceMes? assurance() {
    final a = agent();
    if (a.agent == null) return null;
    return assuranceDeLAgent(
        agentId: a.agent!['id'],
        patients: _actives('patients'),
        consultations: _actives('consultations'),
        demandesAnalyses: _actives('demandesAnalyses'),
        admissions: _actives('admissions'));
  }

  /// La copie de la fiche de paie pour le téléphone de l'agent de la session : ses pièces ÉMISES (diffusées), jamais celles d'un autre, jamais recalculées.
  CopiePaie copiePaie({Object? agentIdDemande}) =>
      copiePaieAgent(actif: copiePaieActive(), acteur: auteur(), personnelActif: _personnelActif, bulletins: _actives('bulletins'), agentIdDemande: agentIdDemande);
}

/// Le pointage par badge au poste (lot L8) : le domaine décide, ce fichier écrit. Hors ligne, l'écriture est locale et voyage au pont d'activité quand le poste
/// rejoint les autres (`presences` figure à `collectionsActivite`) ; la règle du délai est LOCALE au poste (deux postes hors ligne peuvent chacun enregistrer une
/// arrivée : les deux lignes restent visibles au registre, le surveillant régularise ou archive, rien n'est corrigé en silence).
class PointageBadgePoste {
  PointageBadgePoste(this.m, {required this.auteur, required this.role, DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String role;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());
  ServiceParametres get service => serviceParametres(m, auteur: auteur, horloge: _horloge);

  /// Le badge sert-il de pointage AUJOURD'HUI ? (défaut : oui).
  bool actif() => service.valeur('planning.badgeSertDePointage', aujourdhui) != false;

  /// Le délai minimal entre deux pointages, en minutes (défaut : 5, valeur d'attente à valider).
  int delai() {
    final v = service.valeur('planning.delaiEntrePointagesBadge', aujourdhui);
    return v is num && v.isFinite && v >= 0 ? v.toInt() : delaiPointageBadgeDefaut;
  }

  /// Règle le pointage (activation et/ou délai) : deux NOUVELLES VERSIONS effectives aujourd'hui, journalisées (RG-12). Réservé à l'administrateur et à la DA.
  Map<String, Object?> regler({bool? actif, Object? delai, String? motif}) {
    final d = delai == null || delai == '' ? this.delai() : delai;
    final refus = controlerReglagePointageBadge(role: role, delai: d);
    if (refus != null) return refus.toJson();
    final avant = {'actif': this.actif(), 'delai': this.delai()};
    final a = actif ?? this.actif();
    final dn = d is num ? d.toInt() : int.parse('$d'.trim());
    final r1 = service.regler('planning.badgeSertDePointage', a, aujourdhui, motif: motif);
    if (!r1.ok) return {'ok': false, 'code': r1.refus!.code, 'motif': r1.refus!.motif, 'geste': r1.refus!.geste};
    final r2 = service.regler('planning.delaiEntrePointagesBadge', dn, aujourdhui, motif: motif);
    if (!r2.ok) return {'ok': false, 'code': r2.refus!.code, 'motif': r2.refus!.motif, 'geste': r2.refus!.geste};
    m.journaliser('Le badge sert de pointage', 'M10', 'reglage', 'planningBadgeSertDePointage', avant, {'actif': a, 'delai': dn, 'motif': motif});
    return {'ok': true, 'actif': a, 'delai': dn, 'avant': avant};
  }

  /// Une ligne d'audit SANS passer par l'insertion d'une fiche (qui journaliserait à son tour : même forme que `S.journaliserAcces` de la maquette, plafonné à 400).
  void _journaliserPassage(String texte, Fiche? b, String code, String? motif) {
    final a = m.collection('audit');
    a.inserer({
      'id': 'LOG${(a.toutes.length + 1).toString().padLeft(5, '0')}',
      'dateHeure': _horloge().toIso8601String(),
      'utilisateur': auteur(),
      'role': role,
      'action': 'Pointage par badge',
      'module': 'M10',
      'entite': 'Badge',
      'reference': b != null ? '${b['numero']}' : (texte.length > 40 ? texte.substring(0, 40) : texte),
      'cible': b != null ? b['agent'] : null,
      'ecran': 'm10-badges-verification',
      'motif': code + (motif != null && motif.isNotEmpty ? ' : $motif' : ''),
      'trouve': b != null,
      'poste': m.poste,
      'succes': true,
    });
    a.plafonner(400);
  }

  /// Présente un badge au pointage : écrit l'arrivée (nouvelle présence « à valider ») ou le départ (patch de la présence ouverte), journalise chaque passage,
  /// refusé ou non. Rend `{ok, geste, presenceId, agentId, heure, etat, annuler}` ou le refus nommé `{ok: false, code, motif, geste}`.
  Map<String, Object?> pointer(String texte, {DateTime? instant}) {
    final t = instant ?? _horloge();
    final jour = parametreDateIso(t);
    final heure = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final badges = m.collection('badges').toutes;
    final r = pointerParBadge(
        role: role,
        actif: actif(),
        delai: delai(),
        texte: texte,
        jour: jour,
        heure: heure,
        badges: badges,
        personnel: m.collection('personnel').toutes,
        presences: m.collection('presences').actives,
        acteur: auteur(),
        aujourdhui: aujourdhui);
    final lu = rhcLireBadgeQR(texte);
    final b = lu == null ? null : rhcBadgeDuNumero(badges, lu.numero);
    if (!r.ok) {
      _journaliserPassage(texte, b, r.refus!.code, r.refus!.motif);
      return r.refus!.toJson();
    }
    final col = m.collection('presences');
    if (r.geste == 'depart') {
      final annuler = col.mettreAJour(r.presenceId, r.patch!);
      _journaliserPassage(texte, b, 'DEPART', heure);
      return {'ok': true, 'geste': 'depart', 'presenceId': r.presenceId, 'agentId': r.agentId, 'heure': heure, 'etat': r.etat, 'annuler': annuler};
    }
    final ins = col.inserer({...r.creation!}, prefixe: 'PRS');
    _journaliserPassage(texte, b, 'ARRIVEE', heure);
    return {'ok': true, 'geste': 'arrivee', 'presenceId': ins.fiche['id'], 'agentId': r.agentId, 'heure': heure, 'etat': r.etat, 'annuler': ins.annuler};
  }
}

/// L'état d'AFFICHAGE de l'espace « Mes » : la seule chose retenue, et non une copie des données (l'écran relit le magasin à chaque rendu). Poste partagé : au
/// VERROU la rubrique ouverte est gardée (retour à l'écran quitté), à la DÉCONNEXION tout part (l'agent suivant arrive sur la première rubrique).
class MesAffichage {
  const MesAffichage._();

  /// La rubrique ouverte, ou `null` (première rubrique).
  static String? rubrique;

  /// Vide l'état d'affichage ; [garderRubrique] : au verrou.
  static void purger({bool garderRubrique = false}) {
    if (!garderRubrique) rubrique = null;
  }
}
