# Documentation project instructions

## About this project

- This is a documentation site built on [Mintlify](https://mintlify.com)
- Pages are MDX files with YAML frontmatter, written in Dutch
- Configuration lives in `docs.json`
- Use the Mintlify MCP server, `https://mcp.mintlify.com`, to edit content and settings via MCP
- Use the Mintlify docs MCP server, `https://www.mintlify.com/docs/mcp`, to query information about using Mintlify via MCP
- For Mintlify product knowledge (components, configuration, writing standards), install the Mintlify skill: `npx skills add https://mintlify.com/docs`

## Page template

Every page under `beheerders/` and `medewerkers/` has frontmatter (`title`, `description`) and these sections, in this order. Leave out a section only when it has nothing to say.

1. `## Waar deze pagina voor is` — the purpose, in one or two sentences.
2. `## Wie dit mag gebruiken` — the role or permission that opens the page.
3. `## Zo gebruikt u deze pagina` — numbered steps; one action per step, UI names in bold.
4. `## Velden` — each field with what to enter; mark required fields.
5. `## Wat er daarna gebeurt` — the result of the last step.
6. `## Beperkingen` — what the page cannot do and what depends on setup (see the payroll rules below).
7. `## Laatst gecontroleerd tegen versie X.Y.Z` — the release tag (`X.Y.Z`) the page was last checked against in the demo workspace.

Screenshots (`## Schermafbeelding`) come from the demo workspace and sit after the purpose section.

## Form of address

Use **u**, never *je*. The existing pages in `beheerders/` and `medewerkers/` all address the reader as "u" and "uw" ("U beheert hier onder meer opdrachtgevers"). Keep sentences concise, one idea per sentence, and use sentence case for headings.

## Terminology

Use the term in the first column, not the one in the second. These follow the existing pages.

| Use | Not |
|-----|-----|
| tijdregistratie (plural: tijdregistraties) | urenregistratie, urenstaat |
| medewerker | werknemer, personeelslid |
| bestuurder (in tachograaf and vehicle context) | chauffeur, driver |
| opdrachtgever | klant, relatie |
| voertuig, trailer | wagen, aanhanger |
| tachograaf | tacho, tachograph |
| druppel | beacon, tag |
| tracker | volger |
| locatie | adres, plek |
| beheerder | admin, manager |
| overzicht | lijst |
| aanmaken, bewerken | toevoegen, wijzigen (for the page titles) |

Module names: Wagenparkbeheer, HR-beheer, Urenbeheer, Klantenbeheer, Werk. A medewerker is the person; use "medewerker" for the person, never for a contract.

## Payroll pages

- A payroll page describes what the system does, not what a CAO says or what should happen.
- Mark every statement that depends on CAO or contract setup with the sentence "Dit hangt af van de CAO of de contractinstelling." and name which of the two it is; never state such a result as fixed.
- Do not describe a calculation you have not seen run in the demo workspace.

## Content boundaries

- Pages name no customer and no customer-specific rule. Describe the product's behaviour with generic examples only.
- Do not document internal admin features, production data, or unreleased behaviour.
- Use no real names, plates, e-mail addresses or phone numbers; use the demo seed's data.

## Release lines

- Docs keep a `release/X.Y` line for each Platform line from 0.4 on; a page on `release/X.Y` describes Platform X.Y.
- A change to released behaviour goes into the docs line of that Platform version. New, unreleased behaviour goes to `main`, which becomes the next line.
- A Platform hotfix `hotfix/X.Y.Z` takes its docs correction into docs `release/X.Y`.
- Platform 0.2 and 0.3 have no docs line.

## Demo workspace and seed

Every docs task checks its page against one workspace and one seed, so screenshots and steps stay reproducible:

- Workspace: `docs-demo` — create it with `make workspace docs-demo` and start it with `make ws docs-demo up`.
- Seed: the `docs-demo` seed, loaded into that workspace only. Nothing from production is copied into it.

Check each page against that workspace on the release tag named in its last-verified line, and update that line only after the check.

## Screenshot runbook

Screenshots in `images/captures/` are generated, never hand-made. The manifest `images/captures/manifest.json` lists every shot: `file`, `url`, `role` (`admin` or `worker`), an optional `selector` (element to shoot; default the whole viewport) and an optional `mask` list of `{selector, replace}` for names on that page. The manifest's `masks` replace every email address and amount on every page with fixed demo values, and the clock is fixed, so a rerun on an unchanged app gives identical files.

1. Start the demo workspace with the demo seed: `make ws docs-demo up`. The capture refuses `transportklok.nl` hosts.
2. Run `scripts/docs-captures/capture.sh --app-url=http://localhost:<port>` from the workspace root. The admin role signs in with the seeded dev account; give the worker role (and any other login) with `--credentials-file=<file>` as `{"worker":{"email","password"}}`. Use `--only=slug,slug` to refresh a few shots.
3. Read the summary: `added`, `changed`, `unchanged` and `failed` per file. A full run with no failures also rewrites `images/captures/index.json`.
4. Review the diff of `images/captures/` and commit only the shots whose page you changed. Look for any real name or amount that the masks missed and add a `mask` entry for it.
5. To add a page, add one manifest entry and rerun with `--only=<slug>`.

Check the masking with `cd scripts/smoke && node ../docs-captures/test-mask.js`.
