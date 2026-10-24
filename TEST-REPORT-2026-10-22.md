# OpenDezor 1.0.0 (Build 9) – Testbericht

Getestet am 22.10.2026 im iOS-Simulator (iPhone 17 Pro, iOS 26.5), Debug-Build aus `OpenDezor.xcodeproj`
(`BUILD SUCCEEDED`). Simulator-Daten waren nicht frisch: Dezor-Account (Premium), Addon kool.to und
Verlauf waren schon vorhanden. Die App wurde zuletzt per Onboarding auf Deutsch / hell umgestellt.

Methode: manuell per Tippen und Screenshots, dazu `log show` des App-Prozesses. Nicht getestet:
Querformat (Rotation per Tool nicht auslösbar), PiP/AirPlay, Untertitel, Schlaf-Timer, Geschwindigkeit,
Dezor-Login/Connect-Code und Abmelden (bewusst nicht ausgelöst; Passwörter gebe ich nicht ein), Picker
„Qualität/Tonspur/Untertitel", Bilder-Cache-Schalter. Zweite Runde getestet: VPN trennen / Server wechseln /
eigener Proxy, M3U-Import, App-Sperre (siehe F12–F15).

## Fehler (nach Schwere)

### F1 – Suchergebnisse zerstören das Layout der Startseite (hoch, reproduzierbar)
Suche „breaking" im Omnibox → „Suchergebnisse (34)", aber nur 2 Karten sichtbar („Breaking Ground",
„breaking images"), in einem auf ~294 pt Breite abgeschnittenen Streifen mittig auf dem Bildschirm, der
VPN-Pill schwebt in der Bildschirmmitte, die Seite darunter ist verdeckt.
Ursache: `OmniboxView` rendert die Ergebnisliste in sich selbst, und `DashboardView.swift:68-79` legt die
ganze `OmniboxView` neben `VPNStatusPill` in eine `HStack` innerhalb von `.safeAreaInset(edge: .top)`.
Die Ergebnisse (`OmniboxView.swift:152-171`) wachsen damit in die obere Leiste, sind so breit wie die
Suchzeile und strecken die Leiste in die Höhe (Pill wird vertikal zentriert).
Außerdem: Das erwartete Ergebnis „Breaking Bad" ist nicht in den sichtbaren Treffern.

### F2 – Live-TV-Kanäle zeigen nur Schwarz, ohne Fehlermeldung (hoch)
Kanäle „21 POPULLORE .s" und „7 NEWS .s" getestet: Player öffnet, nach 12–15 s weiter schwarzes Bild,
Zeitleiste `00:00 / 00:00`, Pause-Symbol (also „spielt"), kein Fehler-Toast, kein Ladeindikator,
kein Wechsel zur nächsten Quelle. Log: `FigStreamPlayer err=-12860`, `-12783`, `CFHTTP -16848` und
`NSURLErrorDomain -1022` („App Transport Security policy requires the use of a secure connection"),
obwohl `NSAllowsArbitraryLoads` im gebauten Info.plist gesetzt ist. Möglicherweise sind die Streams tot
oder geo-geblockt (nicht geklärt), aber die App muss das dem Nutzer anzeigen. Der gescheiterte Kanal
landet trotzdem im Verlauf („Weiterschauen").

### F3 – Tastatur lässt sich in Bibliothek → Addons nicht schließen (mittel)
Nach Tippen ins URL-Feld verdeckt die Tastatur die Tab-Leiste. Tippen daneben oder Herunterwischen schließt
sie nicht (Seite „gummibandet" nur). Einziger Ausweg: Return-Taste. Fehlt `scrollDismissesKeyboard` /
Tap-Abbruch.

### F4 – Fehler-Toast im Addon-Dialog halb unter der Tastatur (mittel)
„Installation failed: Invalid URL: not a valid addon !!" erscheint direkt über der Tastatur, wird vom
oberen Tastaturrand angeschnitten, roter Text auf dunkelrotem Grund mit niedrigem Kontrast.

### F5 – Settings: Titel und Inhalt überlagern sich beim Scrollen (mittel)
Der Titel „Settings"/„Einstellungen" schwebt ohne Hintergrund über dem scrollenden Inhalt (liegt z. B.
über den Akzentfarb-Kreisen), und der Inhalt scheint unter der Statusleiste durch (Uhrzeit überlappt
Zeilen). Es fehlt ein Material-/Blur-Hintergrund für den Kopfbereich.

### F6 – Erster „Add"-Tap bleibt wirkungslos (niedrig)
Während die Tastatur einblendet, verschiebt sich das Layout um ~10 pt; der erste Tap auf „Add" trifft
daneben, es passiert nichts. Erst der zweite Tap löst die Installation (bzw. den Fehler) aus.

### F7 – Player-Steuerung: unzuverlässige Bedienung (niedrig/mittel)
- Controls blenden nach ~2–3 s aus; der Zurück-Button ist dann nicht treffbar. Mehrfach war ein zweiter
  Tap nötig, um den Player zu verlassen.
- Zwei schnelle Taps lösen die Doppeltipp-Geste aus (−10 s Seek) statt den Zurück-Button zu treffen.
- Hochkant: Steuerelemente liegen mittig auf dem Videobild, Seek-Leiste ganz unten am Bildschirmrand –
  weit auseinander. Das erste Antippen des Bildes zeigt die Controls nicht immer (Einzeltap wartet
  auf Doppeltipp-Erkennung).

### F8 – „Jetzt abspielen" / „Play now" startet nicht direkt (niedrig, evtl. gewollt)
Bei Breaking Bad öffnet der Button eine Quellenliste („Available streams (20)") statt zu spielen.
Die Liste enthält Duplikate: „Server C1 voe.sx" 3×, „Server A1 dood.to" ≥3×, „Server B1 dood.yt" 2×
(vermutlich Addon-Daten, aber ungefiltert). Danach lief der erste Stream einwandfrei.

### F9 – Onboarding: „15-Minuten-Limit" widerspricht dem Backend (niedrig, zu prüfen)
Text auf Seite 5: „…ohne 15-Minuten-Limit unbegrenzt zu streamen". `CLAUDE.md` nennt für anonyme Tokens
`remainingPlayDuration: 300000` (= 5 Minuten). Eine der beiden Angaben ist falsch.

### F10 – Sprachauswahl: Flagge und Code passen nicht (niedrig)
„English" zeigt eine UK-Flagge, darunter aber „US". Eintrag „System" zeigt „EN · DE".

### F11 – Kosmetik / Konsistenz (niedrig)
- Seitenpunkte im Onboarding sind im hellen Modus fast unsichtbar (nur der aktive Punkt ist erkennbar).
- Hintergrund der Onboarding-Seiten hat farbige Glows, obwohl `CLAUDE.md` „flat pages, keine Glows" vorgibt.
- Abschnittsüberschriften auf Discover sitzen unterschiedlich eingerückt („Trending TV channels" x=38 vs.
  „Angesagte Serien" x=44).
- „Live TV & EPG": Titel verspricht EPG, in der Liste ist aber keine Programminfo zu sehen.
- Kanalnamen tragen Suffixe „.s"/„.c" (kommt vom Addon, wird nicht bereinigt); Live-Karten ohne Logos.
- „Angesagte Serien" und „Beliebte Serien" zeigen exakt dieselben Titel.
- Browser-Tab: zwischen Webseite und Tab-Leiste bleibt ein großer leerer Streifen mit Zurück/Vor/Teilen.
- Tab-Leiste überlagert Listeninhalt mit sichtbarem Durchscheinen (Texte schimmern durch das Glas).
- Info-Karte in „About" hat eine nur halb breite Trennlinie unter dem GitHub-Button.
- Addon-Installation existiert doppelt (Bibliothek → Addons und Einstellungen).
- VPN-Sheet bei bestehender Verbindung bietet nur „Weiter"; Trennen ist hier nicht möglich.
- Dezor-Account-Sheet hat gleichzeitig einen Zurück-Pfeil und „Schließen" (doppelte Schließen-Aktion).
- Die Reihe „Trending TV channels" zeigte beim zweiten Laden andere Kanäle (z. B. „NETFLIX STORE .b",
  „1-2-3.TV .c") als beim ersten Start („21 POPULLORE .s", „24 KITCHEN .c"); Reihenfolge nicht stabil.
- Favorit setzen geben kein Feedback außer dem gefüllten Lesezeichen (kein Toast).

### Nachtest (zweite Runde, gleicher Tag)

### F12 – Eigener Proxy bleibt als gewählter Server hängen (mittel)
In VPN & Proxy Schutz → „Eigener Proxy" 127.0.0.1:8080 (SOCKS5) gespeichert: Verbindung scheitert mit
„Proxy-Server nicht erreichbar", Status „VPN nicht verbunden", aber der Button zeigt weiter „VPN Trennen"
(statt „Verbinden"). Danach ist der kaputte Proxy dauerhaft die Auswahl („Custom · Custom host" im
VPN-Gate), auch nach „VPN Trennen". Beim leeren Host passiert beim Tippen auf „Proxy speichern & aktivieren"
nichts, ohne Hinweis. Tastatur schließt dort nur per Return.

### F13 – VPN-Gate erscheint erst nach ~40 s, Wiedergabe startet danach nicht (hoch)
VPN getrennt, Live-TV-Kanal angetippt: Toast „Stream wird vorbereitet…" hängt rund 40 Sekunden, erst
dann kommt das Gate „Sicher streamen". Nach „VPN verbinden" schließt das Gate, der gewählte Kanal startet
aber nicht von selbst (zurück in der Kanalliste, kein Player). Bei Serien: „Jetzt Abspielen" zeigt bei
getrenntem VPN sofort „Keine Quellen gefunden – keine aktiven Stream-Server", obwohl Quellen existieren;
das Gate erscheint dort nicht.

### F14 – M3U-Import: ungültige/leere Eingabe erzeugt Phantom-Kanal (mittel)
Eine nicht erreichbare Playlist-URL (bzw. Text ohne `#EXTM3U`) wird ohne Fehlermeldung „importiert":
es entsteht ein Kanal „IPTV Sender" in der neuen Kategorie „Allgemein". Ursache:
`M3UParser.parse` (`Services/Protocol/M3UParser.swift:42-64`) macht aus jeder Nicht-`#`-Zeile mit gültiger
URL einen Kanal und prüft weder den `#EXTM3U`-Header noch ob die Zeile ein Stream ist; `LiveTVViewModel.importM3U`
(`ViewModels/LiveTVViewModel.swift:93-109`) meldet Erfolg, sobald die Liste nicht leer ist. Zudem
verschluckt die Sheet-Eingabe Fehler: nach dem Import schließt das Sheet ohne Rückmeldung.
(Hinweis: Mehrzeilige Eingaben und „:" / „/" werden vom Simulator-Eingabewerkzeug verfälscht – das ist
kein App-Fehler.)

### F15 – App-Sperre: System-Passcode-Dialog blockiert den Simulator (mittel)
Schalter „App-Sperre" ein → sofort der System-Dialog „Enter iPhone Passcode for OpenDezor" (der Simulator
hat einen Geräte-Passcode, daher greift der Fallback „kein Biometrie → entsperren" aus `AppState.swift:97-112`
nicht). Der Dialog hat keine Abbrechen-Taste; nach Home und Neustart der App erscheint er sofort wieder und
lässt sich ohne Passcode nicht schließen – die eigene Sperre („OpenDezor ist gesperrt") mit „Ohne Face ID
entsperren" und „Sperre ausschalten & deaktivieren" ist dadurch nur kurz sichtbar und nicht bedienbar.
Der Lock-Screen selbst sieht korrekt aus (Texte, Buttons vorhanden).
Folge: Querformat, Untertitel, Schlaf-Timer, Tempo, Dezor-Login und Connect-Code konnten in dieser Runde
nicht mehr getestet werden.

### Dritte Runde (nach Entsperren durch den Nutzer)
Der Passcode-Dialog (F15) wurde vom Nutzer geschlossen; die App-Sperre ist danach aus.
Eingriff beim Testen: In der Simulator-Plist der App (`Library/Preferences/org.opendezor.app.plist`,
`opendezor_settings`) wurde `requireBiometrics` von `true` auf `false` gesetzt (Versuch, die Sperre ohne
Passcode zu lösen, blieb wirkungslos).

Getestet und in Ordnung:
- Player: Untertitel-Sheet („Audio & Untertitel": Tonspur „Unknown", Untertitel Aus/CC), Sync-Regler
  (+1.00 s, Reset), Schlaf-Timer (Menü, 15 Min. → „15m"/„14m" in der Leiste), Tempo-Menü (2.00x gesetzt,
  Anzeige „2.00x"), Vor-/Zurückspringen, Zurück-Button.
- Einstellungen: Picker Qualität (720p/1080p), Tonspur (Deutsch/English), Untertitel (Deutsch/English),
  Schalter „Bilder über Dezor-Cache" (aus/an). Alle Werte danach zurückgesetzt.

### F16 – Player: Tonspurliste zeigt „Unknown" (niedrig)
In „Audio & Untertitel" heißt die einzige Tonspur „Unknown"; der Untertitel-Eintrag „CC" ist kein
sprechender Name (kommt vom HLS-Stream, wird nicht übersetzt oder bereinigt).

### F17 – Player: „Fit" ohne sichtbare Wirkung (niedrig)
Tippen auf „Fit" ändert weder Label noch Bild (Hochformat, 16:9-Quelle); ob die Taste das Seitenverhältnis
wechselt, war nicht erkennbar. Kein Zustandswechsel (z. B. „Fill") in der Beschriftung.

### F18 – Player: Tempo/Timer überlappen Zeitleiste nicht, aber Steuerung blendet in ~3 s aus (niedrig)
Mehrfach musste die Steuerung neu eingeblendet werden, bevor ein Button traf (Einzeltap wartet auf
Doppeltipp-Erkennung, siehe F7).

### F19 – Einstellungen: Dezor-Konto zeigt echte E-Mail und lange Gültigkeit (Hinweis)
Im Account-Sheet steht die volle E-Mail im Klartext (Datenschutz beim Screenshot-Teilen); „Abmelden" ist
ohne Rückfrage ein einzelner Tipp (Bestätigungsdialog nicht geprüft).

### Vierte Runde: Querformat (teilweise)
Der Nutzer hat den Simulator gedreht. Geprüft: Einstellungen, Entdecken (Hero), Browser, Live TV,
Bibliothek, Detailseite, Quellenliste und Player rendern im Querformat ohne Layoutbruch; der Player
zeigt Controls korrekt gedreht. Nicht geprüft: Querformat bei Suche, VPN-Gate, Onboarding.
Hinweis zum Test: Im gedrehten Simulator gelten Touch-Koordinaten gedreht (X = Bildschirm-y, Y = 402 − Bildschirm-x);
die Player-Controls blenden nach ~3 s aus, daher traf der Zurück-Button erst nach mehreren Versuchen (siehe F7/F18).

### F20 – Querformat: Suchergebnisse (F1) auch hier defekt (hoch)
Suche „breaking" im Querformat (Discover): Die Ergebnisliste „Suchergebnisse (34)" sitzt wie in F1 in der
oberen Suchleiste; der VPN-Pill schwebt mitten im Bildschirm, Karten und Titel laufen unter die Tab-Leiste,
Kartentitel („Breaking Ground", „breaking images") sind abgeschnitten und stehen als Platzhalter-Kacheln
(Poster fehlen bei 3 von 4 Treffern). Gleiche Ursache wie F1 (`DashboardView.swift:68-79`).
Touch-Hinweis: bei zweimal gedrehtem Simulator gilt X = 874 − Bildschirm-y, Y = Bildschirm-x.

### Teststand / Blocker
Nicht getestet (bewusst): **Abmelden, Anmelden, Connect-Code**. Das Simulator-Konto ist ein echtes
Dezor-Premium-Konto; ein Abmelden würde die Sitzung beenden und ich kann mich nicht wieder anmelden
(keine Passwort-Eingabe, Connect-Code nur über dezor.net durch den Nutzer).
Nicht getestet (technisch): Querformat – der Simulator lässt sich über die verfügbaren Werkzeuge nicht
drehen (Device ▸ Rotate per osascript ist im Sandbox-Modus blockiert).

### Konsolenwarnungen (technisch)
- 4× `SwiftUI runtime-issues: Publishing changes from within view updates is not allowed` kurz nach dem
  Wechsel auf den Live-TV-Tab / Player (Zustand wird während des View-Updates geändert → undefiniertes
  Verhalten möglich).
- `AVIF … failed err=-39` im WebKit-Content-Prozess (nur Browser, harmlos).
- CoreAudio „LoudnessManager … no plist" (Simulator-Artefakt, ignorieren).

## Funktioniert (geprüft)
- Start: Launch-Animation → VPN-Gate → „Connect VPN" verbindet (London, auto), Status „VPN" grün.
- Discover: Hero-Carousel, Weiterschauen, Reihen mit Karussell-Effekt, Detailseite mit Zoom-Übergang,
  Handlung, Cast, Episoden, Quellenliste, Wiedergabe von Breaking Bad S1E1 (Bild, Seek, Zeit 00:15 / 58:06).
- Player-Controls: Pause, ±10 s, Skip +85 s, Zeitleiste, AirPlay-, Schlaf- und Untertitel-Button,
  Fit, Geschwindigkeit 1.00x; Zurück schließt den Player.
- Browser: DuckDuckGo-Startseite, Adressleiste, Sicherheitsanzeige.
- Live TV: Liste, Suche, Gruppenfilter, Plus-Button.
- Bibliothek: Favoriten (leer-Zustand; Breaking Bad per Lesezeichen hinzugefügt, erscheint danach in
  „Favoriten (1)"), Verlauf (3), Addons (Installieren-Fehlerfall zeigt Toast).
- „Alle anzeigen" öffnet das passende Katalog-Raster mit Suchfeld („Angesagte Serien").
- Dezor-Account-Sheet: Premium aktiv, Laufzeit, Wiedergabezeit 24 Std.
- Einstellungen: Konto (Premium), Darstellung, Wiedergabe, VPN, App-Sperre, Daten, About.
- Onboarding: alle 5 Schritte, Sprachwechsel DE/EN wirkt sofort, Hell/Dunkel wirkt sofort,
  heller Modus ohne „weiß auf weiß" auf den geprüften Seiten (Onboarding, Einstellungen, Discover).
