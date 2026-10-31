import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/icones.dart';
import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';
import '../../shell/contexte_ecran.dart';
import 'acc_gabarit.dart';

/// Écrans de support (module SUP, hors ruban : atteints par le menu profil et la recherche globale) — `support.js` — et `plan-du-site` (autonome).
/// Règles et textes dans `packages/domaine/lib/src/acces/acc_support.dart`, rejoués sur les vecteurs de la maquette.

/// Un texte avec les balises de la maquette (`<code>`, `<strong>`, `<em>`) : le kit n'a pas de texte enrichi, on rend les trois balises du contenu.
List<InlineSpan> spansEnrichis(String html, TextStyle base) {
  final out = <InlineSpan>[];
  final re = RegExp(r'<(code|strong|em)>(.*?)</\1>');
  var i = 0;
  String net(String s) => s.replaceAll('&amp;', '&');
  for (final m in re.allMatches(html)) {
    if (m.start > i) out.add(TextSpan(text: net(html.substring(i, m.start)), style: base));
    final t = net(m.group(2)!);
    out.add(switch (m.group(1)) {
      'code' => TextSpan(
          text: t,
          style: base.copyWith(fontFamily: 'LiberationMono', fontSize: (base.fontSize ?? 14) - 1, backgroundColor: JetonsShell.slate100)),
      'strong' => TextSpan(text: t, style: base.copyWith(fontWeight: FontWeight.w600)),
      _ => TextSpan(text: t, style: base.copyWith(fontStyle: FontStyle.italic)),
    });
    i = m.end;
  }
  if (i < html.length) out.add(TextSpan(text: net(html.substring(i)), style: base));
  return out;
}

Widget _titreSection(String titre, String sous) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre, style: const TextStyle(color: JetonsShell.slate900, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600)),
      Text(sous, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
    ]));

// ------------------------------------------------------------------------------------------------------------------------------------------------
// aide-apropos
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranAide extends StatelessWidget with EcranMaquette {
  const EcranAide({super.key});

  @override
  String get titre => 'Aide & À propos';
  @override
  String get description => 'Documentation d’usage : présentation du logiciel, guide des modules et foire aux questions.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final manifeste = _manifesteDe(context);
    final mods = accModules(manifeste);
    final profils = c.magasin.collection('rolesBase').toutes.length;
    final chiffres = accChiffresAide(manifeste, profils);
    return LayoutBuilder(builder: (context, k) {
      final large = k.maxWidth >= 1024;
      final texte = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Le SIGH-CNT est le Système Intégré de Gestion Hospitalière de la ${IdentiteClinique.nom}. Il réunit en une seule application des activités jusqu’ici réparties entre plusieurs logiciels cloisonnés et de nombreux registres papier : dossier patient, consultations, hospitalisation, laboratoire, pharmacie, achats, facturation, assurances, ressources humaines, paie et comptabilité.',
            style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 22.75 / 14)),
        const SizedBox(height: 12),
        const Text(
            'Une donnée saisie une fois circule ensuite d’un module à l’autre : une prescription alimente la facturation, une dispensation décrémente le stock, un planning validé nourrit le calcul des primes.',
            style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 22.75 / 14)),
        const SizedBox(height: 12),
        const NoteSigh(
            'Les quatorze règles de gestion du cahier des charges sont appliquées et rappelées à l’écran là où elles s’imposent : identifiant patient, marge nulle sur les médicaments, stock jamais négatif, signatures de sortie, validité des cartes d’assurance, équilibre des écritures, journalisation et archivage logique.'),
      ]);
      final apropos = CarteSigh(
          titre: 'À propos',
          child: Column(children: [
            for (final l in [
              ('Version', '${accEditeur['version']}'),
              ('Éditeur', '${accEditeur['auteur']}'),
              ('Établissement', IdentiteClinique.nom),
              ('IFU', IdentiteClinique.ifu),
              ('RCCM', IdentiteClinique.rccm),
            ])
              Container(
                  padding: const EdgeInsets.only(bottom: 6, top: 6),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text(l.$1, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(l.$2,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: JetonsShell.slate800, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500))),
                  ])),
          ]));
      final colonnes = k.maxWidth >= 1280 ? 3 : (k.maxWidth >= 640 ? 2 : 1);
      final largeurCarte = (k.maxWidth - (colonnes - 1) * 12) / colonnes - 0.01;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: texte),
            const SizedBox(width: 16),
            Expanded(child: apropos),
          ])
        else ...[texte, const SizedBox(height: 16), apropos],
        const SizedBox(height: 20),
        KpiGrilleSigh(kpis: [
          KpiSigh(libelle: 'Modules fonctionnels', valeur: nombre(chiffres.modules), icone: LucideIcons.layoutGrid, ton: TonSigh.navy),
          KpiSigh(libelle: 'Écrans disponibles', valeur: nombre(chiffres.ecrans), icone: LucideIcons.monitor, ton: TonSigh.info),
          KpiSigh(libelle: 'Règles de gestion appliquées', valeur: '${chiffres.regles}', icone: LucideIcons.shieldCheck, ton: TonSigh.succes),
          KpiSigh(libelle: 'Profils d’utilisateur', valeur: nombre(chiffres.profils), icone: LucideIcons.usersRound, ton: TonSigh.neutre),
        ]),
        const SizedBox(height: 20),
        _titreSection('Modules du logiciel', 'Chaque module ouvre sa page d’accueil, où figurent tous ses écrans.'),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final m in mods)
            SizedBox(
                width: largeurCarte,
                child: _CarteModule(
                    module: m,
                    surTap: () => c.aller('hub-${m.code.toLowerCase()}'))),
        ]),
        const SizedBox(height: 20),
        _titreSection('Foire aux questions', 'Les situations le plus souvent rencontrées, et ce que le système en fait.'),
        Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JetonsShell.slate200),
                boxShadow: JetonsShell.ombreCarte),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Column(children: [
                  for (final (i, q) in accFaq.indexed) _Question(question: q, ouverte: i == 0, premiere: i == 0),
                ]))),
        const SizedBox(height: 20),
        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: JetonsShell.navy50, border: Border.all(color: JetonsShell.navy200), borderRadius: BorderRadius.circular(12)),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 12, children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.headset, size: 20, color: Colors.white)),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('Vous ne trouvez pas de réponse ?',
                        style: TextStyle(color: JetonsShell.navy900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                    Text('Écrivez à l’éditeur : question, suggestion ou signalement d’anomalie. Réponse sous 48 h ouvrées.',
                        style: TextStyle(color: JetonsShell.navy800, fontSize: 12, height: 16 / 12)),
                  ])),
              BoutonSigh(libelle: 'Contacter l’éditeur', icone: LucideIcons.mail, onPressed: () => c.aller('contact-editeur')),
            ])),
      ]);
    });
  }
}

/// Le manifeste, lu dans la coque. L'écran d'aide compte les modules et les écrans du manifeste COMPLET (non filtré par les droits), comme la maquette.
Manifeste _manifesteDe(BuildContext context) => ContexteEcran.of(context).donnees!.manifeste;

class _CarteModule extends StatelessWidget {
  const _CarteModule({required this.module, required this.surTap});
  final AccModuleManifeste module;
  final VoidCallback surTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: surTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JetonsShell.slate200),
              boxShadow: JetonsShell.ombreCarte),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                child: Icon(icone(module.icone), size: 20, color: JetonsShell.navy700)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(module.label, style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                BadgeSigh(module.code, ton: TonSigh.navy),
              ]),
              const SizedBox(height: 4),
              Text(accResumeModule(module.code), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 19.5 / 12)),
              const SizedBox(height: 4),
              Text('Domaine ${module.domaine}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 11, height: 16 / 11)),
            ])),
          ])));
}

class _Question extends StatefulWidget {
  const _Question({required this.question, required this.ouverte, required this.premiere});
  final AccQuestion question;
  final bool ouverte;
  final bool premiere;
  @override
  State<_Question> createState() => _EtatQuestion();
}

class _EtatQuestion extends State<_Question> {
  late bool _ouverte = widget.ouverte;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(border: widget.premiere ? null : const Border(top: BorderSide(color: JetonsShell.slate200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
            onTap: () => setState(() => _ouverte = !_ouverte),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: [
                  Expanded(
                      child: Text(widget.question.q,
                          style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500))),
                  const SizedBox(width: 12),
                  Icon(_ouverte ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: JetonsShell.slate400),
                ]))),
        if (_ouverte)
          Container(
              color: JetonsShell.slate50,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: null,
              child: Text.rich(
                  TextSpan(
                      children: spansEnrichis(widget.question.r, const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 22.75 / 14))),
                  key: Key('aide:reponse:${widget.question.q}'))),
      ]));
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// contact-editeur
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranContactEditeur extends StatefulWidget with EcranMaquette {
  const EcranContactEditeur({super.key});

  @override
  String get titre => 'Contactez l’éditeur';
  @override
  String get description => 'Assistance technique, suggestions d’amélioration et signalement d’anomalies.';

  @override
  State<EcranContactEditeur> createState() => _EtatContact();
}

class _EtatContact extends State<EcranContactEditeur> {
  ControleurFormulaire? _message;
  ControleurFormulaire? _bug;
  String? _capture;

  @override
  void dispose() {
    _message?.dispose();
    _bug?.dispose();
    super.dispose();
  }

  void _enregistrer(ContexteEcran c, Map<String, Object?> donnees) {
    final col = c.magasin.collection('support');
    final reference = accReferenceSupport(c.aujourdhui.year, col.toutes.map((f) => f['reference']));
    final r = col.inserer({
      'reference': reference,
      'date': iso(c.aujourdhui),
      'auteur': c.utilisateur,
      'etat': 'envoyee',
      ...donnees,
    });
    ToastsSigh.afficher(context, accToastDemande('${donnees['type']}'),
        type: TypeToast.succes,
        detail: accDetailDemande(reference),
        annuler: r.annuler);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final manifeste = _manifesteDe(context);
    final options = accOptionsModules(manifeste);
    _message ??= ControleurFormulaire([
      const ChampDef(
          nom: 'objet', libelle: 'Objet', requis: true, col: ColChamp.plein, indicatif: 'ex. : question sur le module Comptabilité'),
      const ChampDef(
          nom: 'message',
          libelle: 'Message',
          type: TypeChamp.textarea,
          lignes: 5,
          requis: true,
          col: ColChamp.plein,
          indicatif: 'Décrivez votre question ou votre suggestion…'),
    ]);
    _bug ??= ControleurFormulaire([
      ChampDef(
          nom: 'module',
          libelle: 'Module concerné',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          // Un code peut revenir (M2 sur trois rangées) : la valeur interne porte le rang, l'écriture au registre porte le code.
          options: [for (final (i, o) in options.indexed) OptionChamp('$i|${o.code}', o.libelle)]),
      const ChampDef(
          nom: 'description',
          libelle: 'Description du problème',
          type: TypeChamp.textarea,
          lignes: 4,
          requis: true,
          col: ColChamp.plein,
          indicatif: 'Que s’est-il passé ? Qu’attendiez-vous à la place ?'),
      const ChampDef(
          nom: 'etapes',
          libelle: 'Étapes pour reproduire',
          type: TypeChamp.textarea,
          lignes: 3,
          col: ColChamp.plein,
          indicatif: '1. Aller dans…   2. Cliquer sur…   3. Le message suivant apparaît…'),
    ]);
    final col = c.magasin.collection('support');
    final principal = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Envoyer un message',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: _message!),
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerRight,
                child: BoutonSigh(
                    libelle: 'Envoyer le message',
                    icone: LucideIcons.send,
                    onPressed: () {
                      final v = _message!;
                      final refus = accControlerMessage('${v['objet']}', '${v['message']}');
                      if (refus != null) {
                        ToastsSigh.afficher(context, refus, type: TypeToast.erreur);
                        return;
                      }
                      _enregistrer(c, accDemandeMessage('${v['objet']}', '${v['message']}'));
                      v.poser('objet', '');
                      v.poser('message', '');
                    })),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Signaler une anomalie',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: _bug!),
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: JetonsShell.slate50, border: Border.all(color: JetonsShell.slate300), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Capture d’écran (facultative)',
                      style: TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    BoutonSigh(
                        libelle: 'Joindre une capture d’écran',
                        icone: LucideIcons.imagePlus,
                        taille: TailleBouton.sm,
                        variante: VarianteBouton.secondaire,
                        // Le poste n'embarque aucun sélecteur de fichier : le nom de la capture se saisit à la main (dans la description).
                        onPressed: () => ToastsSigh.afficher(context, 'Aucun sélecteur de fichier sur ce poste.',
                            type: TypeToast.info, detail: 'Décrire l’écran dans la description : la capture n’est pas jointe à la demande.')),
                    Text(_capture == null ? 'Aucune capture jointe.' : 'Pièce jointe : $_capture',
                        style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                  ]),
                ])),
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerRight,
                child: BoutonSigh(
                    libelle: 'Signaler l’anomalie',
                    variante: VarianteBouton.danger,
                    icone: LucideIcons.bug,
                    onPressed: () {
                      final v = _bug!;
                      final code = '${v['module']}'.contains('|') ? '${v['module']}'.split('|').last : '${v['module']}';
                      final refus = accControlerAnomalie(code, '${v['description']}');
                      if (refus != null) {
                        ToastsSigh.afficher(context, refus, type: TypeToast.erreur);
                        return;
                      }
                      final etapes = '${v['etapes']}'.trim().isEmpty ? null : '${v['etapes']}';
                      _enregistrer(c, accDemandeAnomalie(code, '${v['description']}', etapes, _capture));
                      v.poser('description', '');
                      v.poser('etapes', '');
                      setState(() => _capture = null);
                    })),
          ])),
      const SizedBox(height: 16),
      ListenableBuilder(
          listenable: col,
          builder: (context, _) {
            final lignes = [...col.actives]..sort((a, b) => '${b['reference']}'.compareTo('${a['reference']}'));
            if (lignes.isEmpty) return const SizedBox.shrink();
            return CarteSigh(
                titre: 'Demandes envoyées',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Référence', (r) => '${r['reference']}', rendu: (r) => mono('${r['reference']}')),
                  ColonneMini('Date', (r) => dateIsoFr(r['date'])),
                  ColonneMini('Nature', (r) => r['type'] == 'anomalie' ? 'Anomalie' : 'Message',
                      rendu: (r) => r['type'] == 'anomalie' ? const BadgeSigh('Anomalie', ton: TonSigh.danger) : const BadgeSigh('Message', ton: TonSigh.info)),
                  ColonneMini('Objet', (r) => '${r['objet']}'),
                  ColonneMini('Module', (r) => r['module'] == null ? '—' : '${r['module']}'),
                  ColonneMini('État', (r) => 'Envoyée', rendu: (r) => const BadgeSigh('Envoyée', ton: TonSigh.succes)),
                ], lignes: lignes.take(10).toList()));
          }),
    ]);
    final lateral = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Coordonnées de l’éditeur',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
                  child: Text(initialesPoste('${accEditeur['auteur']}'),
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${accEditeur['auteur']}',
                    style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                const Text('Éditeur du logiciel SIGH-CNT', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ])),
            ]),
            const SizedBox(height: 12),
            for (final l in [
              (LucideIcons.mail, (accEditeur['emails'] as List).join('   ·   ')),
              (LucideIcons.phone, '${accEditeur['telephone']}'),
              (LucideIcons.clock, '${accEditeur['horaires']}'),
            ])
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 2), child: Icon(l.$1, size: 16, color: JetonsShell.slate400)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.$2, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
                  ])),
          ])),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Avant de nous écrire',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.lightbulb, size: 16, color: JetonsShell.warning500)),
              SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'La réponse se trouve peut-être déjà dans la documentation : présentation des modules, règles de gestion et questions fréquentes y sont réunies.',
                      style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14))),
            ]),
            const SizedBox(height: 12),
            BoutonSigh(libelle: 'Consulter l’aide & la FAQ', icone: LucideIcons.lifeBuoy, onPressed: () => c.aller('aide-apropos')),
          ])),
      const SizedBox(height: 16),
      const NoteSigh(
          'Les demandes envoyées depuis cet écran sont enregistrées et journalisées comme toute autre opération : elles restent consultables sous les formulaires.'),
    ]);
    return LayoutBuilder(builder: (context, k) {
      if (k.maxWidth < 1024) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [principal, const SizedBox(height: 16), lateral]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: principal),
        const SizedBox(width: 16),
        Expanded(child: lateral),
      ]);
    });
  }
}

/// Initiales (`C.initials`).
String initialesPoste(String nom) => nom.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();

// ------------------------------------------------------------------------------------------------------------------------------------------------
// plan-du-site — autonome
// ------------------------------------------------------------------------------------------------------------------------------------------------

class EcranPlanDuSite extends StatelessWidget with EcranAutonome {
  const EcranPlanDuSite({super.key});

  @override
  Widget build(BuildContext context) {
    final x = ContexteAutonome.of(context);
    final manifeste = x.donnees!.manifeste;
    final plan = accPlanDuSite(manifeste, accEcransSysteme(manifeste));
    return Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1152),
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: LayoutBuilder(builder: (context, k) {
                          final colonnes = k.maxWidth >= 1024 ? 3 : (k.maxWidth >= 768 ? 2 : 1);
                          final largeur = (k.maxWidth - (colonnes - 1) * 12) / colonnes - 0.01;
                          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 12, children: [
                                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                                    Text('Plan du site',
                                        style: TextStyle(
                                            color: JetonsShell.slate900, fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
                                    SizedBox(height: 4),
                                    Text('Inventaire de tous les écrans du prototype, organisés par domaine et par module.',
                                        style: TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14)),
                                  ]),
                                  BoutonSigh(
                                      libelle: 'Retour à l’application',
                                      icone: LucideIcons.arrowLeft,
                                      onPressed: () => x.aller(x.accueil())),
                                ])),
                            for (final s in plan.sections)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Row(children: [
                                          Icon(icone(s.icone), size: 16, color: JetonsShell.slate500),
                                          const SizedBox(width: 8),
                                          Text(s.domaine.toUpperCase(),
                                              style: const TextStyle(
                                                  color: JetonsShell.slate500,
                                                  fontSize: 14,
                                                  height: 20 / 14,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.7)),
                                        ])),
                                    Wrap(spacing: 12, runSpacing: 12, children: [
                                      for (final m in s.modules) SizedBox(width: largeur, child: _CartePlan(module: m, surTap: x.aller)),
                                    ]),
                                  ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: Text('ACCÈS ET PAGES SYSTÈME',
                                      style: TextStyle(
                                          color: JetonsShell.slate500, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, letterSpacing: 0.7))),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final e in plan.systeme)
                                  BoutonSigh(
                                      libelle: e.label, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => x.aller(e.id)),
                              ]),
                            ]),
                            Padding(
                                padding: const EdgeInsets.only(top: 32),
                                child: Text(plan.pied, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
                          ]);
                        }))))));
  }
}

class _CartePlan extends StatelessWidget {
  const _CartePlan({required this.module, required this.surTap});
  final AccPlanModule module;
  final void Function(String id) surTap;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JetonsShell.slate200),
          boxShadow: JetonsShell.ombreCarte),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icone(module.icone), size: 14, color: JetonsShell.navy700)),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(module.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              BadgeSigh(module.code, ton: TonSigh.navy),
            ])),
        for (final e in module.ecrans)
          InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => surTap(e.id),
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    Icon(icone(e.icone ?? module.icone), size: 14, color: JetonsShell.slate400),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12))),
                  ]))),
      ]));
}
