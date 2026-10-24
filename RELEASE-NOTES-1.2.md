# OpenDezor 1.2.0 (Build 11)

Funktions-Release: DEV-Panel für Fehlerberichte, eigene Suchseite, Doppeltippen im Player und
Querformat-Korrekturen. Geprüft im iOS-Simulator (iPhone 17 Pro, iOS 26.5, Hoch- und Querformat);
alle 137 Unit-Tests laufen durch.

Hinweis: Die IPA ist ad-hoc signiert (Sideloading über AltStore / Sideloadly / TrollStore), wie 1.1.0.

## Neu

- **DEV-Panel** (Einstellungen → Entwickler), für jeden zugänglich:
  - Logging per Schalter; das Log liegt nur im Speicher, bleibt im Hintergrund erhalten und ist nach vollständigem Beenden der App weg. Beim nächsten Start ist Logging wieder aus.
  - Live-Log mit Stufenfilter (Alle / Warnungen / Fehler), Suche, Auto-Scroll, Marker setzen, Leeren.
  - Bericht als lesbare .txt-Datei exportieren oder in die Zwischenablage kopieren.
  - Diagnose: iPhone-Modell, iOS- und App-Version, RAM, freier Speicher, Akku, Temperatur-Status, Verbindungsart (WLAN/Mobilfunk), Geschwindigkeitstest (Mbit/s, Latenz), Live-Werte des laufenden Streams (Bitrate, Puffer, Aussetzer), Addon-Check (Host, HTTP-Status, Antwortzeit).
  - Datenschutz: Das Log enthält nur, was die App und das Gerät tun. Konto-Daten, Titel, IP-Adressen, Netzwerknamen, Tokens, URL-Pfade und Dateipfade werden entfernt (Unit-Tests).
- **Suchseite** mit Typ-Filter vor und nach der Suche: Alle / Filme / Serien / Live TV / Sonstiges. Ergebnisse werden einmal geladen und lokal gefiltert.
- **Doppeltippen im Player**: rechte Hälfte +10 s, linke Hälfte −10 s, kurze Animation mit Haptik; funktioniert im Hochformat und in beiden Querformat-Richtungen.
- **Apple-Design-Feinschliff**: Federanimationen und Haptik an Schaltern und Gesten.
- Englische Übersetzungen für alle neuen Texte.

## Entfernt

- Der **+85-s-Button** im Player (ersetzt durch Doppeltippen).

## Behoben

- Beim erneuten Öffnen eines bereits gesehenen Streams stand „No streams found": Quellensuche wiederholt sich jetzt bei Fehlschlag und Quellen werden 30 Minuten zwischengespeichert. Im Test trat der ursprüngliche Fehler nicht auf; die Wirkung gegen den echten Fall ist daher nicht bestätigt.
- Hero-Banner auf der Startseite im Querformat: Karussell lag halb außerhalb des Bildschirms; jetzt blätterndes Karussell mit kompakter Querformat-Ansicht.
- VPN-Gate im Querformat: zweispaltiges Layout statt abgeschnittener Inhalte.
- Compiler-Warnungen beseitigt.

## Bekannt

- Im Simulator zeigt „Akku" n/a; echte Werte erscheinen nur auf einem iPhone, das ist dort nicht getestet.
- Das Teilen-Sheet des Berichts wurde im Simulator nicht sichtbar bestätigt; die Datei wird erzeugt und übergeben.
- Offene Punkte aus 1.1.0 (F4, F6, F11, F17) bleiben unverändert.
