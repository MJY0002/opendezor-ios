# OpenDezor 1.1.0 (Build 10)

Fehlerbehebungs-Release nach einem vollständigen manuellen Durchlauf der App im iOS-Simulator
(iPhone 17 Pro, iOS 26.5, Hoch- und Querformat). Alle gefundenen Fehler sind unten aufgeführt –
mit Status. Alle Unit-Tests laufen durch (2 neu für den M3U-Parser).

Hinweis: Die IPA ist ad-hoc signiert (Sideloading über AltStore / Sideloadly / TrollStore), wie 1.0.0.

## Entfernt

- **App-Sperre (Face ID / Passcode beim Start)**: Einstellung, Sperrbildschirm und `NSFaceIDUsageDescription` sind entfernt. Die App startet ohne Entsperr-Abfrage (löst zugleich F15). 132 Unit-Tests (der Test der Sperr-Einstellung entfällt).

## Behoben

| ID | Fehler | Behebung | Geprüft |
|----|--------|----------|---------|
| F1 / F20 | Suchergebnisse zerstörten das Layout der Startseite (Hoch- und Querformat): Ergebnisliste steckte in der angehefteten Suchleiste neben dem VPN-Pill, Karten abgeschnitten, Pill mitten im Bild | Ergebnisse (`OmniboxResultsView`) stehen jetzt im Seiteninhalt, die Suchleiste bleibt schmal | Simulator ✔ |
| F2 | Live-TV-Kanal: schwarzes Bild bei 00:00 ohne Fehlermeldung, nächste Quelle wurde nie versucht | Watchdog im Player: 30 s ohne Bild gilt als Fehler → nächste Quelle bzw. Fehlermeldung; sind alle Quellen tot, schließt der Player und zeigt eine Meldung | Simulator ✔ (Fehlermeldung, Player schließt) |
| F14 | M3U-Import erzeugte aus beliebigem Text einen Phantom-Kanal „IPTV Sender" und meldete Erfolg | Parser verlangt `#EXTM3U`/`#EXTINF` und gültige Stream-URLs; Import meldet „Keine Sender gefunden" | Simulator ✔, Unit-Tests ✔ |
| F13 | VPN-Gate: nach „VPN verbinden" startete die gewählte Wiedergabe nicht von selbst; Detailseite „Jetzt Abspielen" zeigte bei getrenntem VPN „Keine Quellen" statt des Gates; Wartezeit bis zum Gate ~40 s | Wiedergabe wird gemerkt und nach dem Verbinden fortgesetzt; Detailseite fordert zuerst das VPN an; Wartezeit auf 15 s gekürzt | Code; im Simulator nur Teilpfad (VPN verband automatisch) |
| F12 | Eigener Proxy: nach fehlgeschlagener Verbindung zeigte der Button weiter „VPN Trennen" | Button zeigt „Trennen" nur bei bestehender/laufender Verbindung; ein Tipp nach Fehlschlag versucht es erneut | Code |
| F3 | Tastatur in Bibliothek → Addons ließ sich nur mit Return schließen | Tastatur schließt beim Scrollen (`scrollDismissesKeyboard`) | Code |
| F5 | Einstellungen: Titel schwebte ohne Hintergrund über dem Inhalt | Navigationsleiste mit Material-Hintergrund | Code |
| F7 / F18 | Player-Steuerung blendete nach 4 s aus, Zurück-Button wurde oft verfehlt | Ausblendzeit 6 s | Code |
| F8 | Dieselbe Stream-URL erschien mehrfach in der Quellenliste | Doppelte URLs werden zusammengefasst | Code |
| F9 | Onboarding nannte ein „15-Minuten-Limit", das nicht zum Backend passt | Text neutral: „ohne Zeitlimit" (DE/EN) | Code |
| F10 | Sprache „English" zeigte eine UK-Flagge, die Region steht aber auf „US" | Flagge 🇺🇸 | Code |
| F16 | Tonspur hieß „Unknown" | Unbenannte Tonspuren heißen „Tonspur 1, 2 …" (lokalisiert) | Code |
| F19 | „Abmelden" meldete ohne Rückfrage ab | Bestätigungsdialog „Wirklich abmelden?" | Code |

„Code" = Änderung im Quelltext, gebaut und von den Unit-Tests nicht widerlegt, aber nicht gezielt im Simulator nachgestellt.

## Nicht behoben / bekannt

- **F4** Fehler-Toast im Addon-Dialog liegt über der Tastatur – durch F3 (Tastatur schließt beim Scrollen) entschärft, Position nicht geändert.
- **F6** Erster Tipp auf „Add" geht ins Leere, wenn sich das Layout beim Einblenden der Tastatur verschiebt.
- **F11** Kosmetik: Seitenpunkte im Onboarding (heller Modus) schwach sichtbar, leicht unterschiedliche Überschrift-Einrückung auf Discover, Live-TV ohne EPG-Daten/Logos, doppelte Addon-Installation (Bibliothek und Einstellungen), „Angesagte" und „Beliebte Serien" zeigen dieselben Titel (Addon-Daten).
- **F15** (System-Passcode-Dialog der App-Sperre) hat sich durch das Entfernen der App-Sperre erledigt.
- **F17** „Fit"-Taste im Player: Wirkung im Test nicht erkennbar (nicht abschließend geklärt).
- Doppel-Tipp-Geste (±10 s) kann zwei schnelle Taps auf Steuerelemente schlucken.
- Live-TV-Streams der getesteten Quelle waren tot oder blockiert; die App zeigt das jetzt als Fehler an, die Quelle liegt außerhalb der App.

## Nicht getestet

Abmelden/Anmelden/Connect-Code-Ablauf, PiP/AirPlay, Onboarding im Querformat.

## Änderungen im Detail

`OmniboxView.swift`, `DashboardView.swift`, `PlayerService.swift`, `AppState.swift`, `M3UParser.swift`,
`LiveTVGuideView.swift`, `VPNManager.swift`, `VPNSettingsSheetView.swift`, `VPNGateView.swift`,
`MediaDetailView.swift`, `SourcePickerSheetView.swift`, `AccountView.swift`, `SettingsView.swift`,
`MainNavigationView.swift`, `CustomPlayerView.swift`, `OnboardingView.swift`, `StorageModels.swift`,
`Localization.swift`; Version in `Info.plist` und `scripts/generate_xcodeproj.py`.

Datenschutz: Dieses Release enthält keine Test- oder Nutzerdaten; die IPA wird ausschließlich aus dem Quellcode gebaut.
