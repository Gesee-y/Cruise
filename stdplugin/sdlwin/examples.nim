## =============================================================
##  SDL3 Windowing Framework — Exemples complets
##
##  Couvre :
##    1. Fenêtre simple avec boucle de jeu
##    2. Entrées clavier (just_pressed / pressed / just_released)
##    3. Entrées souris (mouvement, roue, boutons)
##    4. Texte saisi (SDL_EVENT_TEXT_INPUT)
##    5. Multi-fenêtres
##    6. Plein écran (borderless et exclusif)
##    7. Notifications (NOTIF_*)
##    8. Combinaisons de touches (modificateurs)
##    9. Redimensionnement / repositionnement dynamique
##   10. Gestion propre de la fermeture
## =============================================================

import ../../src/windows/windows
import core

# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 1 — Fenêtre minimale avec boucle de jeu
# ═══════════════════════════════════════════════════════════════════

proc exemple1_fenetre_simple() =
  ## Ouvre une fenêtre 800×600, tourne jusqu'à ce que l'utilisateur
  ## appuie sur Échap ou ferme la fenêtre.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 1 — Fenêtre simple", "800", "600")

  # Connexion au notifier de fermeture : quand la croix est cliquée
  var running = true
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      running = false

  while running:
    app.eventLoop(SDLEventRouter)

    # Quitter sur Échap
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 2 — Clavier : just_pressed / pressed / just_released
# ═══════════════════════════════════════════════════════════════════

proc exemple2_clavier() =
  ## Démontre les trois états d'une touche.
  ##
  ## just_pressed  → se déclenche UNE SEULE FOIS le premier frame où la
  ##                 touche passe de relâchée à enfoncée.
  ## pressed       → vrai tant que la touche est maintenue (y compris
  ##                 le frame just_pressed).
  ## just_released → se déclenche UNE SEULE FOIS le frame où la touche
  ##                 est relâchée.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 2 — Clavier")

  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Détection du bord montant (une seule frame) ──────────────────
    if win.isKeyJustPressed(CKey_Space):
      echo "[ ESPACE ] venait d'être ENFONCÉE"

    # ── Maintien continu ─────────────────────────────────────────────
    if win.isKeyPressed(CKey_W):
      echo "[ W ] maintenue — déplace vers le haut"

    if win.isKeyPressed(CKey_S):
      echo "[ S ] maintenue — déplace vers le bas"

    if win.isKeyPressed(CKey_A):
      echo "[ A ] maintenue — déplace vers la gauche"

    if win.isKeyPressed(CKey_D):
      echo "[ D ] maintenue — déplace vers la droite"

    # ── Bord descendant (une seule frame) ────────────────────────────
    if win.isKeyJustReleased(CKey_Space):
      echo "[ ESPACE ] vient d'être RELÂCHÉE"

    # ── Quitter ──────────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 3 — Souris : mouvement, roue, boutons
# ═══════════════════════════════════════════════════════════════════

proc exemple3_souris() =
  ## Affiche en console les événements souris en temps réel.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 3 — Souris")

  # ── Connexions aux notifiers souris ──────────────────────────────

  NOTIF_MOUSE_MOTION.connect do(w: CWindow, ev: MouseMotionEvent):
    echo "Mouvement  pos=(", ev.x, ",", ev.y, ")  rel=(", ev.xrel, ",", ev.yrel, ")"

  NOTIF_MOUSE_WHEEL.connect do(w: CWindow, ev: MouseWheelEvent):
    echo "Roue  x=", ev.xwheel, "  y=", ev.ywheel

  NOTIF_MOUSE_BUTTON.connect do(w: CWindow, ev: MouseClickEvent):
    let etat = if ev.just_pressed: "ENFONCÉ" elif ev.just_released: "RELÂCHÉ" else: "maintenu"
    echo "Bouton ", ev.button, " → ", etat, "  (clics multiples : ", ev.clicks, ")"

  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Lecture directe des axes ──────────────────────────────────
    let axX = win.getAxis(CMouseAxis_X)
    if axX.kind == AxisMotion and (axX.motion.xrel != 0 or axX.motion.yrel != 0):
      # Déjà affiché par le notifier ci-dessus, mais montre l'accès direct.
      discard

    # ── Lecture directe des boutons ───────────────────────────────
    if win.isMouseButtonJustPressed(CMouseBtn_Left):
      let (mx, my) = win.getMousePosition()
      echo "Clic gauche à (", mx, ",", my, ")"

    if win.isMouseButtonPressed(CMouseBtn_Right):
      echo "Bouton droit maintenu"

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 4 — Saisie de texte (SDL_EVENT_TEXT_INPUT)
# ═══════════════════════════════════════════════════════════════════

proc exemple4_texte() =
  ## Accumule la saisie UTF-8 de l'utilisateur.
  ## win.textInput est réinitialisé à chaque frame par clearFrameState()
  ## (appelé dans eventLoop), donc on concatène soi-même dans `buffer`.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 4 — Saisie texte (écris puis Entre)")

  var buffer = ""
  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # win.textInput contient les caractères tapés CE frame
    if win.textInput.len > 0:
      buffer.add(win.textInput)
      echo "Buffer : [", buffer, "]"

    # Valider avec Entrée
    if win.isKeyJustPressed(CKey_Enter):
      echo "==> Validé : «", buffer, "»"
      buffer = ""

    # Backspace : effacer le dernier caractère UTF-8
    if win.isKeyJustPressed(CKey_Backspace) and buffer.len > 0:
      # Reculer d'un point de code UTF-8 (safe grâce à Nim's string)
      var i = buffer.len - 1
      while i > 0 and (buffer[i].ord and 0xC0) == 0x80:
        dec i
      buffer = buffer[0 ..< i]
      echo "Buffer : [", buffer, "]"

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 5 — Modificateurs de touches (Shift, Ctrl, Alt)
# ═══════════════════════════════════════════════════════════════════

proc exemple5_modificateurs() =
  ## Montre comment lire les modificateurs attachés à chaque KeyboardEvent.
  ## Les champs mkey / pkey sont remplis par detectModifiers() dans
  ## sdl3_events.nim juste après l'insertion dans le sparse-set.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 5 — Modificateurs")

  NOTIF_KEYBOARD_INPUT.connect do(w: CWindow, ev: KeyboardEvent):
    if not ev.just_pressed: return
    let mod1 = if ev.mkey != CKey_None: $ev.mkey else: "—"
    let mod2 = if ev.pkey != CKey_None: $ev.pkey else: "—"
    echo "Touche=", ev.key, "  mod1=", mod1, "  mod2=", mod2

  # Raccourcis classiques construits manuellement
  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # Ctrl+S → sauvegarder
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_S):
      echo "Ctrl+S — Sauvegarde !"

    # Ctrl+Z → annuler
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_Z):
      echo "Ctrl+Z — Annulation !"

    # Shift+F5 → rechargement
    if (win.isKeyPressed(CKey_LShift) or win.isKeyPressed(CKey_RShift)) and
       win.isKeyJustPressed(CKey_F5):
      echo "Shift+F5 — Rechargement forcé !"

    # Alt+F4 → quitter
    if win.isKeyPressed(CKey_LAlt) and win.isKeyJustPressed(CKey_F4):
      running = false

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 6 — Plein écran (borderless et exclusif)
# ═══════════════════════════════════════════════════════════════════

proc exemple6_fullscreen() =
  ## F11 → basculer en plein écran desktop (borderless)
  ## F10 → basculer en plein écran exclusif
  ## Échap → retour fenêtré ou quitter

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 6 — Plein écran  (F11 desktop | F10 exclusif)")

  NOTIF_ERROR.connect do(mes, error: string):
    echo "[ERREUR] ", mes, " — ", error

  NOTIF_WINDOW_FULLSCREEN.connect do(w: CWindow, active: bool, desktop: bool):
    echo "Plein écran → active=", active, "  desktop=", desktop

  var running  = true
  var isFullsc = false

  while running:
    app.eventLoop(SDLEventRouter)

    # ── F11 : plein écran borderless ─────────────────────────────
    if win.isKeyJustPressed(CKey_F11):
      isFullsc = not isFullsc
      win.setFullscreen(isFullsc, desktopResolution = true)

    # ── F10 : plein écran exclusif ───────────────────────────────
    if win.isKeyJustPressed(CKey_F10):
      isFullsc = not isFullsc
      win.setFullscreen(isFullsc, desktopResolution = false)

    # ── Échap : quitter le plein écran ou l'application ──────────
    if win.isKeyJustPressed(CKey_Escape):
      if isFullsc:
        win.setFullscreen(false)
        isFullsc = false
      else:
        running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 7 — Redimensionnement et repositionnement dynamiques
# ═══════════════════════════════════════════════════════════════════

proc exemple7_resize_reposition() =
  ## Touches de contrôle en temps réel de la taille et de la position.
  ##
  ##  +/- (numpad)  → agrandir / rétrécir
  ##  Flèches       → déplacer la fenêtre
  ##  M             → maximiser
  ##  N             → minimiser
  ##  R             → restaurer
  ##  H             → cacher   (réapparaît après 2 s)
  ##  T             → changer le titre

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 7 — Resize/Reposition", "640", "480",
                 "400", "200")

  NOTIF_WINDOW_RESIZED.connect do(w: CWindow, width, height: int):
    echo "Redimensionné → ", width, "×", height

  NOTIF_WINDOW_REPOSITIONED.connect do(w: CWindow, x, y: int):
    echo "Repositionné → (", x, ",", y, ")"

  const STEP_PX  = 20
  const STEP_SZ  = 50
  var titleIdx   = 0
  let titles     = ["Exemple 7", "Hello SDL3 !", "Nim ♥ SDL", "Bonjour !"]
  var running    = true

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Redimensionnement ─────────────────────────────────────────
    if win.isKeyJustPressed(CKey_NumAdd):
      win.resizeWindow(win.width + STEP_SZ, win.height + STEP_SZ)

    if win.isKeyJustPressed(CKey_NumSub):
      let w = max(200, win.width  - STEP_SZ)
      let h = max(150, win.height - STEP_SZ)
      win.resizeWindow(w, h)

    # ── Déplacement ───────────────────────────────────────────────
    if win.isKeyPressed(CKey_Left):
      win.repositionWindow(win.x - STEP_PX, win.y)

    if win.isKeyPressed(CKey_Right):
      win.repositionWindow(win.x + STEP_PX, win.y)

    if win.isKeyPressed(CKey_Up):
      win.repositionWindow(win.x, win.y - STEP_PX)

    if win.isKeyPressed(CKey_Down):
      win.repositionWindow(win.x, win.y + STEP_PX)

    # ── États de la fenêtre ───────────────────────────────────────
    if win.isKeyJustPressed(CKey_M): win.maximizeWindow()
    if win.isKeyJustPressed(CKey_N): win.minimizeWindow()
    if win.isKeyJustPressed(CKey_R): win.restoreWindow()

    if win.isKeyJustPressed(CKey_H):
      win.hideWindow()
      SDL_Delay(2000)   # attend 2 secondes (SDL3 delay)
      win.showWindow()

    # ── Titre ─────────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_T):
      titleIdx = (titleIdx + 1) mod titles.len
      win.setWindowTitle(titles[titleIdx])

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 8 — Multi-fenêtres
# ═══════════════════════════════════════════════════════════════════

proc exemple8_multi_fenetres() =
  ## Deux fenêtres indépendantes gérées par le même CApp.
  ## Chaque fenêtre reçoit ses propres événements via le routage par
  ## SDL_WindowID dans routeEvent().
  ##
  ## W1 : fenêtre principale  (rouge symbolique)
  ## W2 : fenêtre secondaire  (bleue symbolique)
  ##
  ## Fermer W2 ou appuyer sur F2 : détruit uniquement W2.
  ## Échap ou fermer W1 : quitte l'application.

  let app = initSDL3App()

  var w1, w2: SDL3Window
  new(w1); new(w2)

  app.initWindow(w1, "Fenêtre Principale",  "800", "600", "100", "100")
  app.initWindow(w2, "Fenêtre Secondaire",  "400", "300", "950", "100")

  var w2Alive = true
  var running  = true

  # Notifier générique — le `win` permet de savoir d'où vient l'event
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      if win.id == w1.id:
        running = false
      elif win.id == w2.id and w2Alive:
        w2.quitWindow()
        w2Alive = false

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Contrôles sur W1 ─────────────────────────────────────────
    if w1.isKeyJustPressed(CKey_Escape):
      running = false

    # ── Créer/détruire W2 avec F2 ────────────────────────────────
    if w1.isKeyJustPressed(CKey_F2):
      if w2Alive:
        w2.quitWindow()
        w2Alive = false
        echo "W2 détruite"
      else:
        new(w2)
        app.initWindow(w2, "Fenêtre Secondaire (recréée)", "400", "300",
                       "950", "100")
        w2Alive = true
        echo "W2 recréée, id=", w2.id

    # ── Interactions propres à W2 ─────────────────────────────────
    if w2Alive and w2.isKeyJustPressed(CKey_Space):
      echo "[ ESPACE ] dans W2 !"

    w1.updateWindow()
    if w2Alive: w2.updateWindow()

  if w2Alive: w2.quitWindow()
  w1.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 9 — Connecter/déconnecter des notifiers
# ═══════════════════════════════════════════════════════════════════

proc exemple9_notifiers() =
  ## Montre comment connecter et déconnecter dynamiquement des handlers.
  ## P  → met en pause la réception des events clavier (déconnecte le handler)
  ## P  (de nouveau) → reprend

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Exemple 9 — Notifiers dynamiques")

  var paused = false

  # Stocke l'id de connexion pour pouvoir déconnecter
  var kbHandlerID: int

  proc kbHandler(w: CWindow, ev: KeyboardEvent) =
    if ev.just_pressed:
      echo "Touche : ", ev.key

  NOTIF_KEYBOARD_INPUT.connect(kbHandler)

  NOTIF_ERROR.connect do(mes, error: string):
    echo "[ERREUR] ", mes, " | ", error

  NOTIF_WARNING.connect do(mes, warning: string, code: int):
    echo "[WARN] ", mes, " | ", warning, " (code=", code, ")"

  NOTIF_INFO.connect do(mes, info: string, code: int):
    echo "[INFO] ", mes, " | ", info

  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    if win.isKeyJustPressed(CKey_P):
      if paused:
        NOTIF_KEYBOARD_INPUT.connect(kbHandler)
        paused = false
        echo "Reprise des events clavier"
      else:
        NOTIF_KEYBOARD_INPUT.disconnect(kbHandler)
        paused = true
        echo "Events clavier mis en PAUSE"

    # Lire l'erreur SDL courante (si non vide → NOTIF_WARNING émis)
    if win.isKeyJustPressed(CKey_E):
      let err = win.getError()
      if err.len > 0:
        echo "Erreur SDL : ", err

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXEMPLE 10 — Application complète : mini éditeur de texte
# ═══════════════════════════════════════════════════════════════════

proc exemple10_mini_editeur() =
  ## Réunit tout en un mini éditeur de texte en console :
  ##   - Saisie UTF-8 via SDL_EVENT_TEXT_INPUT
  ##   - Backspace, Entrée, Échap
  ##   - Ctrl+C → copier (affiche le contenu)
  ##   - Ctrl+A → tout sélectionner (efface)
  ##   - F11    → plein écran borderless
  ##   - F1     → aide

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Mini Éditeur — F1 aide", "900", "600")

  NOTIF_ERROR.connect do(mes, error: string):
    echo "[ERREUR] ", mes, " | ", error

  var lines  = @[""]          # lignes de texte
  var curLine = 0             # indice de ligne courante
  var isFullscreen = false
  var running = true

  proc printDoc() =
    echo "══════════════════════"
    for i, l in lines:
      let marker = if i == curLine: "▶ " else: "  "
      echo marker, l
    echo "══════════════════════"

  proc printHelp() =
    echo """
    ┌─ AIDE ──────────────────────────────┐
    │  Taper          → insérer du texte  │
    │  Entrée         → nouvelle ligne    │
    │  Backspace      → effacer           │
    │  Ctrl+C         → afficher doc      │
    │  Ctrl+A         → tout effacer      │
    │  F11            → plein écran       │
    │  Échap          → quitter           │
    └──────────────────────────────────────┘"""

  printHelp()

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Saisie caractères ─────────────────────────────────────────
    if win.textInput.len > 0:
      lines[curLine].add(win.textInput)

    # ── Backspace ─────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_Backspace):
      if lines[curLine].len > 0:
        var i = lines[curLine].len - 1
        while i > 0 and (lines[curLine][i].ord and 0xC0) == 0x80:
          dec i
        lines[curLine] = lines[curLine][0 ..< i]
      elif curLine > 0:
        # Fusionner avec la ligne précédente
        let tail = lines[curLine]
        lines.delete(curLine)
        dec curLine
        lines[curLine].add(tail)

    # ── Entrée → nouvelle ligne ───────────────────────────────────
    if win.isKeyJustPressed(CKey_Enter):
      inc curLine
      lines.insert("", curLine)

    # ── Ctrl+C → afficher le document ────────────────────────────
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_C):
      printDoc()

    # ── Ctrl+A → effacer tout ─────────────────────────────────────
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_A):
      lines   = @[""]
      curLine = 0
      echo "(document effacé)"

    # ── F1 → aide ─────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_F1):
      printHelp()

    # ── F11 → plein écran ─────────────────────────────────────────
    if win.isKeyJustPressed(CKey_F11):
      isFullscreen = not isFullscreen
      win.setFullscreen(isFullscreen, desktopResolution = true)

    # ── Échap → quitter ───────────────────────────────────────────
    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# POINT D'ENTRÉE — lance l'exemple désiré
# ═══════════════════════════════════════════════════════════════════

when isMainModule:
  echo """
  Choisissez un exemple :
    1  → Fenêtre simple
    2  → Clavier
    3  → Souris
    4  → Saisie de texte
    5  → Modificateurs
    6  → Plein écran
    7  → Resize / Reposition
    8  → Multi-fenêtres
    9  → Notifiers dynamiques
   10  → Mini éditeur
  """
  let choix = readLine(stdin)
  case choix
  of "1":  exemple1_fenetre_simple()
  of "2":  exemple2_clavier()
  of "3":  exemple3_souris()
  of "4":  exemple4_texte()
  of "5":  exemple5_modificateurs()
  of "6":  exemple6_fullscreen()
  of "7":  exemple7_resize_reposition()
  of "8":  exemple8_multi_fenetres()
  of "9":  exemple9_notifiers()
  of "10": exemple10_mini_editeur()
  else:
    echo "Choix invalide."