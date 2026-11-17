# Correctif focus tvOS (H20) — transmission vers le projet réel

Objectif : tout ce qu'il faut pour porter le correctif dans l'app tvOS réelle et le tester en conditions réelles.
L'implémentation propre est dans cette branche (`fix/focus-h20`). L'enquête complète (hypothèses H13–H22 dans
`focus-invest.md`, canal de log `[FOCUS]`, banc XCUITest, scripts de stress, agent et skill) est conservée sur la branche
`investigation/h13-h22-archive`.

## 1. Le problème

Une `UICollectionView` (compositional layout + diffable data source) contient une cellule dont le contenu est SwiftUI,
posé via `UIHostingConfiguration`, avec **plusieurs boutons focusables** (le jumbotron).
Parfois le moteur de focus saute la cellule ou le focus se perd en y naviguant :

- aller Bas/Haut au-delà du jumbotron le saute (ex. S2 → S4), ou
- le focus entre puis est éjecté (`nil`), ou les boutons ne reçoivent jamais le focus.

### Cause racine (établie sur simulateur et vraie Apple TV)

Une cellule `UIHostingConfiguration` n'expose **aucun élément focusable SwiftUI** quand elle n'est pas affichée, et
les **perd après un cycle caché → visible**. La collection view garde les cellules hors écran avec
`isHidden = true` ; quand la cellule revient, ses boutons SwiftUI ne sont plus focusables.

- Réassigner une configuration par-dessus l'existante met à jour la vue d'hébergement **sur place** et ne
  **restaure pas** les éléments focusables.
- Mettre `contentConfiguration = nil` puis une nouvelle configuration crée une **nouvelle vue d'hébergement**, ce qui les restaure.
- Une cellule affichée puis cachée est morte même si elle n'a jamais eu le focus.
- Les cartes SwiftUI du même écran fonctionnent car la cellule elle-même est focusable (elles n'ont pas de boutons internes à atteindre).

## 2. Le correctif (H20, « trampoline »)

Idée : tant que le focus est ailleurs, **la cellule elle-même est focusable** (le moteur peut toujours atterrir dessus,
comme sur les cartes qui marchent). Quand elle reçoit le focus, elle **le passe à ses boutons SwiftUI**, en recréant
d'abord le contenu SwiftUI **seulement si nécessaire**.

1. `canBecomeFocused = enabled && !focusIsInside && !redirecting`.
2. `didUpdateFocus` : quand `next === self` → `startTrampoline()`.
3. `startTrampoline()` : si `contentIsStale` → recréer le contenu (`nil` puis nouvelle configuration) ; sinon ne rien faire
   (performance). Puis passer le focus (tout de suite si affichée, sinon quand `willDisplay` se déclenche).
4. Passage du focus : `preferredFocusEnvironments = [contentView]` pendant `redirecting`, puis
   `setNeedsFocusUpdate()` + `updateFocusIfNeeded()`, **réessayé à chaque image** (max 60) jusqu'à ce que le focus soit à l'intérieur.
5. `contentIsStale` est posé dans `didEndDisplaying` et levé uniquement par une recréation ou par une configuration assignée
   à une cellule qui n'en avait **aucune** (nouvelle vue d'hébergement).
6. Filet de sécurité : si le passage est toujours bloqué à la tentative 30 (≈0,5 s), recréer le contenu une fois de plus (« recovery ») et continuer.

### Détail critique trouvé par le test de stress sur l'appareil

Au re-dequeue, l'enregistrement de la cellule assigne une configuration **par-dessus** l'existante. Cela ne doit **pas**
marquer le contenu comme frais (la vue d'hébergement est mise à jour sur place, les éléments focusables restent morts).
La version initiale le marquait frais → 154 échecs sur 1006. Corrigé par `didConfigure(replacedExistingContent:)`.

### Règles de performance (exigence centrale)

- Recréer seulement quand la cellule est sortie de l'écran (28 % des entrées dans le test de stress).
- Aucun délai fixe : le passage du focus est tenté à chaque image ; il réussit en ≈16 ms quand le contenu est valide.
- Aucun travail tant que le focus est dans la cellule.

## 3. Code à porter

### 3.1 La cellule (`FocusProblem/SwiftUIPassthroughCell.swift`)

C'est la version commitée dans cette branche : sans logs, sans flag d'hypothèse (le comportement est toujours H20).
Renommer la classe si besoin.

```swift
import UIKit

final class JumbotronHostingCell: UICollectionViewCell {

    /// Posé par l'enregistrement de la cellule : construit une configuration de contenu neuve.
    var makeContentConfiguration: (() -> UIContentConfiguration)?

    private var focusIsInside = false
    private var redirecting = false
    private var contentIsStale = false      // sortie de l'écran après la construction du contenu
    private var isDisplayed = false
    private var handOverPending = false
    private var recoveredThisEntry = false

    override var canBecomeFocused: Bool { !focusIsInside && !redirecting }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if redirecting { return [contentView] }
        let envs = contentView.subviews
        return envs.isEmpty ? super.preferredFocusEnvironments : envs
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let next = context.nextFocusedView
        focusIsInside = next.map { $0 !== self && $0.isDescendant(of: self) } ?? false
        if next === self {
            startTrampoline()
        } else if !focusIsInside {
            redirecting = false
            handOverPending = false
        }
    }

    private func startTrampoline() {
        redirecting = true
        recoveredThisEntry = false
        if contentIsStale { rebuildContent() }
        if isDisplayed { handOver(attempt: 1) } else { handOverPending = true }   // repris par cellWillDisplay()
    }

    /// On retire d'abord la configuration pour qu'UIKit crée une nouvelle vue d'hébergement.
    private func rebuildContent() {
        guard let make = makeContentConfiguration else { return }
        contentConfiguration = nil
        contentConfiguration = make()
        contentIsStale = false
    }

    /// À appeler depuis l'enregistrement à chaque assignation d'une configuration.
    /// Seule une configuration donnée à une cellule qui n'en avait pas crée une vue d'hébergement fraîche.
    func didConfigure(replacedExistingContent: Bool) {
        if !replacedExistingContent { contentIsStale = false }
    }

    // Appelé par le delegate de la collection view
    func cellWillDisplay() {
        isDisplayed = true
        if handOverPending { handOverPending = false; handOver(attempt: 1) }
    }

    func cellDidEndDisplaying() {
        isDisplayed = false
        contentIsStale = true
    }

    private func handOver(attempt: Int) {
        let delay: TimeInterval = attempt == 1 ? 0 : 1.0 / 60.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performHandOver(attempt: attempt)
        }
    }

    private func performHandOver(attempt: Int) {
        guard redirecting else { return }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        if !focusIsInside && attempt < 60 {
            if attempt == 30 && !recoveredThisEntry {      // filet de sécurité
                recoveredThisEntry = true
                rebuildContent()
            }
            handOver(attempt: attempt + 1)
            return
        }
        redirecting = false
    }
}
```

### 3.2 Enregistrement

```swift
let registration = UICollectionView.CellRegistration<JumbotronHostingCell, Item> { cell, _, item in
    let hadConfiguration = cell.contentConfiguration != nil      // à lire AVANT l'assignation
    let make: () -> UIContentConfiguration = {
        UIHostingConfiguration { JumbotronView(/* … */) }.margins(.all, 0)
    }
    cell.makeContentConfiguration = make
    cell.contentConfiguration = make()
    cell.didConfigure(replacedExistingContent: hadConfiguration)
}
```

Si les données du jumbotron sont rafraîchies sur place, `make` doit capturer le **dernier** modèle (le réassigner à chaque fois).

### 3.3 Delegate de la collection view (obligatoire)

```swift
func collectionView(_ cv: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt ip: IndexPath) {
    (cell as? JumbotronHostingCell)?.cellWillDisplay()
}
func collectionView(_ cv: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt ip: IndexPath) {
    (cell as? JumbotronHostingCell)?.cellDidEndDisplaying()
}
```

Si le projet réel implémente déjà ces méthodes de delegate (ou enveloppe le delegate), transmettre à la cellule à cet endroit.

## 4. Notes d'intégration pour l'app réelle

- Le vrai jumbotron est **unique**, en haut de Home sous la barre d'onglets, avec 2 boutons. Les lignes à plusieurs jumbotrons n'existent pas.
- Vérifier `remembersLastFocusedIndexPath`, les `UIFocusGuide`, `.focusSection()` et les overrides de `shouldUpdateFocus` dans le
  vrai contrôleur : ils peuvent interférer avec le trampoline (le POC utilise `remembersLastFocusedIndexPath = false`).
- La cellule ne doit pas être réutilisée pour d'autres types de contenu sans appeler `didConfigure` correctement.
- La recréation du contenu réinitialise le `@State` SwiftUI du jumbotron (index de carrousel, etc.) : garder cet état dans le modèle.
- Le focus atterrit toujours sur le **premier** bouton (Play / principal). La mémoire du dernier bouton focusé n'est pas conservée.

## 5. Comment tester

### 5.1 Banc de test automatique (sur la branche `investigation/h13-h22-archive`)

Pour le réutiliser : `git checkout investigation/h13-h22-archive -- FocusProblemUITests .claude/skills/tvos-focus-hypothesis/scripts`
puis remettre les logs et le flag `-FocusHypothesis` dont il dépend (voir `DebugHelper.swift`, `FocusHypothesis.swift`,
`FrameHitchMonitor.swift` et `SwiftUIPassthroughCell.swift` de cette branche). Le correctif lui-même n'en a pas besoin.

XCUITest pilote la télécommande avec `XCUIRemote.shared.press(...)` (les touches HID du simulateur sont ignorées sur tvOS). L'app écrit le
canal `[FOCUS]` dans `Library/Caches/focus-log.txt` ; les scripts le récupèrent et l'analysent.

```bash
# Séquence standard (simulateur ou appareil)
DEVICE_ID=<udid> .claude/skills/tvos-focus-hypothesis/scripts/run_focus_sequence.sh <out.log> H20
python3 .claude/skills/tvos-focus-hypothesis/scripts/summarize_stress.py <out.log>

# Stress : N lots d'environ 100 entrées aléatoires
DEVICE_ID=<udid> .claude/skills/tvos-focus-hypothesis/scripts/run_focus_stress.sh <outdir> 10 H20
```

Jetons de séquence (`FOCUS_SEQUENCE`) : `down/up/left/right/select`, `*N` répétition, `waitN`, `paceN`, `background`.
Arguments de lancement : `-FocusHypothesis H20`, `-FocusPerf YES` (moniteur d'images sautées), `-FocusVerbose YES`.

Seuls les runs sur **appareil** permettent des conclusions de fiabilité (le simulateur, tvOS 27.2, ne reproduit pas le cas de la reconfiguration).

### 5.2 Signatures de logs à chercher (uniquement avec la version instrumentée de la branche d'archive)

- `trampoline S3 … focused → handing over to SwiftUI`, puis `button S3 Play focused=true` et `perf S3 handover ms=… ok=true`.
- `perf S3 rebuild ms=… reason=stale` (attendu après un masquage), `reason=recovery` (doit être **rare / nul**).
- `perf S3 rebuild skipped (content still valid)` = le chemin rapide.
- Échec : `ok=false`, `move … → nil`, ou `No focusable items found`.

### 5.3 Scénarios manuels à passer dans l'app réelle (non couverts par le POC)

1. Focus initial sur Home : jumbotron en premier sous la barre d'onglets.
2. Haut vers la barre d'onglets, Bas de retour sur le jumbotron, en boucle.
3. Bas vers les onglets de saisons, Haut de retour sur le jumbotron.
4. Scroller pour que le jumbotron quitte l'écran (plusieurs lignes), puis y revenir.
5. Changement d'onglet Home ↔ Live-TV ↔ Home, puis entrée dans le jumbotron.
6. Contenu du jumbotron rafraîchi sur place (rechargement de données) pendant l'affichage, puis navigation ailleurs et retour.
7. App passée en arrière-plan puis au premier plan, puis navigation vers le jumbotron.
8. Appuis rapides répétés Haut/Bas (stress).

Critère de réussite : chaque entrée se termine avec le focus sur un bouton du jumbotron, sans saut ni éjection.

## 6. Résultats (vraie Apple TV SA-ATV-011, tvOS 26.6)

| Run | Entrées | Passages OK | Échecs | Notes |
|---|---|---|---|---|
| Référence (sans correctif) | — | — | — | S3 atteignable seulement parfois ; morte après caché → visible |
| H20, premier stress (avant `didConfigure`) | 1006 | 852 | 154 | tous dus à la reconfiguration marquée comme fraîche |
| Contrôle après correctif (pire seed) | 100 | 100 | 0 | p50 8,5 ms, p95 229 ms |
| **H20 final, séquence standard** | 11 | 11 | 0 | |
| **H20 final, stress 10 lots (2026-11-10)** | **1006** | **1006** | **0** | 0 abandon, 0 éjection nil |

Chiffres du stress final : taux d'échec < 0,30 % (95 %, règle des trois).
Délai de passage du focus : p50 16,1 ms, p95 236,5 ms, p99 259,7 ms, max 268,5 ms.
Contenu recréé sur 28 % des entrées (280) ; 26 % des entrées ont eu une image sautée (263), surtout les entrées avec recréation.
Run précédent sur le chemin H20 standard : 83 entrées, 63 sans recréation à ≈8,5 ms, 20 recréations à 137–205 ms.

### Alternatives rejetées (ne pas réessayer)

- H16 override de `isHidden` (jamais appelé), H17 jumbotron plus court (boutons rognés), H21 rafraîchissement sur place (échec 5/11),
  H22 (régression sur appareil), H19 recréation à chaque entrée avec délai fixe de 0,3 s (fonctionne, plus lent — gardé pour comparaison seulement).

## 7. Limites connues

- ≈150–240 ms et une image sautée à l'entrée quand la cellule est sortie de l'écran (recréation).
- L'état SwiftUI du jumbotron est perdu à la recréation.
- Le focus atterrit toujours sur le premier bouton.
- Pas encore validé sur la mise en page de la vraie page (section 5.3) ; le POC a plusieurs sections que l'app réelle n'a pas.
- Le comportement repose sur des internes UIKit/SwiftUI susceptibles de changer avec les versions de tvOS : relancer le test de stress à chaque version majeure.
