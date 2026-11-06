import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/besoins_commun.dart' show notifierPoste;

/// LA CONFIGURATION FISCALE VALIDÉE ET DATÉE AU POSTE (Direction, 06/11/2026 ; spec `SPEC-configuration-fiscale-validee.md`, phase 5 ; écart E2277).
///
/// Ce que partagent `cfg-branding`, `cfg-fiscalite`, `cfg-comptabilite` et `cfg-entetes` : le branchement du MOTEUR du domaine (`cfb_fiscal_date.dart`,
/// fonctions pures) sur le magasin du poste. Le domaine rend ce qu'il faut écrire ; c'est ICI que l'on écrit, journalise (RG-12) et notifie. Une commande
/// interdite est ABSENTE (jamais grisée) et le moteur refait le contrôle. Sur un fileul rattaché, la configuration est tenue par la mère : lecture seule
/// nommée, et les gardes du magasin (famille R) refusent l'écriture locale (E2278).
class ConfigurationFiscalePoste {
  ConfigurationFiscalePoste(this.c);
  final ContexteEcran c;

  Magasin get m => c.magasin;
  CollectionMagasin get versions => m.collection('identiteLegale');
  CollectionMagasin get obligations => m.collection('obligationsFiscales');
  CollectionMagasin get historique => m.collection('historiqueObligations');
  CollectionMagasin get echeances => m.collection('echeancesFiscales');
  List<Fiche> get exercices => m.collection('exercices').toutes;

  /// Le poste est-il un fileul rattaché à une mère ? (`CF().posteFileul()` de la maquette.)
  bool get fileul => ServiceInstallation.de(m).rattache;

  String get acteurNomme => acteur(c).nom;
  DateTime get maintenant => c.aujourdhui;

  /// `peutValiderConfiguration()` : le rôle est de validation, l'agent a le droit d'écrire sur CFG, le poste n'est pas un fileul.
  bool get peutValider => cfbRolesValidation.contains(c.role) && c.droit.editer && !fileul;

  /// Les trois collections doivent exister sur un poste : si le jeu ne les porte pas (ancien jeu, magasin vide), la SEMENCE est posée, sans journal
  /// (ce n'est pas le geste d'un agent). À appeler AVANT le premier rendu, jamais pendant.
  static void amorcer(Magasin m) {
    final v = m.collection('identiteLegale');
    if (v.toutes.isEmpty) v.ajouterSansJournal(cfbSemenceIdentite());
    final o = m.collection('obligationsFiscales');
    if (o.toutes.isEmpty) {
      for (final f in cfbSemenceObligations()) {
        o.ajouterSansJournal(f);
      }
    }
    m.collection('historiqueObligations');
  }

  // --- Identité ----------------------------------------------------------------------------------------------------------------------------------

  Fiche? identiteEnForce() => cfbIdentiteALaDate(versions.actives, maintenant);
  IdentiteImprimee identiteImprimee([DateTime? date]) => cfbIdentiteImprimee(versions.actives, date ?? maintenant);
  CfbEtatConfiguration etatIdentite() => cfbEtatIdentite(versions.toutes, maintenant);
  bool get identiteExigeVersion => cfbIdentiteExigeVersion(versions.toutes);

  /// Les versions À VENIR (une bascule datée du mois prochain ne change pas ce que la caisse imprime ce matin).
  List<Fiche> versionsAVenir() {
    final a = isoJour(maintenant);
    return [for (final v in versions.actives) if (v['debut'] != null && isoJour(v['debut']).compareTo(a) > 0) v]
      ..sort((x, y) => isoJour(x['debut']).compareTo(isoJour(y['debut'])));
  }

  /// « Enregistrer » avant la première validation : corrige la version en force. Rend le refus, ou `null`. `VERSION_REQUISE` : l'appelant ouvre la
  /// modale de portée.
  CfbEcritureIdentite enregistrerIdentite(Map<String, Object?> champs) {
    final r = cfbEnregistrerIdentite(versions.toutes, champs, acteur: acteurNomme, maintenant: maintenant, aujourdhui: maintenant, fileul: fileul);
    if (r.ok) versions.mettreAJour(r.id, r.fiche!);
    return r;
  }

  /// Après une validation : une version NOUVELLE, datée et motivée ; la version couvrante se ferme la veille de la date d'effet et RESTE.
  CfbEcritureIdentite nouvelleVersionIdentite(Map<String, Object?> champs, {required Object dateEffet, required String motif, required String origine}) {
    final r = cfbNouvelleVersionIdentite(versions.toutes, champs,
        dateEffet: dateEffet, motif: motif, acteur: acteurNomme, maintenant: maintenant, aujourdhui: maintenant, exercices: exercices, fileul: fileul, origine: origine);
    if (!r.ok) return r;
    if (r.precedenteId != null) versions.mettreAJour(r.precedenteId, r.patchPrecedente!);
    versions.inserer(r.fiche!, prefixe: 'IDL');
    return r;
  }

  CfbValidation validerIdentite() {
    final r = cfbValiderIdentite(versions.toutes, role: c.role, acteur: acteurNomme, maintenant: maintenant, aujourdhui: maintenant, fileul: fileul);
    if (r.ok) _validerFiches(versions, r, 'Identité légale validée');
    return r;
  }

  // --- Obligations et paramètres ORTB ------------------------------------------------------------------------------------------------------------

  List<Fiche> obligationsALaDate([DateTime? date]) => cfbObligationsALaDate(obligations.toutes, historique.toutes, date ?? maintenant);
  Fiche ortbALaDate([DateTime? date]) => cfbOrtbALaDate(obligations.toutes, historique.toutes, date ?? maintenant);
  CfbEtatConfiguration etatObligations() => cfbEtatObligations(obligations.toutes, historique.toutes);

  CfbValidation validerObligations() {
    final r = cfbValiderObligations(obligations.toutes, role: c.role, acteur: acteurNomme, maintenant: maintenant, fileul: fileul);
    if (r.ok) _validerFiches(obligations, r, 'Obligations fiscales validées');
    return r;
  }

  /// La validation pose le MÊME patch sur toutes les fiches visées, puis UNE ligne de journal nommée (pas vingt « Modification »).
  void _validerFiches(CollectionMagasin col, CfbValidation r, String action) {
    for (final id in r.ids) {
      col.mettreAJour(id, r.patch, journaliser: false);
    }
    m.journaliser(action, 'CFG', col.nom, r.ids.join(','), null, {'valideLe': r.valideLe, 'validePar': r.validePar, 'fiches': r.nombre});
  }

  /// `echeancesImpactees(code, dateEffet)` annoncé par la modale de portée.
  String annoncePortee(String code, Object dateEffet) => cfbAnnoncePortee(cfbEcheancesImpactees(echeances.toutes, code, dateEffet));

  CfbEcritureObligation modifierObligation(Fiche o, Map<String, Object?> valeurs, {required Object dateEffet, required String motif}) {
    final r = cfbModifierObligation(obligations.toutes,
        id: '${o['id']}', valeurs: valeurs, dateEffet: dateEffet, motif: motif, acteur: acteurNomme, maintenant: maintenant, aujourdhui: maintenant, exercices: exercices, fileul: fileul);
    if (r.ok) _appliquerObligation(r);
    return r;
  }

  CfbEcritureObligation creerObligation(Map<String, Object?> valeurs, {required Object dateEffet, required String motif}) {
    final r = cfbCreerObligation(obligations.toutes, historique.toutes,
        valeurs: valeurs, dateEffet: dateEffet, motif: motif, acteur: acteurNomme, maintenant: maintenant, aujourdhui: maintenant, exercices: exercices, fileul: fileul);
    if (r.ok) _appliquerObligation(r);
    return r;
  }

  CfbEcritureObligation retirerObligation(Fiche o, {required Object dateEffet, required String motif}) {
    final r = cfbRetirerObligation(obligations.toutes,
        id: '${o['id']}',
        dateEffet: dateEffet,
        motif: motif,
        acteur: acteurNomme,
        maintenant: maintenant,
        aujourdhui: maintenant,
        exercices: exercices,
        fileul: fileul,
        droitAnnuler: c.droit.annuler,
        libelleRole: c.role);
    if (r.ok) _appliquerObligation(r);
    return r;
  }

  CfbEcritureObligation modifierOrtb(Map<String, Object?> valeurs, {required Object dateEffet, required String motif}) {
    final r = cfbModifierOrtb(obligations.toutes,
        valeurs: valeurs, dateEffet: dateEffet, motif: motif, acteur: acteurNomme, maintenant: maintenant, aujourdhui: maintenant, exercices: exercices, fileul: fileul);
    if (r.ok) {
      historique.inserer(r.historique!, prefixe: 'HOB');
      obligations.mettreAJour(r.id, r.fiche!);
    }
    return r;
  }

  /// Le résultat de la dernière régénération d'échéances (ce que l'écran annonce).
  CfbRegeneration? derniereRegeneration;

  void _appliquerObligation(CfbEcritureObligation r) {
    if (r.historique != null) historique.inserer(r.historique!, prefixe: 'HOB');
    if (r.creation) {
      obligations.inserer(r.fiche!, prefixe: 'FIS');
    } else if (r.archiver) {
      final patch = {...r.fiche!}..remove('id');
      obligations.mettreAJour(r.id, patch);
    } else {
      obligations.mettreAJour(r.id, r.fiche!);
    }
    derniereRegeneration = regenererEcheances(r.code!, r.dateEffet!);
  }

  /// `S.regenererEcheances` : les échéances PAYÉES ne bougent jamais, les non payées à partir de la date d'effet sont archivées (RG-14) et recréées depuis la
  /// version en vigueur ; une ligne de journal porte les dates avant / après ; une tâche de poste prévient le Comptable.
  CfbRegeneration regenererEcheances(String code, Object dateEffet) {
    final r = cfbRegenererEcheances(echeances.toutes,
        code: code, dateEffet: dateEffet, auteur: acteurNomme, maintenant: maintenant, obligations: obligations.toutes, historique: historique.toutes);
    for (final id in r.archiveesIds) {
      echeances.archiver(id);
    }
    for (final f in r.creeesFiches.reversed) {
      echeances.inserer(f, prefixe: 'ECH');
    }
    m.journaliser('Échéances régénérées', 'M12', 'echeancesFiscales', code, {'echeances': r.avant}, {'echeances': r.apres, ...r.comptes});
    if (r.archivees + r.creees > 0) {
      notifierPoste(m, {'type': 'echeances_regenerees', 'poste': 'comptable', 'libelle': r.libelle, 'detail': r.detail, 'priorite': 'normale', 'reference': code}, maintenant);
    }
    return r;
  }

  /// `amorcerEcheances()` de M12 : un exercice sans échéance les engendre depuis la version EN VIGUEUR (sans quittance inventée). À appeler avant le rendu.
  int amorcerEcheances(int exercice) {
    if (echeances.toutes.any((e) => nombreOuZero(e['exercice']).toInt() == exercice)) return 0;
    final lignes = cfbGenEcheances(exercice, obligations: obligations.toutes, historique: historique.toutes, aujourdhui: maintenant, sansReglement: true);
    for (final f in lignes) {
      echeances.ajouterSansJournal({...f, 'id': 'ECH$exercice-${f['id']}'});
    }
    return lignes.length;
  }
}

// =============================================================================================================================================
// Composants d'écran partagés : bandeau d'état, bouton Valider, note des versions à venir, modale « Portée de la modification »
// =============================================================================================================================================

String _dateHeureIso(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : dateHeure(d.toLocal());
}

/// `bandeauEtatConfiguration(nom, libelle)` : à valider, validé le D par P, ou modifié depuis la validation (RG-12). Sur un fileul : « tenue par la mère ».
Widget cfbBandeauEtat(ConfigurationFiscalePoste cf, {required bool identite, required String libelle}) {
  final e = identite ? cf.etatIdentite() : cf.etatObligations();
  final String texte;
  final TonSigh ton;
  final IconData icone;
  switch (e.etat) {
    case 'valide':
      texte = '$libelle validée le ${_dateHeureIso(e.valideLe!)} par ${e.validePar}.';
      ton = TonSigh.succes;
      icone = LucideIcons.circleCheck;
    case 'modifie_depuis':
      final a = e.validationAnterieure!;
      texte = '$libelle modifiée le ${e.modifieLe == null ? '(date inconnue)' : _dateHeureIso(e.modifieLe!)} par ${e.modifiePar ?? 'un agent non identifié'} '
          'depuis la validation du ${_dateHeureIso('${a['valideLe']}')} par ${a['validePar']} : à revalider.';
      ton = TonSigh.attention;
      icone = LucideIcons.triangleAlert;
    default:
      texte = '$libelle à valider (première configuration) : vérifier chaque mention, corriger ce qui doit l’être, puis Valider. '
          'La validation appartient à la Direction, à la DAF ou à l’administrateur système.';
      ton = TonSigh.attention;
      icone = LucideIcons.clipboardCheck;
  }
  final complet = cf.fileul ? '$texte Configuration tenue par la mère : lecture seule sur ce poste.' : texte;
  return NoteSigh(complet, key: Key('cfb:etat:${identite ? 'identite' : 'obligations'}:${e.etat}'), ton: ton, icone: icone);
}

/// `noteVersionsAVenir()` : les versions de l'identité qui prennent effet plus tard ; `null` s'il n'y en a pas.
Widget? cfbNoteVersionsAVenir(ConfigurationFiscalePoste cf) {
  final futures = cf.versionsAVenir();
  if (futures.isEmpty) return null;
  return NoteSigh(
      '${nombre(futures.length)} version(s) à venir : '
      '${futures.map((v) => 'version ${v['version']} à partir du ${dateFR(DateTime.parse(isoJour(v['debut'])))}${v['motif'] != null ? ' (${v['motif']})' : ''}').join(' ; ')}. '
      'Jusque-là, les pièces portent la version en force aujourd’hui.',
      key: const Key('cfb:versions-a-venir'),
      ton: TonSigh.info,
      icone: LucideIcons.calendarClock);
}

/// Un refus du domaine, affiché : le motif et le geste qui corrige.
void cfbToastRefus(BuildContext ctx, CfbRefus r) => ToastsSigh.afficher(ctx, r.motif, type: TypeToast.erreur, detail: r.geste);

/// `boutonValiderConfiguration(nom, libelle, apres)` : ABSENT sans droit (`K.commande`) et hors des rôles de validation ; le moteur refait le contrôle.
Widget? cfbBoutonValider(BuildContext ctx, ConfigurationFiscalePoste cf, {required bool identite, required String libelle, VoidCallback? apres}) {
  if (!cf.peutValider) return null;
  return BoutonSigh(
      key: Key('cfb:valider:${identite ? 'identite' : 'obligations'}'),
      libelle: 'Valider $libelle',
      icone: LucideIcons.shieldCheck,
      onPressed: () async {
        final ok = await confirmerSigh(ctx,
            titre: 'Valider $libelle',
            message: 'La validation atteste que chaque mention a été vérifiée par la Direction, la DAF ou l’administrateur. Elle est journalisée (RG-12) et ne '
                'modifie aucune valeur. Toute modification ultérieure créera une version datée et remettra la configuration à l’état « à revalider ».',
            libelleOk: 'Valider');
        if (!ok || !ctx.mounted) return;
        final r = identite ? cf.validerIdentite() : cf.validerObligations();
        if (!r.ok) {
          cfbToastRefus(ctx, r.refus!);
          return;
        }
        final l = libelle.replaceFirst(RegExp(r'^(l’|les |la |le )'), '');
        ToastsSigh.afficher(ctx, '${l[0].toUpperCase()}${l.substring(1)} validée${identite ? '' : 's'}.',
            type: TypeToast.succes, detail: 'Le ${_dateHeureIso(r.valideLe!)} par ${r.validePar}.');
        apres?.call();
      });
}

/// LA MODALE « PORTÉE DE LA MODIFICATION » (reprise de la grille des primes). Date d'effet (défaut : aujourd'hui, refusée dans un exercice clos et avant la
/// version en vigueur) et motif OBLIGATOIRES ; pour une obligation, elle annonce ce que la régénération fera des échéances. AUCUNE option rétroactive :
/// une échéance payée ne bouge jamais, une pièce émise garde son en-tête. [appliquer] rend le refus du moteur (affiché, la modale reste ouverte) ou `null`.
Future<void> cfbModalePortee(
  BuildContext ctx, {
  required ConfigurationFiscalePoste cf,
  String? sousTitre,
  required String explication,
  Object? minimum,
  String? placeholderMotif,
  String libelleAppliquer = 'Appliquer',
  String Function(String dateEffet)? impact,
  Widget? resume,
  required CfbRefus? Function(String dateEffet, String motif) appliquer,
}) {
  final auj = isoJour(cf.maintenant);
  final f = ControleurFormulaire([
    ChampDef(
        nom: 'dateEffet',
        libelle: 'Date d’effet',
        type: TypeChamp.date,
        requis: true,
        aide: 'À partir de ce jour, la nouvelle version s’applique ; avant, l’ancienne reste en vigueur. Refusée dans un exercice clos'
            '${minimum != null ? ' et avant le ${dateFR(DateTime.parse(isoJour(minimum)))}' : ''}.'),
    ChampDef(
        nom: 'motif',
        libelle: 'Motif (consigné au journal)',
        type: TypeChamp.textarea,
        lignes: 2,
        requis: true,
        col: ColChamp.plein,
        indicatif: placeholderMotif ?? 'Texte, décision ou constat qui justifie la modification'),
  ], {'dateEffet': auj});
  return afficherModale<void>(ctx,
      titre: 'Portée de la modification',
      sousTitre: sousTitre,
      taille: TailleModale.lg,
      corps: ListenableBuilder(
          listenable: f,
          builder: (cc, _) {
            final d = '${f['dateEffet'] ?? ''}'.isEmpty ? auj : '${f['dateEffet']}';
            final t = impact?.call(d);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: JetonsShell.warning50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.warning200)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(LucideIcons.triangleAlert, size: 20, color: JetonsShell.warning600),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Cette modification a une portée : elle est datée.',
                          style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.warning900)),
                      const SizedBox(height: 4),
                      Text(explication, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.warning800)),
                    ])),
                  ])),
              if (resume != null) ...[const SizedBox(height: 12), resume],
              const SizedBox(height: 12),
              FormulaireSigh(controleur: f),
              if (t != null) ...[const SizedBox(height: 12), NoteSigh(t, key: const Key('cfb:portee:impact'), ton: TonSigh.info, icone: LucideIcons.calendarClock)],
            ]);
          }),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                key: const Key('cfb:portee:appliquer'),
                libelle: libelleAppliquer,
                icone: LucideIcons.check,
                onPressed: () {
                  final v = f.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ctx, 'Date d’effet et motif sont obligatoires.', type: TypeToast.erreur);
                    return;
                  }
                  final r = appliquer('${v['dateEffet']}', '${v['motif']}'.trim());
                  if (r != null) {
                    cfbToastRefus(ctx, r);
                    return;
                  }
                  fermer();
                }),
          ]);
}

/// `enregistrerIdentiteDepuis(ecran, champs, apres)` : avant la première validation, « Enregistrer » corrige la version en force ; après, il ouvre la modale
/// de portée et crée une version. Le refus du magasin (garde « réglé sur la mère ») est NOMMÉ, jamais avalé.
Future<void> cfbEnregistrerIdentiteDepuis(BuildContext ctx, ConfigurationFiscalePoste cf, String ecran, Map<String, Object?> champs, {VoidCallback? apres}) async {
  try {
    if (cf.identiteExigeVersion) {
      final enForce = cf.identiteEnForce();
      await cfbModalePortee(ctx,
          cf: cf,
          sousTitre: 'Identité légale (version ${enForce?['version'] ?? 1} en force)',
          explication: 'L’identité légale a déjà été validée : la modification crée une NOUVELLE VERSION, datée. Les pièces émises avant la date d’effet gardent '
              'l’en-tête sous lequel elles ont été imprimées ; la nouvelle version devra être revalidée.',
          minimum: enForce?['debut'],
          placeholderMotif: 'Changement de RCCM, nouvelle adresse, nouveau numéro…',
          libelleAppliquer: 'Créer la version',
          appliquer: (dateEffet, motif) {
            final r = cf.nouvelleVersionIdentite(champs, dateEffet: dateEffet, motif: motif, origine: ecran);
            if (!r.ok) return r.refus;
            ToastsSigh.afficher(ctx, 'Version ${r.version} de l’identité légale créée.',
                type: TypeToast.succes,
                detail: '${r.enForceAujourdhui ? 'En force dès aujourd’hui.' : 'Prend effet le ${dateFR(DateTime.parse(isoJour(dateEffet)))}.'} '
                    'À revalider par la Direction, la DAF ou l’administrateur.');
            apres?.call();
            return null;
          });
      return;
    }
    final r = cf.enregistrerIdentite(champs);
    if (!r.ok) {
      cfbToastRefus(ctx, r.refus!);
      return;
    }
    ToastsSigh.afficher(ctx, 'Identité enregistrée (version ${r.version}).',
        type: TypeToast.succes, detail: 'Tous les états édités reprennent ces mentions. À valider par la Direction, la DAF ou l’administrateur (écran Paramètres fiscaux).');
    apres?.call();
  } on EcritureRefusee catch (e) {
    ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
  }
}

/// Un appel au magasin qui peut être refusé par une garde (fileul : « réglé sur la mère ») : le refus est affiché, jamais avalé. Rend vrai si refusé.
bool cfbRefuseSiGarde(BuildContext ctx, void Function() ecriture) {
  try {
    ecriture();
    return false;
  } on EcritureRefusee catch (e) {
    ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
    return true;
  }
}
