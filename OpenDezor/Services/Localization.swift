import Foundation
import Combine

/// Interface translation.
///
/// The German string is the lookup key, so `L("Einstellungen")` returns "Settings" in
/// English and falls back to its own argument when a translation is missing. That keeps
/// every call site readable and makes a missing entry degrade to correct German rather
/// than to a raw key like `settings.title`.
public final class LocalizationController: ObservableObject {
    public static let shared = LocalizationController()

    /// Interface language code, `de` or `en`.
    @Published public var code: String = "de"

    public init() {}

    public func apply(_ language: AppLanguage) {
        let resolved = language.interfaceCode
        if code != resolved { code = resolved }
    }

    public func string(_ german: String) -> String {
        guard code != "de" else { return german }
        return Self.english[german] ?? german
    }

    /// German -> English. Anything absent stays German.
    static let english: [String: String] = [
        // Navigation & tabs
        "Entdecken": "Discover",
        "Kataloge": "Catalogs",
        "Live TV": "Live TV",
        "Bibliothek": "Library",
        "Einstellungen": "Settings",

        // Generic actions
        "Schließen": "Close",
        "Abbrechen": "Cancel",
        "Weiter": "Next",
        "Zurück": "Back",
        "Überspringen": "Skip",
        "Fertig": "Done",
        "Speichern": "Save",
        "Löschen": "Delete",
        "Entfernen": "Remove",
        "Installieren": "Install",
        "Öffnen": "Open",
        "Suchen": "Search",
        "Kopieren": "Copy",
        "Alle anzeigen": "See all",
        "Mehr anzeigen": "Show more",
        "Weniger anzeigen": "Show less",
        "Jetzt starten": "Get started",
        "Jetzt Abspielen": "Play now",
        "Details": "Details",
        "Quellen": "Sources",
        "Aus": "Off",

        // Dashboard & catalog
        "Willkommen bei OpenDezor": "Welcome to OpenDezor",
        "Installiere ein MediaHub-Addon über die Adressleiste oben oder durchsuche Kataloge.":
            "Install a MediaHub addon from the address bar above, or browse catalogs.",
        "Weiterschauen": "Continue watching",
        "Meine Liste": "My list",
        "URL eingeben (z.B. mhub://...) oder suchen": "Enter a URL (e.g. mhub://…) or search",
        "MediaHub Addon gefunden": "MediaHub addon found",
        "Handlung": "Storyline",
        "Besetzung": "Cast",
        "Episoden": "Episodes",
        "Staffel": "Season",
        "Episode": "Episode",
        "Folge": "Ep.",
        "Verfügbare Streams": "Available streams",
        "Keine Quellen gefunden": "No sources found",
        "Für diesen Titel konnten keine aktiven Stream-Server gefunden werden.":
            "No active stream servers could be found for this title.",
        "Unbekannter Titel": "Untitled",
        "Lade Live-TV Sender...": "Loading live TV channels…",
        "Sender suchen...": "Search channels…",
        "Keine Live-Sender verfügbar": "No live channels available",
        "Wiedergabefehler": "Playback error",

        // Onboarding
        "Willkommen bei": "Welcome to",
        "Dein nativer MediaHub & Streaming Client für iOS": "Your native MediaHub and streaming client for iOS",
        "Nativer AVPlayer": "Native AVPlayer",
        "Hardware-beschleunigtes HLS/MP4 Streaming mit PiP & AirPlay":
            "Hardware-accelerated HLS/MP4 streaming with PiP and AirPlay",
        "MediaHub-Addons": "MediaHub addons",
        "Universelle Integration aller MediaHub / Dezor Quellen":
            "Universal integration of every MediaHub / Dezor source",
        "VPN & Proxy": "VPN & proxy",
        "Unbegrenzter Stream-Zugang mit Dezor Account": "Unlimited streaming with a Dezor account",
        "Sprache": "Language",
        "Wähle deine Sprache": "Choose your language",
        "Gilt für die Oberfläche und für Titel, Beschreibungen und Streams der Addons.":
            "Applies to the interface as well as to addon titles, descriptions and streams.",
        "Aussehen": "Appearance",
        "Wähle dein Aussehen": "Choose your appearance",
        "Farbschema und Akzentfarbe lassen sich jederzeit in den Einstellungen ändern.":
            "Colour scheme and accent can be changed any time in Settings.",
        "Farbschema": "Colour scheme",
        "Akzentfarbe": "Accent colour",
        "Hell": "Light",
        "Dunkel": "Dark",
        "Vorschau": "Preview",
        "Dezor VPN & Premium": "Dezor VPN & Premium",
        "Hast du einen bezahlten Dezor Account? Du kannst ihn jetzt verknüpfen, um ohne 15-Minuten-Limit unbegrenzt zu streamen.":
            "Got a paid Dezor account? Link it now to stream without the 15-minute limit.",
        "Du kannst die Anmeldung auch jederzeit später in den Einstellungen durchführen.":
            "You can also sign in later from Settings.",
        "Connect-Code auf dezor.net:": "Connect code on dezor.net:",
        "Mit E-Mail & Passwort anmelden": "Sign in with email and password",
        "Mit E-Mail anmelden": "Sign in with email",
        "Verbunden als": "Connected as",
        "Unbegrenzter VPN-Zugang ist aktiv.": "Unlimited VPN access is active.",

        // Account
        "Dezor Account": "Dezor account",
        "Dezor Account & VPN": "Dezor account & VPN",
        "Gerät verknüpfen": "Link device",
        "1. Öffne auf deinem Computer oder im Browser:": "1. On your computer or browser, open:",
        "2. Gib den folgenden Code ein:": "2. Enter this code:",
        "Warte auf Bestätigung auf dezor.net...": "Waiting for confirmation on dezor.net…",
        "Token oder Voucher manuell eingeben": "Enter a token or voucher manually",
        "Token speichern & Freischalten": "Save token and unlock",
        "Token verifiziert und aktiviert!": "Token verified and activated.",
        "Abmelden": "Sign out",
        "Account": "Account",
        "VPN Bandbreite": "VPN bandwidth",
        "Unbegrenzt (Keine Drosselung)": "Unlimited (no throttling)",
        "Gültig bis": "Valid until",
        "Token-Status": "Token status",
        "Aktiv & Authentifiziert": "Active and authenticated",
        "Dezor Premium": "Dezor Premium",
        "Unbegrenzter VPN- & Stream-Zugang": "Unlimited VPN and streaming access",
        "Anmelden für unbegrenzten VPN-Zugang": "Sign in for unlimited VPN access",
        "Unbegrenzter VPN & Stream-Zugang aktiv": "Unlimited VPN and streaming active",
        "Passwort vergessen?": "Forgot your password?",
        "E-Mail": "Email",
        "Passwort": "Password",
        "Anmelden": "Sign in",
        "Kein Premium": "No premium",
        "Unbegrenzt aktiv": "Active, unlimited",
        "Aktives Abo": "Active subscription",
        "Nicht angemeldet": "Not signed in",

        // Settings
        "Addons verwalten": "Manage addons",
        "Keine Addons installiert": "No addons installed",
        "Verlauf löschen": "Clear history",
        "Suchverlauf löschen": "Clear search history",
        "Onboarding erneut anzeigen": "Show onboarding again",
        "Über die App": "About",
        "Version": "Version",
        "Daten": "Data",
        "Darstellung": "Appearance",

        // Errors and service-layer messages.
        //
        // Messages that embed a value keep only their static half as the key, and the code
        // appends the value: `"\(L("Ungültige URL")): \(url)"`. That keeps one entry per
        // message instead of a format string per call site.
        "Ungültige URL": "Invalid URL",
        "Addon konnte nicht erkannt werden": "Addon could not be detected",
        "HTTP-Fehler": "HTTP error",
        "Fehler beim Parsen der Server-Antwort": "Failed to parse the server response",
        "Keine Videoquellen für diesen Titel gefunden.": "No video sources found for this title.",
        "Stream-URL konnte nicht aufgelöst werden": "Could not resolve the stream URL",
        "Netzwerkfehler": "Network error",
        "Code kopiert!": "Code copied.",
        "Keine gültige HTTP-Antwort": "No valid HTTP response",
        "Fehler beim Dekodieren des Manifests": "Failed to decode the manifest",
        "Fehler beim Serialisieren des Payloads": "Failed to serialize the payload",
        "Fehler beim Dekodieren von": "Failed to decode",
        "Ungültige aufgelöste Stream-URL": "Invalid resolved stream URL",
        "Kein aktives Addon zum Laden von Quellen gefunden.":
            "No active addon available to load sources from.",
        "Kein gültiges Addon unter": "No valid addon at",
        "gefunden.": "found.",
        "Unter": "At",
        "wurde kein MediaHub/MediaURL-Addon gefunden.": "no MediaHub/MediaURL addon was found.",
        "Stream konnte nicht geladen werden": "The stream could not be loaded",
        "Stream wird vorbereitet…": "Preparing stream…",
        "Alle": "All",
        "Wiedergabe läuft nur über das VPN. Bitte verbinde das VPN.": "Playback only runs through the VPN. Please connect the VPN.",
        "Filme, Serien und Live-TV laufen in OpenDezor ausschließlich über das VPN. Deine echte IP-Adresse bleibt für Hoster verborgen.": "In OpenDezor, films, series and Live TV play exclusively through the VPN. Your real IP address stays hidden from hosters.",
        "Filme, Serien und Live-TV laufen nur über das VPN – auch der Videostream selbst. Gilt nur für diese App, nicht systemweit.": "Films, series and Live TV only play through the VPN – including the video stream itself. Applies to this app only, not system-wide.",
        "Das VPN schützt den Datenverkehr dieser App: den Browser und alle Filme, Serien und Live-TV-Sender – auch den Videostream selbst. Es ist kein systemweites VPN; andere Apps laufen über deine normale Verbindung.": "The VPN protects this app's traffic: the browser and all films, series and Live TV channels – including the video stream itself. It is not a system-wide VPN; other apps use your normal connection.",
        "Du bist geschützt": "You're protected",
        "Sicher streamen": "Stream safely",
        "Server": "Server",
        "VPN verbinden": "Connect VPN",
        "Beim Start automatisch verbinden": "Connect automatically at launch",
        "Dieser Bildschirm wird dann übersprungen.": "This screen is skipped then.",
        "Später – nur stöbern": "Later – just browse",
        "VPN verbunden": "VPN connected",
        "Das Addon hat zu viele Aufgaben gestellt": "The addon requested too many tasks",
        "Nicht unterstützte Addon-Aufgabe": "Unsupported addon task",
        "Addon-Aufgabe auf ein privates Netzwerk abgelehnt": "Addon task to a private network refused",
        "Fehler beim Installieren des Addons": "Failed to install the addon",
        "erfolgreich installiert!": "installed successfully.",
        "Addon": "Addon",
        "Fehler beim Abspielen des Streams": "Playback of the stream failed",
        "Standard Stream": "Default stream",
        "Bitte gib eine gültige E-Mail-Adresse ein.": "Please enter a valid email address.",
        "Bitte gib dein Passwort ein.": "Please enter your password.",
        "Bitte gib einen Token ein.": "Please enter a token.",
        "Anmeldung fehlgeschlagen. Bitte prüfe E-Mail und Passwort.":
            "Sign-in failed. Please check your email and password.",
        "Du bist bereits angemeldet.": "You are already signed in.",

        // Empty states, settings and remaining view strings
        "Keine Einträge gefunden": "No entries found",
        "Keine Einträge in diesem Katalog gefunden.": "No entries found in this catalog.",
        "Filter zurücksetzen": "Reset filters",
        "Zurücksetzen": "Reset",
        "Keine Beschreibung für diesen Titel verfügbar.": "No description available for this title.",
        "Installiere ein IPTV-fähiges MediaHub-Addon in den Einstellungen, um Live-TV zu empfangen.":
            "Install an IPTV-capable MediaHub addon in Settings to receive live TV.",
        "Verlauf": "History",
        "Einträge": "entries",
        "Keine Favoriten gespeichert": "No favourites saved",
        "Füge Filme und Serien über die Detailansicht zu deinen Favoriten hinzu.":
            "Add movies and shows to your favourites from the detail view.",
        "Kein Wiedergabeverlauf": "No playback history",
        "Füge eine MediaHub-Quelle hinzu, um Filme, Serien und Live-TV freizuschalten.":
            "Add a MediaHub source to unlock movies, shows and live TV.",
        "Standard MediaHub-Katalog für Filme, Serien & Live-TV":
            "Default MediaHub catalog for movies, shows and live TV",
        "Hinzufügen": "Add",
        "Keine alternativen Tonspuren verfügbar": "No alternative audio tracks available",
        "Ungültige E-Mail-Adresse.": "Invalid email address.",
        "Neues Addon hinzufügen": "Add a new addon",
        "Addon-Installation": "Addon installation",
        "Noch keine Addons installiert.": "No addons installed yet.",
        "Wische nach links, um ein Addon zu deinstallieren.": "Swipe left to remove an addon.",
        "Installierte Addons": "Installed addons",
        "Verlauf leeren": "Clear history",
        "Verlauf leeren?": "Clear history?",
        "Verlauf wurde geleert.": "History cleared.",
        "Möchtest du den gesamten Wiedergabeverlauf wirklich löschen?":
            "Do you really want to delete the entire playback history?",
        "Einführung & Onboarding anzeigen": "Show the introduction again",
        "Über OpenDezor": "About OpenDezor",
        "Die Anmeldung erfolgt direkt bei Dezor (dezor.net). OpenDezor ist ein inoffizieller Client und speichert dein Passwort nicht; es gelten Dezors Nutzungsbedingungen und Datenschutzhinweise.": "You sign in directly with Dezor (dezor.net). OpenDezor is an unofficial client and does not store your password; Dezor's terms of use and privacy policy apply.",
        "OpenDezor ist ein inoffizielles, unabhängiges Hobbyprojekt und steht in keiner Verbindung zu Dezor. „Dezor“ ist eine Marke ihres Inhabers. Konto, VPN-Server und Dienste gehören Dezor und unterliegen dessen Nutzungsbedingungen. Die App liefert keine Inhalte und keine Addons; für hinzugefügte Quellen und deren Nutzung ist allein der Nutzer verantwortlich.": "OpenDezor is an unofficial, independent hobby project and is not affiliated with Dezor. “Dezor” is a trademark of its owner. The account, VPN servers and services belong to Dezor and are subject to its terms of use. The app ships no content and no addons; users alone are responsible for any sources they add and how they use them.",
        "Std.": "h",
        "Min.": "min",
        "Min": "min",

        // Section headers, badges and the remaining view strings
        "Dezor Mitgliedschaft": "Dezor membership",
        "Daten & Speicher": "Data & storage",
        "Addon-URL (z.B. https://.../mediahubmx.json)": "Addon URL (e.g. https://…/mediahubmx.json)",
        "Addon einrichten": "Set up an addon",
        "Addon entfernt.": "Addon removed.",
        "Addon erfolgreich installiert!": "Addon installed successfully.",
        "installiert!": "installed.",
        "Audio & Untertitel": "Audio & subtitles",
        "Tonspuren": "Audio tracks",
        "Untertitel": "Subtitles",
        "E-Mail-Adresse": "Email address",
        "Erfolgreich angemeldet!": "Signed in successfully.",
        "Abgemeldet.": "Signed out.",
        "Falls du dein Passwort vergessen hast, besuche bitte:":
            "If you have forgotten your password, please visit:",
        "Gib deinen Dezor Authentifizierungs-Token ein:": "Enter your Dezor authentication token:",
        "Filter & Sortierung": "Filters & sorting",
        "Sortierung": "Sorting",
        "Favoriten": "Favourites",
        "Meine Liste / Favoriten": "My list / favourites",
        "Letzte Suchen": "Recent searches",
        "Suchergebnisse": "Search results",
        "Suche nach Videoquellen...": "Searching for video sources…",
        "Live TV & EPG": "Live TV & EPG",
        "Oder eigene URL eingeben:": "Or enter your own URL:",
        "Leeren": "Clear",
        "Fehler": "Error",
        "AKTIV": "ACTIVE",
        "PREMIUM": "PREMIUM",
        "EMPFOHLEN": "RECOMMENDED",
        "LIVE": "LIVE",
        "LIVE TV": "LIVE TV",
        "SERIE": "SERIES",
        "FILM": "MOVIE",
        "SENDER": "CHANNEL",
        "KATALOG": "CATALOG",
        "In": "In",
        "suchen...": "search…",
        "Live Programm": "live programme",
        "Nachrichten & Aktuelles": "News & current affairs",

        // VoiceOver labels
        "Abspielen": "Play",
        "Pause": "Pause",
        "10 Sekunden zurück": "Back 10 seconds",
        "10 Sekunden vor": "Forward 10 seconds",
        "Bild-in-Bild": "Picture in picture",
        "Untertitel und Tonspuren": "Subtitles and audio tracks",
        "Bildausschnitt anpassen": "Change video fit",
        "Wiedergabegeschwindigkeit": "Playback speed",
        "Schließen und zurück": "Close and go back",
        "Fortschritt": "Progress",
        "Serie": "Series",
        "Film": "Movie",
        "Sender": "Channel",
        "Zu Favoriten hinzufügen": "Add to favourites",
        "Aus Favoriten entfernen": "Remove from favourites",
        "Adresse eingeben": "Enter address",
        "Seite neu laden": "Reload page",
        "Eine Seite zurück": "Back one page",
        "Eine Seite vor": "Forward one page",
        "Im Browser öffnen": "Open in browser",
        "Browser": "Browser",
        "Bilder über Dezor-Cache laden": "Load images via Dezor cache",
        "Kleinere Bilder, schnellerer Aufbau. Bild-Adressen werden dabei an dezor.net gesendet.":
            "Smaller images, faster loading. Image URLs are sent to dezor.net.",
        "Nächste Episode automatisch abspielen": "Auto-play next episode",
        "Bevorzugte Tonspur": "Preferred audio track",
        "Bevorzugte Untertitel": "Preferred subtitles",
        "Bevorzugte Qualität": "Preferred quality",
        "Bildspeicher": "Image cache",
        "Wiedergabe": "Playback",

        // VPN & proxy
        "VPN & Proxy Schutz": "VPN & proxy protection",
        "VPN & Anonymität": "VPN & anonymity",
        "In-App VPN & Proxy Schutz": "In-app VPN & proxy protection",
        "VPN Schutz ist AKTIV": "VPN protection is ON",
        "VPN ist GETRENNT": "VPN is DISCONNECTED",
        "VPN nicht verbunden": "VPN not connected",
        "VPN Verbinden": "Connect VPN",
        "VPN Trennen": "Disconnect VPN",
        "VPN ist aktiv": "VPN is active",
        "VPN ist getrennt": "VPN is disconnected",
        "VPN getrennt": "VPN disconnected",
        "VPN auf dieser Plattform nicht verfügbar": "VPN is not available on this platform",
        "Verbinde…": "Connecting…",
        "Verbunden": "Connected",
        "Verbindung fehlgeschlagen": "Connection failed",
        "Maskierte IP": "Masked IP",
        "Deine echte IP-Adresse ist für Webseiten sichtbar": "Websites can see your real IP address",
        "Server-Standorte": "Server locations",
        "Wähle einen Server-Standort": "Choose a server location",
        "Automatisch": "Automatic",
        "Eigener Proxy": "Custom proxy",
        "Eigener Host": "Custom host",
        "Eigenen Proxy konfigurieren": "Configure a custom proxy",
        "Proxy speichern & aktivieren": "Save proxy & connect",
        "Server Host / IP": "Server host / IP",
        "Port": "Port",
        "Protokoll": "Protocol",
        "Kein Proxy-Host angegeben": "No proxy host set",
        "Kein Server ausgewählt": "No server selected",
        "Keine VPN-Konfiguration vom Server erhalten": "The server sent no VPN configuration",
        "Proxy-Server nicht erreichbar": "Proxy server unreachable",
        "Proxy-Antwort nicht lesbar": "Could not read the proxy response",
        "Verschlüsselung nicht unterstützt": "Unsupported encryption",
        "Freies VPN-Kontingent aufgebraucht": "Free VPN allowance used up",

        // Browser
        "Seite konnte nicht geladen werden": "The page could not be loaded",
        "Erneut versuchen": "Try again",
        "Laden abbrechen": "Stop loading",
        "Seite teilen": "Share page",
        "Text löschen": "Clear text",

        // Addons
        "Addon hinzufügen": "Add addon",
        "Addon-Katalog": "Addons",
        "Addon-URL eingeben:": "Enter addon URL:",
        "Addons werden nicht mitgeliefert": "No addons are bundled",
        "Fehler beim Installieren": "Installation failed",
        "Trage die Adresse einer MediaHub-Quelle ein, die du selbst gefunden hast. Im Browser-Tab erkennt die App passende Quellen automatisch und bietet sie zur Installation an.":
            "Enter the address of a MediaHub source you found yourself. In the browser tab the app detects compatible sources automatically and offers to install them.",
        "Trage die Adresse einer MediaHub-Quelle ein. Im Browser-Tab erkennt die App passende Quellen automatisch, während du surfst.":
            "Enter the address of a MediaHub source. In the browser tab the app detects compatible sources automatically while you browse.",

        // App lock
        "OpenDezor ist gesperrt": "OpenDezor is locked",
        "App-Sperre (Face ID / Touch ID)": "App lock (Face ID / Touch ID)",
        "Mit Face ID entsperren": "Unlock with Face ID",
        "Ohne Face ID entsperren (nur Simulator)": "Unlock without Face ID (simulator only)",
        "Sperre ausschalten & deaktivieren": "Turn the lock off",
        "Entsperre OpenDezor mit Face ID oder Touch ID": "Unlock OpenDezor with Face ID or Touch ID",
        "Verwende Face ID, Touch ID oder deinen Geräte-Code, um fortzufahren.":
            "Use Face ID, Touch ID or your device passcode to continue.",
        "Sperrt OpenDezor beim Verlassen der App und erfordert biometrische Authentifizierung.":
            "Locks OpenDezor when you leave the app and requires biometric authentication.",
        "Sicherheit & Privatsphäre": "Security & privacy",

        // Account
        "Angemeldet": "Signed in",
        "Aktiv": "On",
        "Verbleibende Wiedergabezeit": "Remaining playback time",

        // Live TV & M3U
        "IPTV Sender": "IPTV channels",
        "M3U Wiedergabeliste": "M3U playlist",
        "M3U Playlist importieren": "Import M3U playlist",
        "Wiedergabeliste importieren": "Import playlist",
        "M3U / M3U8 Wiedergabeliste URL": "M3U / M3U8 playlist URL",
        "M3U Inhalt einfügen": "Paste M3U content",
        "M3U Text": "M3U text",
        "URL-Link": "URL link",
        "M3U Playlist konnte nicht geladen werden": "The M3U playlist could not be loaded",
        "Sender erfolgreich importiert!": "channels imported successfully!",
        "Sender entfernen": "Remove channel",
        "Alle importierten Sender löschen": "Delete all imported channels",
        "Alle benutzerdefinierten Sender wurden entfernt.": "All custom channels were removed.",
        "Installiere ein IPTV-fähiges MediaHub-Addon in den Einstellungen oder importiere eine eigene M3U-Wiedergabeliste.":
            "Install an IPTV-capable MediaHub addon in the settings, or import your own M3U playlist.",

        "im Browser suchen": "search in the browser",

        // Credits
        "Gebaut mit": "Built with",
        "von": "by",
        "Liebe": "love",

        // Player
        "Nächste Folge": "Next episode",
        "Intro überspringen (+85s)": "Skip intro (+85s)",
        "In externem Player öffnen": "Open in external player",
        "Untertitel-Synchronisation": "Subtitle sync",
        "Zeitversatz (Sync)": "Offset (sync)",
        "Timer aus": "Timer off",
        "Quelle": "Source",
        "Reset": "Reset",
    ]
}

/// Shorthand used across the views.
public func L(_ german: String) -> String {
    LocalizationController.shared.string(german)
}
