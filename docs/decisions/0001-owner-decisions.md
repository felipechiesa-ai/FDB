# 0001: Owner decisions and 01-01 scaffold

- Status: accepted
- Date: 2026-10-15
- Source: owner answers in the working session on 2026-10-15

## Decisions

| Topic | Decision | Notes |
| --- | --- | --- |
| Minimum macOS | macOS 26 | Supersedes the proposed default of macOS 14 in AGENTS.md §3. |
| Architectures | Apple silicon (arm64) only | Only arm64 is claimed and verified. |
| Stage 1 demo | No user-facing demo library | Synthetic data lives in tests and behind a developer launch argument. |
| Citizenship and birthplace | ISO 3166-1 sovereign countries only in Stage 1 | Football associations, such as England or Scotland, get a separate model later. |
| Bundle identifier | `com.pipachiesa.FDB` | Derived from the owner's answer "pipachiesa". Changeable until a library exists. |
| Copyright holder | pipachiesa | MIT License, 2026. |
| Git | Repository initialized; initial commit made on 2026-10-15 | Commit or push only when the owner asks. |
| GitHub remote | Public, chosen by the owner on 2026-10-15 | Repository `felipechiesa-ai/FDB`. |
| Manual acceptance checks | Owner runs VoiceOver, keyboard, appearance, and small-window checks | Results go in `docs/verification/`. |
| Reference material | No scrape files or schema dump exist | The reference inventory covers AGENTS.md §2 only. |
| Apple Developer Program | No membership | Stage 5 signing and notarization stay open. |
| Transfermarkt terms | Not reviewed by the owner | No Transfermarkt content is copied. The inventory cites three pages and describes their fields. Review the terms before relying on it publicly. |

## Defaults adopted

These stand unless the owner objects.

- **Team category:** senior, reserve, youth, or other. Age group is a separate optional field. Gender category (men's, women's, mixed, unspecified) is separate.
- **Positions:** GK, CB, LB, RB, DM, CM, AM, LW, RW, CF, and unspecified. One primary position per player.
- **Preferred foot:** right, left, both, or unknown.
- **Birthplace:** city text plus an optional birth-country reference.
- **Dates and ages:** year- or month-only dates keep their precision and never become January 1. Memberships with imprecise boundaries show as uncertain in as-of results. A start equal to its end is rejected. Age is computed from the current date.
- **Images:** JPEG or PNG only, up to 25 MB and 6000 px per side. Orientation is applied, and metadata, including GPS, is removed on import. Test images are generated originals.
- **Backups:** a folder package with a manifest, a SQLite snapshot, and originals. No compression in Stage 1.
- **Security:** App Sandbox and Hardened Runtime on. File access only through open and save panels.
- **Test data:** fictional people and clubs, with names that do not match real ones.
- **Language:** English UI in a String Catalog. Dates and numbers use locale formatters.
- **Measurements:** performance numbers are recorded on the reference Mac and labeled with its hardware and OS.
- **Cadence:** stop at each substage boundary with a handoff, per AGENTS.md §8, item 10.

## Notes

The owner's single-word answer "pipachiesa" was read as both the bundle identifier namespace and the copyright holder. If the owner wants a different identifier or a full legal name, change it before the first library is created.
