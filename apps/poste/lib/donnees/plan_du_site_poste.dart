import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le plan du site réglable au poste (lot U, Direction, 11/11/2026) : la colle entre les fonctions pures de `packages/domaine/lib/src/acces/acc_plan_du_site.dart` (rejouées sur les
/// vecteurs de la maquette) et le poste. Aucune règle ici : le défaut (NON), les droits (administrateur et Directrice Administrative seuls) et les refus nommés sont ceux du domaine ;
/// la valeur se LIT au registre des paramètres (`affichage.planDuSite`, versionnée par date, synchronisée par le journal de configuration), jamais une constante. Le réglage ne va jamais
/// aux téléphones (`mobile: false`).

/// Le plan du site est-il affiché sur ce poste AUJOURD'HUI ? `m` absent (page sans magasin) : non, le défaut du domaine.
bool planDuSitePosteAffiche(Magasin? m, {DateTime Function()? horloge}) {
  if (m == null) return planDuSiteDefaut;
  final h = horloge ?? DateTime.now;
  final s = serviceParametres(m, auteur: () => '', horloge: h);
  return planDuSiteAffiche(s.valeur(cleAffichagePlanDuSite, parametreDateIso(h())));
}

class PlanDuSitePoste {
  PlanDuSitePoste(this.m, {required this.auteur, required this.role, DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String role;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());
  ServiceParametres get service => serviceParametres(m, auteur: auteur, horloge: _horloge);

  bool affiche() => planDuSitePosteAffiche(m, horloge: _horloge);

  /// Ce profil règle-t-il ? (La commande est ABSENTE ailleurs.)
  bool get peutRegler => rolesPlanDuSite.contains(role);

  /// Règle l'affichage : une NOUVELLE VERSION du paramètre effective aujourd'hui, journalisée avec l'ancienne et la nouvelle valeur (RG-12). Refus nommé du domaine (réservé, valeur
  /// invalide) ou du service (une fiche ne s'écrit que sur la mère).
  Map<String, Object?> definir(Object? oui, {String? motif}) {
    final refus = controlerReglagePlanDuSite(role: role, valeur: oui);
    if (refus != null) return refus.toJson();
    final avant = affiche();
    final r = service.regler(cleAffichagePlanDuSite, oui as bool, aujourdhui, motif: motif);
    if (!r.ok) return {'ok': false, 'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
    m.journaliser('Plan du site', 'M14', 'reglage', 'planDuSiteAffiche', {'affiche': avant}, {'affiche': oui, 'motif': motif});
    return {'ok': true, 'affiche': oui, 'avant': avant};
  }
}
