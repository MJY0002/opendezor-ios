# OpenDezor – ready-to-post English texts (local only)

Check each subreddit's rules/flair first. Don't post all on the same day. Add 2–3 screenshots (Discover tab, player, VPN screen).
Two lines are yours to confirm before posting: **[TAKEDOWN]** (add a link/date to the source) and **[WHY]** (your own motive, edit freely).

---

## 1) r/sideloaded · r/SideStore · r/AltStore

**Title:** OpenDezor 1.1 – open-source iOS client in the Dezor style (IPA for AltStore/Sideloadly/TrollStore)

**Body:**
The original Dezor app was taken down from the App Store **[TAKEDOWN: add link/date]**. **[WHY: e.g. "I wanted a transparent alternative that anyone can read, build and fix."]** So I built **OpenDezor**.

- Unofficial, independent iOS client (iOS 17+, SwiftUI, zero dependencies, MIT)
- Ships **no content and no add-ons** – you add sources by link, and what you use is your call (please respect copyright)
- Movies & series with resume, Live TV with M3U import, built-in browser, favourites/history stored locally, PiP/AirPlay, subtitles, English + German
- **VPN-first:** playback only runs through the VPN. Shadowsocks is implemented in-app (no NetworkExtension, so it sideloads fine)

**1.1** comes from a full manual test run: 20 findings documented with status in the release notes; the main ones are fixed (search layout, dead Live-TV streams, M3U import, VPN flow), and the startup passcode is gone.

IPA: https://github.com/MJY0002/opendezor-ios/releases/tag/v1.1.0

---

## 2) r/iOSProgramming (Show-off Saturday) · r/swift · r/SwiftUI

**Title:** I built an open-source iOS streaming client with an in-process Shadowsocks VPN (SwiftUI, no NetworkExtension)

**Body:**
Hobby project, MIT, iOS 17+, no third-party dependencies.

The part I enjoyed most: **AEAD Shadowsocks on CryptoKit + Network.framework** (EVP_BytesToKey, HKDF-SHA1, AES-GCM/ChaChaPoly) behind a local SOCKS5 listener. AVPlayer ignores app proxy settings, so playback goes through a loopback stream proxy that re-issues requests via URLSession and rewrites HLS playlists – no packet-tunnel entitlement needed, so ad-hoc sideloading works. Known-answer tests pin the nonce handling (it breaks silently otherwise).

1.1 is a bug-fix release from a complete manual QA pass – every finding is listed with status (fixed / code-only / open), including the ones I didn't fix. Feedback on the architecture welcome.

Repo: https://github.com/MJY0002/opendezor-ios

---

## 3) Hacker News

**Title:** Show HN: OpenDezor – open-source iOS client with an in-process Shadowsocks VPN
**URL:** https://github.com/MJY0002/opendezor-ios
First comment: same text as (2), plus one honest line on what it deliberately does not do (ships no content, no add-ons).

---

## Reply templates
- "Is this legal?" → "The app itself is a neutral client: it ships no content and no add-ons. What sources you add, and whether you may use them, is up to you – please follow your local copyright law."
- "Why not App Store?" → "It uses arbitrary-load ATS settings for add-on hosts, which App Store review wouldn't accept, so it's sideload-only by design."
- "Bug reports" → "Please open an issue with iOS version + steps; thanks!"
