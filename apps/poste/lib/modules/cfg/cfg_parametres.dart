import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_parametres.dart';
import '../../donnees/aib_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../sync/configuration_sync.dart' show ApplicateurConfiguration;
import 'cfa_commun.dart';
import 'cfg_aib_achats.dart';

/// L'onglet « Paramètres » de « Paramètres système » (lot L0, décision de la Direction du 09/11/2026) : TOUT ce qui est paramétrable se règle ici, est ENREGISTRÉ
/// EN BASE avec un défaut semé, et se VERSIONNE PAR DATE. Un réglage n'écrase jamais l'ancien : il ajoute une version à partir d'une date d'effet, de sorte que
/// la valeur appliquée à une pièce déjà émise reste retrouvable. Une valeur déjà utilisée par une pièce ne se réécrit pas (refus nommé, avec le geste).
///
/// Les règles sont au domaine (`ServiceParametres`) ; cet écran ne fait que les mettre en page. Les paramètres se règlent sur la MÈRE : un fileul les reçoit par
/// le journal et les consulte (la commande de réglage y est absente, et la collection refuse l'écriture). Le panneau web du relais n'en montre aucun : il ne
/// voit jamais leur contenu (enveloppes chiffrées).
class PanneauParametres extends StatelessWidget {
  const PanneauParametres({super.key, required this.c, required this.estMere});
  final ContexteEcran c;
  final bool estMere;

  ServiceParametres _service() => serviceParametres(c.magasin, auteur: () => acteurNom(c), horloge: () => c.aujourdhui);

  @override
  Widget build(BuildContext context) {
    final service = _service();
    final aujourdhui = parametreDateIso(c.aujourdhui);
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection(parCollectionParametres), c.magasin.collection(parCollectionUsages)]),
        builder: (ctx, _) {
          final familles = service.parFamille(aujourdhui);
          final peutRegler = estMere && c.droit.editer;
          return cfaPile([
            cfaLectureSeule(c),
            if (!estMere) NoteSigh(ApplicateurConfiguration.motifGarde, ton: TonSigh.info, icone: LucideIcons.lock),
            const NoteSigh(
                'Un réglage ajoute une version à partir d’une date d’effet : la valeur en vigueur se lit à la date de la pièce, jamais à celle du jour. Une valeur déjà utilisée par une pièce ne se réécrit pas. Les paramètres voyagent chiffrés vers le relais, qui ne les lit pas.',
                ton: TonSigh.info,
                icone: LucideIcons.history),
            for (final e in familles.entries)
              cfaSection(
                  libellesFamillesParametres[e.key] ?? e.key,
                  cfaPile([
                    for (final p in e.value) _Carte(c: c, service: service, p: p, aujourdhui: aujourdhui, peutRegler: peutRegler, estMere: estMere),
                    // Famille AIB (lot L2) : l'état de la charge et du branchement, et ce que le branchement écrirait sur les achats.
                    if (e.key == 'bareme_aib') SectionAibAchats(c: c, estMere: estMere),
                  ], espace: 12)),
            cfaSource('Défauts : décisions de la Direction du 09/11/2026 (DECISIONS-A-VALIDER, section D). Rien n’est codé dans l’écran : valeurs et versions sont en base.'),
          ]);
        });
  }
}

String _libelleValeur(DefinitionParametre d, Object? v) {
  if (v is bool) return v ? 'Oui' : 'Non';
  if (v is String && d.libellesChoix.containsKey(v)) return d.libellesChoix[v]!;
  return v == null ? '—' : '$v';
}

class _Carte extends StatelessWidget {
  const _Carte({required this.c, required this.service, required this.p, required this.aujourdhui, required this.peutRegler, required this.estMere});
  final ContexteEcran c;
  final ServiceParametres service;
  final ParametreAffiche p;
  final String aujourdhui;
  final bool peutRegler;
  final bool estMere;

  DefinitionParametre get d => p.definition;

  String get _origine => p.origine == 'defaut'
      ? 'Défaut semé'
      : (p.dateEffet == null ? 'Défaut semé (version 0)' : 'Version ${p.version}, effective depuis le ${_dateFr(p.dateEffet!)}');

  @override
  Widget build(BuildContext context) {
    return CarteSigh(
        titre: d.libelle.isEmpty ? d.cle : d.libelle,
        child: cfaPile([
          DescListeSigh([
            ('Valeur en vigueur aujourd’hui', cfaGras(_libelleValeur(d, p.valeur))),
            ('Origine', _origine),
            ('Défaut', _libelleValeur(d, d.defaut)),
            ('Prochaine version', p.prochaine == null ? 'Aucune' : '${_libelleValeur(d, p.prochaine!.valeur)} à partir du ${_dateFr(p.prochaine!.dateEffet!)}'),
            ('Clé', cfaCode(d.cle)),
          ]),
          if (d.aide.isNotEmpty) cfaDiscret(d.aide),
          if (!d.branche)
            BadgeSigh('Enregistré, pas encore appliqué par l’écran concerné (${d.appliquePar ?? 'lot à venir'})', ton: TonSigh.attention),
          if (d.source != null) cfaDiscret('Source : ${d.source}'),
          Row(children: [
            if (peutRegler)
              BoutonSigh(libelle: 'Régler à partir d’une date', icone: LucideIcons.slidersHorizontal, taille: TailleBouton.sm, onPressed: () => _regler(context)),
            if (peutRegler) const SizedBox(width: 8),
            BoutonSigh(libelle: 'Historique (${p.nbVersions})', icone: LucideIcons.history, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => _historique(context)),
          ]),
        ], espace: 10));
  }

  void _historique(BuildContext ctx) {
    final versions = service.historique(d.cle);
    afficherModale<void>(ctx,
        titre: 'Historique : ${d.libelle.isEmpty ? d.cle : d.libelle}',
        sousTitre: d.cle,
        taille: TailleModale.lg,
        corps: versions.isEmpty
            ? const Text('Aucune version enregistrée : le défaut s’applique.', style: TextStyle(color: JetonsShell.slate600, fontSize: 14))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final v in versions)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DescListeSigh([
                        ('Version', 'v${v.version}${v.dateEffet == null ? ' (défaut semé)' : ''}'),
                        ('Valeur', _libelleValeur(d, v.valeur)),
                        ('Effective depuis', v.dateEffet == null ? 'toujours' : _dateFr(v.dateEffet!)),
                        ('Réglée par', v.auteur),
                        if (v.motif != null) ('Motif', v.motif),
                      ])),
              ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  void _regler(BuildContext ctx) {
    final champs = <ChampDef>[
      switch (d.type) {
        TypeParametre.booleen => ChampDef(
            nom: 'valeur', libelle: 'Nouvelle valeur', type: TypeChamp.select, requis: true, options: const [OptionChamp('oui', 'Oui'), OptionChamp('non', 'Non')]),
        TypeParametre.choix => ChampDef(
            nom: 'valeur',
            libelle: 'Nouvelle valeur',
            type: TypeChamp.select,
            requis: true,
            options: [for (final k in d.choix ?? const <String>[]) OptionChamp(k, d.libellesChoix[k] ?? k)]),
        TypeParametre.entier || TypeParametre.nombre => const ChampDef(nom: 'valeur', libelle: 'Nouvelle valeur', type: TypeChamp.nombre, requis: true),
        TypeParametre.texte => const ChampDef(nom: 'valeur', libelle: 'Nouvelle valeur', requis: true),
      },
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Effective à partir du',
          type: TypeChamp.date,
          requis: true,
          aide: 'Les pièces émises à cette date ou après l’utiliseront. Une date antérieure à une pièce qui a déjà utilisé la valeur est refusée.'),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, col: ColChamp.plein),
    ];
    final initial = p.valeur is bool ? (p.valeur == true ? 'oui' : 'non') : p.valeur;
    final ctl = ControleurFormulaire(champs, {'valeur': initial, 'dateEffet': aujourdhui});
    afficherModale<void>(ctx,
        titre: 'Régler : ${d.libelle.isEmpty ? d.cle : d.libelle}',
        sousTitre: 'Valeur actuelle : ${_libelleValeur(d, p.valeur)}',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final valeur = _convertir(saisie['valeur']);
                    if (valeur == null) {
                      ToastsSigh.afficher(ctx, 'La valeur saisie n’est pas du bon type.', type: TypeToast.erreur, detail: 'Saisir ${_typeLisible(d.type)}.');
                      return;
                    }
                    // Les réglages de l'AIB (lot L2) passent par le contrôle du moteur : rôle d'écriture, compte au plan, motif, date postérieure, activation du
                    // branchement complète. Un refus se NOMME (code AIB_*, motif, geste) et rien n'est écrit.
                    final aib = AibPoste(c.magasin,
                        auteur: () => acteurNom(c), role: c.role, libelleRole: c.donnees?.matrice.libelle(c.role) ?? c.role, fileul: !estMere, horloge: () => c.aujourdhui);
                    final refusAib = aib.controlerReglage(d.cle, valeur.$1, '${saisie['dateEffet']}', '${saisie['motif'] ?? ''}');
                    if (refusAib != null) {
                      ToastsSigh.afficher(ctx, '${refusAib['code']} : ${refusAib['motif']}', type: TypeToast.erreur, detail: '${refusAib['geste'] ?? ''}', duree: const Duration(seconds: 12));
                      return;
                    }
                    final r = service.regler(d.cle, valeur.$1, '${saisie['dateEffet']}', motif: '${saisie['motif'] ?? ''}');
                    if (!r.ok) {
                      // Un refus se NOMME : le motif dit pourquoi, le geste dit quoi faire.
                      ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste, duree: const Duration(seconds: 10));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Nouvelle version enregistrée.',
                        type: TypeToast.succes, detail: 'Version ${r.valeur!.version}, effective à partir du ${_dateFr('${saisie['dateEffet']}')}. Elle part vers les fileuls et le relais (chiffrée).');
                  }),
            ]);
  }

  /// La saisie convertie au type du paramètre ; `null` si elle n'en est pas (le contrôle fin, lui, est celui du domaine). Enveloppée dans un enregistrement : une
  /// valeur booléenne `false` ne se confond ainsi pas avec « pas de valeur ».
  (Object?,)? _convertir(Object? brut) {
    switch (d.type) {
      case TypeParametre.booleen:
        return brut == 'oui' ? (true,) : (brut == 'non' ? (false,) : null);
      case TypeParametre.choix:
      case TypeParametre.texte:
        return brut is String ? (brut,) : null;
      case TypeParametre.entier:
        final n = int.tryParse('$brut'.trim());
        return n == null ? null : (n,);
      case TypeParametre.nombre:
        final n = num.tryParse('$brut'.trim().replaceAll(',', '.'));
        return n == null ? null : (n,);
    }
  }
}

String _typeLisible(TypeParametre t) => switch (t) {
      TypeParametre.booleen => 'oui ou non',
      TypeParametre.choix => 'l’une des valeurs proposées',
      TypeParametre.entier => 'un nombre entier',
      TypeParametre.nombre => 'un nombre',
      TypeParametre.texte => 'un texte',
    };

/// AAAA-MM-JJ → JJ/MM/AAAA (le format de la clinique).
String _dateFr(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}
