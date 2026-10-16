# Reference inventory

Source: AGENTS.md §2. The owner confirmed on 2026-10-15 that no scrape files or schema dump exist, so this inventory covers only the three public pages named in the charter. Nothing here is copied from those pages.

| Reference | Access date | Observed entity | Fields and relationships | Uncertainty | FDB destination | Status |
| --- | --- | --- | --- | --- | --- | --- |
| [Copa LPF Proyección competition](https://www.transfermarkt.us/copa-lpf-proyeccion-final/startseite/wettbewerb/CLPF) | 2026-10-15 | Competition edition | Season selector; participating reserve teams; squad sizes and ages; fixtures and results; two standings tables; scorer list; link to a later competition | The text fetch returned HTTP 403, so the page was observed in a browser only. Official rules are not inferred from a standings widget. | Stage 2: competition, edition, entry, phase, group. Stage 3: matches and standings. | Accepted as a feature requirement |
| [CA Boca Juniors II team page](https://www.transfermarkt.us/club-atletico-boca-juniors-ii/startseite/verein/14831/saison_id/2025) | 2026-10-15 | Club team, separate from the club organization | Season-selectable squad; portraits; positions; birth dates; multiple nationalities; stadium; internal team movements | The URL uses `saison_id/2025`, but the visible selector showed 2026. Verify the season context before relying on it. | Stage 1: team, roster membership, citizenship, positions. Stage 2: venue. | Accepted as a feature requirement |
| [Benjamín Sagüés Barreiro profile](https://www.transfermarkt.us/benjamin-sagues-barreiro/profil/spieler/1253295) | 2026-10-15 | Player profile | Portrait; birth date and place; citizenships; height; position; preferred foot; current team; joined date; contract fields | The header and the citizenship area showed different amounts of information. | Stage 1: biography, citizenships, positions, memberships. Contract fields excluded (AGENTS.md §1). | Accepted for biography and memberships. Contract fields excluded. |

## Terms of use

Not reviewed by the owner. Do not publish reproductions of these pages. The repository is public, so review the terms soon, and revise or remove this inventory if they prohibit citing these pages.

## Provenance rules

The external URLs above are provenance only. They are not FDB identifiers. No scraped records, images, or portraits are committed.
