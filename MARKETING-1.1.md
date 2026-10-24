# OpenDezor – Werbeplan (Entwurf, nur lokal, nicht im Repo)

Stand: 22.10.2026. Nichts davon ist veröffentlicht – Posten liegt bei dir.

## Wichtig vorab

- **Takedown der alten Dezor-App und dein Beweggrund:** Beides habe ich online **nicht bestätigen** können (Suche ergab nur Berichte, dass Dezor früher in den Charts stand; keine Meldung zur Entfernung). Die Texte unten nutzen deshalb Platzhalter `[…]` – setz dort deine eigenen, belegbaren Worte ein (am besten mit Link/Datum zur Quelle des Takedowns).
- **Rechtliches Umfeld:** Medien berichten, dass Dezor-Nutzung oft mit urheberrechtlich geschützten Inhalten verbunden wird. Werbe nur mit dem, was stimmt: *inoffizieller, quelloffener Client, bringt keine Inhalte und keine Addons mit, Quellen wählt der Nutzer, VPN-Pflicht*. Keine Versprechen wie „kostenlos Filme/Netflix". Das schützt dich vor Löschungen/Bans in den Foren und vor Ärger.
- **Regeln jeder Community vor dem Posten lesen** (Self-Promotion-Limits, Flairs, Account-Alter). Reddit war in meinem Browser-Zugriff gesperrt, ich konnte die Regeln nicht prüfen.

## Foren / Plattformen (nach Passung)

**Sehr passend (Sideloading & iOS-Nutzer)**
1. r/sideloaded – Sideloading-Community
2. r/SideStore – SideStore-Nutzer (IPA direkt aus Releases)
3. r/AltStore – AltStore-Nutzer
4. r/jailbreak bzw. r/TrollStore-Themen – nur wenn die Regeln Apps erlauben

**Entwickler / Open Source (Fokus: Code, SwiftUI, VPN-Eigenbau)**
5. r/iOSProgramming – „Show-off Saturday"-Thread
6. r/swift und r/SwiftUI – Technik-Thread (Shadowsocks in-process, kein NetworkExtension)
7. r/opensource – quelloffenes Hobbyprojekt
8. Hacker News – „Show HN: OpenDezor – open-source iOS client … (SwiftUI, in-process Shadowsocks)"
9. GitHub: Topics setzen (`ios`, `swiftui`, `sideloading`, `altstore`, `ipa`), Discussions aktivieren, Repo-Beschreibung

**Deutschsprachig**
10. r/de bzw. r/de_EDV – nur technisch/neutral, Regeln beachten
11. iphone-ticker.de-Forum, Apfeltalk, MacTechNews-Forum, ComputerBase-Forum (Bereich iOS/Apps)
12. Telegram-Gruppen zu Sideloading/AltStore (nur wo Self-Promo erlaubt ist)

**Sonstige**
13. Mastodon (#iOS #SwiftUI #opensource #sideloading), X/Bluesky mit Screenshots
14. Product Hunt (eher für ein späteres, polierteres Release)
15. dev.to / Medium: Technik-Artikel („Shadowsocks in SwiftUI ohne NetworkExtension")

## Werbetexte

### Kurzslogan
- DE: „OpenDezor – dein inoffizieller, quelloffener Dezor-Client fürs iPhone. Ohne Inhalte, mit VPN-Pflicht, ohne Tracking."
- EN: "OpenDezor – an unofficial, open-source Dezor client for iPhone. No built-in content, VPN-first, no tracking."

### Reddit-Post (DE, für r/sideloaded & Co.)
**Titel:** OpenDezor 1.1 – quelloffener iOS-Client im Dezor-Stil (Sideload, SwiftUI)

Hi zusammen,

[Die offizielle Dezor-App wurde aus dem App Store genommen – Quelle/Datum einfügen.] Ich wollte [DEIN BEWEGGRUND, z. B. „eine transparente, quelloffene Alternative, die man selbst prüfen und weiterentwickeln kann"] – deshalb habe ich **OpenDezor** gebaut.

**Was es ist:** ein inoffizieller, unabhängiger iOS-Client (iOS 17+, SwiftUI, keine Fremdabhängigkeiten) im MediaHub-Stil. Addons fügst du per Link hinzu – die App bringt **keine Inhalte und keine Addons mit** und empfiehlt keine.
**Was drin ist:** Filme/Serien mit Fortsetzen, Live-TV mit M3U-Import, eingebauter Browser, Favoriten & Verlauf (nur lokal), Bild-in-Bild/AirPlay, Untertitel, Deutsch/Englisch.
**VPN:** Wiedergabe läuft nur über das VPN – das Shadowsocks-Protokoll ist komplett in der App umgesetzt (kein NetworkExtension nötig, deshalb sideloadbar).
**1.1:** ein ganzer Testdurchlauf, 20 Fehler dokumentiert, die wichtigsten behoben (Suche, tote Live-TV-Streams, M3U-Import, VPN-Ablauf), App-Sperre entfernt. Liste aller Fehler mit Status im Release.

Download (IPA, AltStore/Sideloadly/TrollStore): https://github.com/MJY0002/opendezor-ios/releases/tag/v1.1.0
Quellcode (MIT): https://github.com/MJY0002/opendezor-ios

Hinweis: inoffiziell, keine Verbindung zu Dezor. Welche Quellen du nutzt und ob du das darfst, entscheidest du – bitte Urheberrecht beachten. Feedback und Bugs gern als Issue.

### Reddit/HN-Post (EN, für r/iOSProgramming, r/swift, Show HN)
**Title:** Show HN: OpenDezor – open-source iOS client with an in-process Shadowsocks VPN (SwiftUI, no NetworkExtension)

[The official Dezor app was pulled from the App Store – add source/date.] [Your motive, e.g. "I wanted something transparent that anyone can audit and extend."] So I built OpenDezor: SwiftUI, iOS 17+, zero dependencies, ad-hoc signed IPA for sideloading.

Interesting bits: AEAD Shadowsocks (EVP_BytesToKey, HKDF-SHA1, AES-GCM/ChaChaPoly) implemented on CryptoKit + Network.framework with a local SOCKS5 listener, so AVPlayer traffic is proxied through a loopback stream proxy without a packet tunnel entitlement. Known-answer tests pin the nonce handling. 1.1 comes out of a full manual test run (20 findings, documented with status in the release).

Repo: https://github.com/MJY0002/opendezor-ios — MIT. Unofficial; ships no content or add-ons.

### Kurzer Social-Post (DE)
🎬 OpenDezor 1.1 ist da – inoffizieller, quelloffener iOS-Client, SwiftUI, VPN-first, keine Inhalte an Bord. [Takedown-Satz einfügen.] 20 gefundene Fehler dokumentiert, die wichtigsten behoben. IPA + Code: github.com/MJY0002/opendezor-ios #iOS #SwiftUI #sideloading #opensource

## Tipps zur Wirkung
- 2–3 Screenshots/GIFs (Startseite, Player, VPN-Gate) in jeden Post; erstes Bild = Entdecken-Tab.
- Pro Community ein angepasster Text, nicht überall dasselbe kopieren; nicht am selben Tag überall posten.
- Auf Kommentare in den ersten 2 Stunden antworten; Bugs sofort als GitHub-Issues anlegen.
- README: Screenshots und „Warum OpenDezor?" (dein Beweggrund) ergänzen – das ist der Link, den alle öffnen.
- Ehrlichkeit als Stärke: die Fehlerliste mit Status ist ein Vertrauensargument.
