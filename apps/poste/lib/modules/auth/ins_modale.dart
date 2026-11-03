import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/etat_installation.dart';
import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';

/// LA MODALE « CONFIGURATIONS À FAIRE AVANT L'UTILISATION » (PRD-POSTE-premiere-installation, EF-INST-03 à 07, PLAN étapes 6 à 8). Elle s'ouvre toute seule sur le
/// tableau de bord de l'administrateur après l'installation, se rouvre par la pastille de la barre, et ne se rouvre plus seule une fois l'assistant clos.
/// Chaque ligne renvoie à un écran EXISTANT : aucun écran de saisie nouveau. ÉCRAN DE LA CIBLE (ECARTS-MAQUETTE, E2100).

/// Les écrans de l'étape B, dans l'ordre : ce sont les écrans `cfg-*` de la maquette (arbitrage de la Direction, 02/11/2026).
const List<(String id, String libelle)> ecransConfigurationsInstallation = [
  ('cfg-entetes', 'Papier à en-tête officiel'),
  ('cfg-modules', 'Activité des modules'),
  ('cfg-tarifs', 'Référentiel tarifaire'),
  ('cfg-natures-facture', 'Natures de facture'),
  ('cfg-comptabilite', 'Paramètres comptables & obligations'),
  ('mecef-config', 'Configuration fiscale (MECeF)'),
  ('m14-roles', 'Rôles & permissions'),
];

/// L'écran du poste pour les appairages (la console de la mère). Absent en mode fileul.
const String ecranAppairages = 'mere-appareils';

/// Ouvre la modale. [aller] : navigation de la coque (ferme la modale, ouvre l'écran). [estMere] : le poste est-il la mère ? [ouvert] : l'écran est-il ouvert au
/// profil ? (une ligne vers un écran fermé reste visible et non cliquable, avec son motif.)
Future<void> ouvrirModaleInstallation(
  BuildContext context, {
  required Magasin magasin,
  required void Function(String ecran) aller,
  required bool estMere,
  required bool Function(String ecran) ouvert,
}) {
  final service = ServiceInstallation.de(magasin);
  return afficherModale<void>(context,
      titre: 'Configurations à faire avant l’utilisation',
      sousTitre: 'Faites ces étapes dans l’ordre : ce qui est réglé sur la mère est repris par les autres postes et les mobiles.',
      taille: TailleModale.lg,
      corps: ListenableBuilder(
          listenable: service,
          builder: (cc, _) => _Corps(service: service, magasin: magasin, aller: (e) {
                Navigator.of(cc, rootNavigator: true).pop();
                aller(e);
              }, estMere: estMere, ouvert: ouvert)),
      pied: (fermer) => [BoutonSigh(key: const Key('ins:modale-fermer'), libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
}

class _Corps extends StatefulWidget {
  const _Corps({required this.service, required this.magasin, required this.aller, required this.estMere, required this.ouvert});
  final ServiceInstallation service;
  final Magasin magasin;
  final void Function(String) aller;
  final bool estMere;
  final bool Function(String) ouvert;

  @override
  State<_Corps> createState() => _EtatCorps();
}

class _EtatCorps extends State<_Corps> {
  Timer? _detection;
  ServiceInstallation get service => widget.service;
  Magasin get magasin => widget.magasin;
  void Function(String) get aller => widget.aller;
  bool get estMere => widget.estMere;
  bool Function(String) get ouvert => widget.ouvert;

  @override
  void initState() {
    super.initState();
    // Les étapes se DÉTECTENT : l'administrateur n'a rien à cocher. Un tour à l'ouverture, puis toutes les deux secondes tant que la modale est là.
    unawaited(service.detecter());
    _detection = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(service.detecter()));
  }

  @override
  void dispose() {
    _detection?.cancel();
    super.dispose();
  }

  EtatInstallation get e => service.etat;

  Widget _pastille(EtapeEtat s) => switch (s) {
        EtapeEtat.faite => const BadgeSigh('Faite', ton: TonSigh.succes),
        EtapeEtat.reportee => const BadgeSigh('Reportée', ton: TonSigh.attention),
        EtapeEtat.aFaire => const BadgeSigh('À faire'),
      };

  /// Une étape : titre, état, motif de verrou s'il y en a un, contenu. Verrouillée = visible, atténuée, non cliquable, avec son motif.
  Widget _etape(BuildContext c, String id, String explication, List<Widget> actions) {
    final verrou = e.motifVerrou(id);
    final rang = etapesInstallation.indexOf(id) + 1;
    return Container(
        key: Key('ins:etape-$id'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: verrou == null ? Colors.white : JetonsShell.slate50,
            border: Border.all(color: JetonsShell.slate200),
            borderRadius: BorderRadius.circular(8)),
        child: Opacity(
            opacity: verrou == null ? 1 : 0.6,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('$rang. ${libellesEtapesInstallation[id]}',
                    style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                _pastille(e.etat(id)),
              ]),
              const SizedBox(height: 4),
              Text(verrou ?? explication, key: Key('ins:motif-$id'), style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
              if (verrou == null && actions.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: actions)],
            ])));
  }

  Widget _lien(String id, String libelle) {
    final ok = ouvert(id);
    return BoutonSigh(
        key: Key('ins:ouvrir-$id'),
        libelle: libelle,
        variante: VarianteBouton.secondaire,
        icone: LucideIcons.externalLink,
        // Un écran fermé à ce profil reste visible mais ne s'ouvre pas : la masquer ferait croire qu'il n'existe pas.
        onPressed: ok ? () => aller(id) : null);
  }

  /// Une ligne de l'étape B : l'écran, ce que la détection en a vu (écrit, vérifié, à faire), et « Rien à changer » pour un écran qu'on a regardé sans le modifier.
  Widget _ligneConfiguration(String id, String libelle, ({bool ecrit, bool verifie}) l) {
    final fait = l.ecrit || l.verifie;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _lien(id, libelle),
      const SizedBox(width: 6),
      if (fait)
        BadgeSigh(l.ecrit ? 'Configurée' : 'Vérifiée', ton: TonSigh.succes)
      else
        InkWell(
            key: Key('ins:verifier-$id'),
            onTap: () => service.verifierConfiguration(id),
            child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('Rien à changer', style: TextStyle(color: JetonsShell.navy700, fontSize: 12, fontWeight: FontWeight.w500)))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final refus = service.motifRefusCloture();
    final lignes = service.lignesConfiguration();
    final admins = service.administrateursActifs();
    final cloture = e.phase == PhaseInstallation.cloturee;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${e.nombreFaites} étape(s) faite(s) sur ${etapesInstallation.length}',
          key: const Key('ins:progression'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
      const SizedBox(height: 12),
      _etape(context, 'mere',
          'Relais web, secret de la mère et clé de clinique. Une seule mère par clinique. Si le relais est injoignable, vous pouvez reporter : rien n’est diffusé tant que la mère n’est pas activée.', [
        if (e.etat('mere') == EtapeEtat.faite)
          const Text('La mère est activée.', style: TextStyle(color: JetonsShell.slate600, fontSize: 12))
        else
          BoutonSigh(
              key: const Key('ins:activer'),
              libelle: e.etat('mere') == EtapeEtat.reportee ? 'Activer maintenant' : 'Activer la mère',
              icone: LucideIcons.server,
              onPressed: () => _modaleActivation(context)),
      ]),
      _etape(context, 'configurations',
          'Réglez la clinique sur ce poste : chaque réglage part vers le relais et les autres postes. Une configuration est détectée dès qu’elle est enregistrée ; un écran qui n’a rien à changer se marque « Rien à changer ». L’étape se termine toute seule.', [
        for (final (id, libelle) in ecransConfigurationsInstallation) _ligneConfiguration(id, libelle, lignes[id] ?? (ecrit: false, verifie: false)),
      ]),
      _etape(context, 'comptes',
          'Créez les comptes des agents (identifiant, rôle) et donnez-leur un mot de passe. Un SECOND administrateur est obligatoire pour clore l’assistant : $admins sur ${ServiceInstallation.administrateursRequis} pour l’instant. L’étape se termine toute seule dès que le second administrateur existe.',
          [_lien('m14-utilisateurs', 'Comptes utilisateurs')]),
      _etape(context, 'appairages',
          estMere
              ? 'Émettez un code d’appairage (8 caractères, 15 minutes, usage unique) pour chaque poste fileul et chaque mobile. Un poste fileul qui s’appaire reprend les configurations : il n’a rien à refaire.'
              : 'L’appairage des postes et des mobiles se fait depuis la mère : activez-la d’abord (étape 1).',
          [
            if (estMere) _lien(ecranAppairages, 'Appareils et appairage'),
            Text(service.appareilsAppaires == null ? 'Appairages non relevés.' : '${service.appareilsAppaires} appareil(s) appairé(s).',
                key: const Key('ins:appareils'), style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
          ]),
      const SizedBox(height: 4),
      if (cloture)
        const NoteSigh('L’assistant est clos.', icone: LucideIcons.circleCheck)
      else ...[
        if (refus != null) NoteSigh(refus, key: const Key('ins:refus-cloture'), icone: LucideIcons.triangleAlert),
        const SizedBox(height: 8),
        // Le refus est NOMMÉ ci-dessus ; la commande reste visible : la masquer cacherait ce qu'il reste à faire.
        BoutonSigh(
            key: const Key('ins:cloturer'),
            libelle: 'Clore l’assistant',
            icone: LucideIcons.lock,
            onPressed: refus != null ? null : () => _cloturer(context)),
      ],
    ]);
  }

  Future<void> _cloturer(BuildContext context) async {
    final par = magasin.utilisateur;
    final r = await service.cloturer(par: par, maintenant: magasin.horloge());
    if (!context.mounted) return;
    ToastsSigh.afficher(context, r ?? 'L’assistant d’installation est clos.', type: r == null ? TypeToast.succes : TypeToast.erreur);
  }

  void _modaleActivation(BuildContext context) {
    final f = ControleurFormulaire(const [
      ChampDef(
          nom: 'relais',
          libelle: 'Adresse du relais web',
          requis: true,
          col: ColChamp.plein,
          indicatif: 'sighcnt.nassieratoo.com',
          aide: 'L’adresse du site où le relais est installé, sans « https:// » ni rien après le nom (le poste ajoute https://).'),
      ChampDef(
          nom: 'secret',
          libelle: 'Secret de la mère',
          type: TypeChamp.motDePasse,
          requis: true,
          col: ColChamp.plein,
          aide: 'Le même texte que RELAIS_SECRET_MERE dans le fichier .env du relais. Long et aléatoire (32 caractères au moins) ; il identifie la mère auprès du relais.'),
      ChampDef(
          nom: 'cle',
          libelle: 'Clé de clinique (16 caractères au moins)',
          type: TypeChamp.motDePasse,
          requis: true,
          col: ColChamp.plein,
          aide: 'À ranger sur papier, sous scellé : sans elle, rien de ce qui quitte le serveur ne peut être restauré.'),
      ChampDef(nom: 'nom', libelle: 'Nom de ce poste (facultatif)', col: ColChamp.plein, aide: 'Ce que le panneau du relais affichera, par exemple « Poste principal, bureau de la Direction ».'),
    ], {});
    final etat = ValueNotifier<({String? erreur, bool injoignable})>((erreur: null, injoignable: false));
    var occupe = false;
    afficherModale<void>(context,
        titre: 'Activer la mère',
        taille: TailleModale.md,
        corps: ValueListenableBuilder(
            valueListenable: etat,
            builder: (cc, st, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: f),
                  if (st.erreur != null) Padding(padding: const EdgeInsets.only(top: 12), child: NoteSigh(st.erreur!, key: const Key('ins:erreur-activation'), icone: LucideIcons.triangleAlert)),
                  if (st.injoignable)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: BoutonSigh(
                            key: const Key('ins:reporter'),
                            libelle: 'Reporter l’activation',
                            variante: VarianteBouton.secondaire,
                            onPressed: () async {
                              await service.reporterMere();
                              if (cc.mounted) Navigator.of(cc, rootNavigator: true).pop();
                            })),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('ins:activer-valider'),
                  libelle: 'Activer',
                  icone: LucideIcons.server,
                  onPressed: () async {
                    if (occupe) return;
                    final v = f.valider();
                    if (v == null) return;
                    occupe = true;
                    final refus = await service.activer(
                        relais: '${v['relais']}', secretMere: '${v['secret']}', cleClinique: '${v['cle']}', nomPoste: v['nom'] == null || '${v['nom']}'.trim().isEmpty ? null : '${v['nom']}');
                    occupe = false;
                    if (refus == null) {
                      fermer();
                      return;
                    }
                    // La modale reste ouverte avec le refus NOMMÉ ; si le relais ne répond pas, le report est proposé.
                    etat.value = (erreur: refus.motif, injoignable: refus.code == 'relais_injoignable');
                  }),
            ]);
  }
}
