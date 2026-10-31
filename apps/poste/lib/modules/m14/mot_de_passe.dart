import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/identifiants.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Le GESTE « Définir le mot de passe » d'un compte (m14-utilisateurs), distinct de « corriger une fiche » : il se voit au journal (RG-12), il exige le droit
/// d'écrire de l'écran, et il est la seule façon de donner un mot de passe à un compte du jeu (les comptes n'ont aucun identifiant avant que l'administrateur
/// en définisse un). Le secret n'est ni gardé ni journalisé : seul le haché Argon2id l'est, dans `identifiants`.
///
/// « Générer un mot de passe provisoire » tire un mot de passe aléatoire qui respecte la politique et l'AFFICHE dans la modale, UNE fois : l'administrateur le
/// communique à l'agent, qui devra le changer à sa première connexion.
void afficherModaleMotDePasse(BuildContext ctx, ContexteEcran c, Fiche compte) {
  final svc = ServiceIdentifiants.de(c.magasin);
  final id = '${compte['id']}';
  final identifiant = '${compte['identifiant'] ?? ''}';
  final f = ControleurFormulaire(const [
    ChampDef(nom: 'nouveau', libelle: 'Nouveau mot de passe', type: TypeChamp.motDePasse, requis: true, col: ColChamp.plein),
    ChampDef(nom: 'confirmation', libelle: 'Confirmer le mot de passe', type: TypeChamp.motDePasse, requis: true, col: ColChamp.plein),
    ChampDef(nom: 'doitChanger', libelle: 'Changement obligatoire à la première connexion', type: TypeChamp.case_, col: ColChamp.plein),
  ], {'doitChanger': true});
  String? provisoire;
  var occupe = false;
  afficherModale<void>(ctx,
      titre: 'Définir le mot de passe',
      sousTitre: '$identifiant, ${compte['nomComplet'] ?? ''}',
      taille: TailleModale.md,
      corps: StatefulBuilder(
          builder: (cc, maj) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                NoteSigh(svc.possede(id)
                    ? 'Ce compte a déjà un mot de passe : le nouveau le remplace et lève un éventuel verrou.'
                    : 'Ce compte n’a pas encore de mot de passe : il ne peut pas ouvrir de session tant qu’il n’en a pas.'),
                const SizedBox(height: 12),
                FormulaireSigh(controleur: f),
                const SizedBox(height: 8),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final r in accRegleMotDePasse)
                        Text(r, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
                    ])),
                const SizedBox(height: 8),
                BoutonSigh(
                    libelle: 'Générer un mot de passe provisoire',
                    variante: VarianteBouton.secondaire,
                    icone: LucideIcons.dices,
                    onPressed: () {
                      final p = accGenererMotDePasseProvisoire(ServiceIdentifiants.aleatoire());
                      f.poser('nouveau', p);
                      f.poser('confirmation', p);
                      f.poser('doitChanger', true);
                      maj(() => provisoire = p);
                    }),
                if (provisoire != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Mot de passe provisoire (affiché une seule fois, à communiquer à l’agent) : '),
                            TextSpan(
                                text: provisoire,
                                style: const TextStyle(fontFamily: 'LiberationMono', fontWeight: FontWeight.w700, color: JetonsShell.slate900)),
                          ]),
                          key: const Key('m14:mdp-provisoire'),
                          style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12))),
              ])),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Définir le mot de passe',
                icone: LucideIcons.keyRound,
                onPressed: () async {
                  if (occupe) return;
                  final v = f.valider();
                  if (v == null) return;
                  final refus = accControlerNouveauMotDePasse('${v['nouveau']}', '${v['confirmation']}', identifiant: identifiant);
                  if (refus != null) {
                    ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
                    return;
                  }
                  occupe = true;
                  await svc.definir(id, '${v['nouveau']}', par: c.agent.nom, doitChanger: v['doitChanger'] == true, maintenant: c.aujourdhui);
                  fermer();
                  if (ctx.mounted) {
                    ToastsSigh.afficher(ctx, 'Mot de passe défini.',
                        type: TypeToast.succes, detail: 'Conservé haché (Argon2id) ; ${v['doitChanger'] == true ? 'l’agent devra le changer à sa première connexion.' : 'aucun changement imposé.'}');
                  }
                }),
          ]);
}

/// L'état de l'identifiant d'un compte, pour la fiche : « défini le … », « verrouillé jusqu'à … », « non défini ». Jamais le haché.
String etatIdentifiant(Magasin m, String utilisateurId, DateTime maintenant) {
  final f = ServiceIdentifiants.de(m).fiche(utilisateurId);
  if (f == null) return 'Non défini : le compte ne peut pas ouvrir de session';
  final fin = accVerrouJusqua(f, maintenant);
  if (fin != null) return 'Verrouillé jusqu’à ${fin.hour.toString().padLeft(2, '0')}:${fin.minute.toString().padLeft(2, '0')}';
  final defini = '${f['definiLe'] ?? ''}'.split('T').first;
  final suite = accChangementObligatoire(f, maintenant) ? ' (changement obligatoire à la prochaine connexion)' : '';
  return 'Défini le $defini$suite';
}
