import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// `cfg-rappels` — « Rappels & messages » : DEUX objets distincts. Le MODÈLE de message est un gabarit administrable, avec ses variables, écrit une fois ;
/// le RAPPEL est son envoi à une occasion donnée. Les confondre obligerait à ressaisir le texte à chaque anniversaire. LE LOGICIEL PRÉPARE, IL N'ENVOIE PAS :
/// il fonctionne hors ligne, sans passerelle SMS ni serveur de messagerie — prétendre l'envoyer serait mentir sur ce qui se passe.
class EcranRappels extends StatefulWidget with EcranMaquette {
  const EcranRappels({super.key});
  @override
  String get titre => 'Rappels & messages';
  @override
  String get description => 'Modèles de message administrables et rappels à échéance : anniversaires, nouvel an, fêtes, rendez-vous.';
  @override
  String get regle =>
      'Le modèle s’écrit une fois, le rappel est son envoi. Les confondre obligerait à ressaisir le texte à chaque occasion. Le logiciel prépare le message et le met en file : il ne l’envoie pas — le prototype fonctionne hors ligne, sans passerelle.';

  @override
  State<EcranRappels> createState() => _EcranRappelsState();
}

class _EcranRappelsState extends State<EcranRappels> {
  bool _amorce = false;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final modeles = c.magasin.collection('modelesMessage');
    final rappels = c.magasin.collection('rappels');
    // L'amorçage vient AVANT le premier rendu (un piège déjà payé trois fois) : les six modèles proposés, à valider par la Direction.
    if (!_amorce) {
      _amorce = true;
      if (modeles.toutes.isEmpty) {
        for (final m in cfaModelesProposes) {
          modeles.inserer({'statut': 'actif', 'occasion': m.$1, 'libelle': m.$2, 'texte': m.$3, 'actif': true, 'source': 'Modèle proposé — à valider par la Direction'}, prefixe: 'MSG');
        }
      }
    }
    return ListenableBuilder(
        listenable: Listenable.merge([modeles, rappels]),
        builder: (ctx, _) {
          final ms = modeles.actives;
          final rs = rappels.actives;
          final enFile = rs.where((r) => r['etat'] == 'en_file').length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis([
              CfaKpi('Modèles de message', nombre(ms.length), 'message-square', 'navy'),
              CfaKpi('Modèles actifs', nombre(ms.where((m) => cfaVrai(m['actif'])).length), 'check-check', 'success'),
              CfaKpi('Rappels préparés', nombre(rs.length), 'bell-ring', 'info'),
              CfaKpi('En file d’envoi', nombre(enFile), 'send', enFile > 0 ? 'warning' : 'neutral', 'le logiciel prépare, il n’envoie pas'),
            ]),
            const SizedBox(height: 16),
            const NoteSigh(
                'Le prototype compose les messages et les met en file. Il ne les envoie pas : la solution fonctionne hors ligne, sans passerelle SMS ni serveur de messagerie. Prétendre l’envoi serait mentir sur ce qui se passe — et la clinique croirait ses patients prévenus.',
                ton: TonSigh.attention,
                icone: LucideIcons.wifiOff),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'modeles', libelle: 'Modèles de message', compte: ms.length, construire: (_) => const _OngletModeles()),
              OngletDef(id: 'rappels', libelle: 'Rappels préparés', compte: rs.length, construire: (_) => const _OngletRappels()),
              OngletDef(id: 'variables', libelle: 'Variables', compte: cfaVariablesMessage.length, construire: (_) => const _OngletVariables()),
            ]),
          ]);
        });
  }
}

String _apercu(ContexteEcran c, Object? texte) =>
    cfaApercuMessage('${texte ?? ''}', clinique: IdentiteClinique.nom, telephone: CfaIdentite.telephoneRdv, jour: iso(c.aujourdhui));

class _OngletModeles extends StatelessWidget {
  const _OngletModeles();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return CfaTableau(
      collection: 'modelesMessage',
      entite: 'Modèle',
      libelleNouveau: 'Nouveau modèle',
      titreCreation: 'Modèle de message',
      prefixeId: 'MSG',
      messageVide: 'Aucun modèle de message.',
      nomExport: 'modeles-message',
      colonnes: [
        const ColonneTableau(cle: 'libelle', libelle: 'Modèle'),
        ColonneTableau(cle: 'occasion', libelle: 'Occasion', texte: (r) => cfaLibelleOccasion(r['occasion'])),
        ColonneTableau(
            cle: 'texte',
            libelle: 'Texte',
            texte: (r) => cfaCoupeTexte('${r['texte'] ?? ''}'),
            rendu: (_, r) => Text(cfaCoupeTexte('${r['texte'] ?? ''}'), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
        ColonneTableau(
            cle: 'actif',
            libelle: 'Actif',
            texte: (r) => cfaVrai(r['actif']) ? 'Oui' : 'Non',
            rendu: (_, r) => cfaVrai(r['actif']) ? const BadgeSigh('Oui', ton: TonSigh.succes) : const BadgeSigh('Non')),
      ],
      champs: (e) => [
        ChampDef(nom: 'occasion', libelle: 'Occasion', type: TypeChamp.select, requis: true, options: [for (final o in cfaOccasions) OptionChamp(o.$1, o.$2)]),
        const ChampDef(nom: 'libelle', libelle: 'Intitulé du modèle', requis: true),
        ChampDef(
            nom: 'texte',
            libelle: 'Texte du message',
            type: TypeChamp.textarea,
            lignes: 5,
            requis: true,
            aide: 'Variables reconnues : ${cfaVariablesMessage.map((x) => x.$1).join(' · ')}'),
        const ChampDef(nom: 'actif', libelle: 'Modèle actif', type: TypeChamp.case_),
      ],
      fiche: (s, e) => e == null ? {'source': 'Rédigé par l’administrateur', ...s} : {...s},
      detail: (ctx, r) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Intitulé', '${r['libelle'] ?? ''}'),
          ('Occasion', cfaLibelleOccasion(r['occasion'])),
          ('Actif', cfaVrai(r['actif']) ? 'Oui' : 'Non'),
          ('Origine', cfaOuTiret(r['source'])),
        ]),
        const SizedBox(height: 16),
        cfaSection('Texte du modèle', Text('${r['texte'] ?? ''}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate600))),
        const SizedBox(height: 16),
        cfaSection(
            'Aperçu, variables remplacées',
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
                child: Text(_apercu(c, r['texte']), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)))),
      ]),
      titreDetail: (r) => '${r['libelle']}',
    );
  }
}

class _OngletRappels extends StatelessWidget {
  const _OngletRappels();

  void _preparer(BuildContext ctx, ContexteEcran c) {
    final col = c.magasin.collection('rappels');
    final depart = RegExp(r'(\d+)$').firstMatch(admReferenceSuivante('RPL-', 5, col.toutes))?.group(1) ?? '1';
    var rang = int.parse(depart);
    final r = cfaPreparerAnniversaires(
        modeles: c.magasin.collection('modelesMessage').actives,
        patients: c.magasin.collection('patients').actives,
        rappelsExistants: col.toutes,
        jour: iso(c.aujourdhui),
        clinique: IdentiteClinique.nom,
        telephone: CfaIdentite.telephoneRdv,
        prochaineRef: () => 'RPL-${(rang++).toString().padLeft(5, '0')}');
    if (r.erreur != null) {
      ToastsSigh.afficher(ctx, r.erreur!, type: TypeToast.erreur);
      return;
    }
    if (r.concernes == 0) {
      ToastsSigh.afficher(ctx, r.message, type: TypeToast.info);
      return;
    }
    for (final f in r.rappels) {
      col.inserer({'statut': 'actif', ...f, '_creePar': c.utilisateur, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: 'RPL');
    }
    ToastsSigh.afficher(ctx, r.message,
        type: r.faits > 0 ? TypeToast.succes : TypeToast.info, detail: 'Les messages sont EN FILE : le logiciel ne les envoie pas.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('rappels');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) => TableauSigh(
              // Plus récent d'abord (`sortBy(dateEcheance).reverse()`).
              lignes: trierPar(col.actives, (r) => r['dateEcheance']).reversed.toList(),
              messageVide: 'Aucun rappel préparé.',
              nomExport: 'rappels',
              actions: [
                if (c.droit.editer)
                  BoutonSigh(libelle: 'Préparer les anniversaires du jour', icone: LucideIcons.cake, taille: TailleBouton.sm, onPressed: () => _preparer(context, c)),
              ],
              colonnes: [
                const ColonneTableau(cle: 'reference', libelle: 'Référence'),
                const ColonneTableau(cle: 'occasion', libelle: 'Occasion'),
                const ColonneTableau(cle: 'destinataire', libelle: 'Destinataire'),
                const ColonneTableau(cle: 'telephone', libelle: 'Téléphone'),
                ColonneTableau(cle: 'dateEcheance', libelle: 'Échéance', texte: (r) => dateFR(DateTime.parse('${r['dateEcheance']}'))),
                ColonneTableau(
                    cle: 'etat',
                    libelle: 'État',
                    texte: (r) => r['etat'] == 'en_file' ? 'En file' : '${r['etat'] ?? ''}',
                    rendu: (_, r) => r['etat'] == 'en_file' ? const BadgeSigh('En file', ton: TonSigh.attention) : BadgeSigh('${r['etat'] ?? ''}')),
              ],
              // Un rappel se consulte et s'archive ; il ne se MODIFIE pas : le message est composé (écart E848 — la maquette y offre un « Modifier » qui échoue).
              actionsLigne: (ctx2, r) => [
                BoutonIcone(
                    icone: LucideIcons.eye,
                    libelle: 'Consulter',
                    onPressed: () => afficherTiroir<void>(ctx2,
                        titre: '${r['reference']}',
                        largeurMax: 672,
                        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          DescListeSigh([
                            ('Référence', '${r['reference'] ?? ''}'),
                            ('Occasion', '${r['occasion'] ?? ''}'),
                            ('Destinataire', '${r['destinataire'] ?? ''}'),
                            ('Téléphone', cfaOuTiret(r['telephone'])),
                            ('Échéance', dateFR(DateTime.parse('${r['dateEcheance']}'))),
                            ('État', '${r['etat'] ?? ''}'),
                          ]),
                          const SizedBox(height: 16),
                          cfaSection(
                              'Message composé',
                              Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
                                  child: Text('${r['message'] ?? ''}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)))),
                        ]))),
                if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => cfaArchiver(ctx2, col, r)),
              ],
            ));
  }
}

class _OngletVariables extends StatelessWidget {
  const _OngletVariables();

  @override
  Widget build(BuildContext context) => cfaPile([
        const NoteSigh(
            'Ces jetons sont remplacés au moment de composer le message. Un jeton inconnu reste tel quel dans le texte — visible, donc corrigeable, plutôt que remplacé par du vide.',
            icone: LucideIcons.braces),
        MiniTableauSigh(colonnes: [
          ColonneMini('Jeton', (l) => '${l['jeton']}'),
          ColonneMini('Remplacé par', (l) => '${l['description']}'),
        ], lignes: [
          for (final v in cfaVariablesMessage) {'jeton': v.$1, 'description': v.$2}
        ]),
      ], espace: 12);
}
