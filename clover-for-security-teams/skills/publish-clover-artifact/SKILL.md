---
name: publish-clover-artifact
description: >-
  Publishes the result of any Clover skill as a shareable artifact styled in the Clover product theme.
  Use as the final step of any skill whose output is worth sharing. Renders what Clover already
  returned; it does not query Clover itself.
user-invocable: false
---
# Publish Clover Artifact

Turn a Clover answer into a page that looks like it came from Clover.

Clover holds the data and does the analysis. This skill only renders what another skill already received. It adds no findings, no counts, and no interpretation of its own.

## 1. Scope the request

Publish when the user asks for a page, a link, or something to share. Otherwise present in the conversation and offer this as a follow-up. Two things never publish without the user saying yes: a single application's live weaknesses, and anything naming a customer or researcher.

**Load the `artifact-design` skill before writing the file.** Then write the HTML to a file and publish it with the Artifact tool. Republish the same path to update in place: the link stays stable.

## 2. Build the page

Title: `<Report name> · <subject>`.

Everything below is taken from clover.security's own stylesheet and brand files, so the page reads as Clover's rather than as a generic green report.

### Brand assets

Two SVG files of the **full Clover logo** (the clover mark plus the "Clover" wordmark, 150×32) sit next to this SKILL.md, in the same directory. They are the exact files the website serves. Always use one of them for the page logo. Never use the bare mark alone, never draw the mark by hand, never use an emoji or a different image in its place, and never type the word "Clover" next to the logo: the wordmark is already in the file.

| File | What it is | Use it when |
|---|---|---|
| `clover-logo-dark.svg` | moss-green (`#15291F`) logo on a transparent background | the logo sits on a light surface |
| `clover-logo-white.svg` | off-white (`#F5F5F4`) logo on a transparent background | the logo sits on a dark surface such as the `--ground` header band |

The header band is dark, so `clover-logo-white.svg` is the right choice there; `clover-logo-dark.svg` is for light surfaces.

The artifact sandbox loads no external images, so the chosen file must be embedded as a data URI. Read it with:

```sh
base64 -i "<directory of this SKILL.md>/<chosen file>.svg"
```

and place it exactly like this, keeping the 150:32 ratio:

```html
<img src="data:image/svg+xml;base64,<output>" alt="Clover" width="150" height="32">
```

Place the SVG exactly as it is: no CSS filter, no recolouring, no cropping to the mark, no redrawing. Wherever else the logo appears, apply the same rule and pick the file by the surface behind it.

**Tab icon (favicon)**: the browser tab is controlled by the claude.ai shell around the page, which takes only the emoji `favicon` parameter of the Artifact tool. Pass `🍀` on the first publish and never change it on a republish. A `<link rel="icon">` inside the HTML has no effect on the tab, so do not add one. The official logo appears on the page only.

### Fonts

The website sets three families: **Season Mix** for headings, **Season Sans** for body and UI text, and **Geist Mono** for tags and data. Season Sans and Season Mix are commercial fonts by Displaay Type Foundry whose licence forbids redistribution, so they are not in this repository. Geist Mono is open (SIL OFL) and on Google Fonts, which the artifact sandbox allows.

Load the open stand-ins from Google Fonts with this exact tag at the top of the file, before `<style>`:

```html
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400;500&family=Instrument+Sans:ital,wght@0,400..700;1,400..700&family=Fraunces:opsz,wght@9..144,400..700&display=swap">
```

and define the stacks as tokens on `:root`:

| Token | Role on the page | Site font | Stand-in | Full stack |
|---|---|---|---|---|
| `--font-display` | `h1`, section headings, the verdict sentence | Season Mix | Fraunces | `"Season Mix", Fraunces, Georgia, serif` |
| `--font-text` | body copy, labels, table headers, pills | Season Sans | Instrument Sans | `"Season Sans", "Instrument Sans", system-ui, -apple-system, "Segoe UI", sans-serif` |
| `--font-mono` | every data value: names, statuses, ids, counts, stat figures, tags | Geist Mono | Geist Mono | `"Geist Mono", ui-monospace, "SF Mono", Menlo, monospace` |

The site fonts lead each stack so that the real faces are used wherever they are installed, and the Google Fonts stand-ins render everywhere else. **Optional, licence-holders only**: if `fonts/SeasonSansVF.woff2` and `fonts/SeasonMixVF.woff2` exist next to this SKILL.md, embed each as an `@font-face` with a `data:font/woff2;base64,` source, `font-weight: 300 900`, `font-display: swap`, and the family names `"Season Sans"` and `"Season Mix"`. Do not fetch them from clover.security and do not add them to the repository.

Type rules, copied from the site's utility classes:

- **Headings** (`--font-display`): weight 580 on the site, so use 560 to 600; line-height 1.0; letter-spacing −0.01em. The `h1` in the header band is about 2.75rem, section headings about 1.625rem.
- **Body** (`--font-text`): 1rem to 1.125rem, weight 400, line-height 1.4, letter-spacing 0.025em. Small labels: 0.8125rem, weight 600 to 650, letter-spacing 0.04em.
- **Tags and data** (`--font-mono`): 0.75rem, weight 400, uppercase, letter-spacing 0.1em for tag chips, exactly as the site's `.tag`; data values in cards and tables stay mixed-case at 0.875rem to 1rem.
- Keep the product's signature split: **label in sans, value in monospace**, on every field row and stat tile.

### Palette

Tokens are named after the site's own CSS variables. Define them on `:root`, with the dark counterparts under both `@media (prefers-color-scheme: dark)` guarded as `:root:not([data-theme="light"])` and `:root[data-theme="dark"]`:

| Token | Light | Dark | Site variable |
|---|---|---|---|
| `--ground` (header band) | `#15291F` | `#0D1613` | `--primary-moss` / `--black-400` |
| `--paper` (page) | `#F5F5F4` | `#15291F` | `--daylight` / `--primary-moss` |
| `--card` | `#FFFFFF` | `#1E3D32` | `--white` |
| `--ink` | `#15291F` | `#F5F5F4` | `--primary-moss` / `--daylight` |
| `--muted` | `#828173` | `#C1C0BB` | `--neutral-warm-600` / `--neutral-warm-300` |
| `--line` | `#EAEAE8` | `#2B4B3B` | `--neutral-warm-100` / `--dep-green` |
| `--clover` | `#138869` | `#35D8AD` | `--dark-green` / `--light-green` |
| `--wash` | `#E0F6CB` | `#22493F` | `--grove-green-100` / `--green` |
| `--on-ground` (text on the header band) | `#F5F5F4` | `#F5F5F4` | `--daylight` |
| `--on-ground-muted` | `rgba(245, 245, 244, 0.6)` | `rgba(245, 245, 244, 0.6)` | `--daylight` at 60% |

`body` gets an explicit `var(--paper)` background and `var(--ink)` text. Note the neutrals are **warm** (the site's `neutral-warm` scale), not blue-grey: borders, muted labels and the page ground all lean slightly towards sand. That warmth is most of what makes it look like Clover.

**Text on the header band always uses `--on-ground` and `--on-ground-muted`**, never `--paper` or `--ink`: in the dark theme `--paper` is the same moss green as the band and the heading vanishes.

**Green and neutral only.** The page uses no colour outside this table: no gradients, no glows, no hairlines, no red, amber or turquoise accents, and no colour scale for threat levels, severities or scores. Print the level Clover gave in monospace. The one accent is `--clover`, spent on settled status pills and the headline stat figure.

### Shapes

From the site: cards use a 1px `--line` border and a small 4px radius; tag chips a 6px radius; status pills are fully rounded capsules; buttons and links a 4px radius. No drop shadows except the site's one soft `0 10px 15px rgba(21, 41, 31, 0.10)` on the overlapping verdict card.

### Layout

In this order:
1. **Header band** in `--ground`, full bleed, a plain flat surface with no gradient, glow or bottom hairline, laid out as four stacked rows that all start at the same left edge as the page content below. Never indent the later rows to the logo; the logo is not a gutter column.
   - **Logo row**: the full Clover logo SVG alone on its own line (`clover-logo-white.svg`, embedded as above, height 32). Nothing else sits on this row: no separator, no report name, no extra "Clover" text, since the wordmark is already in the file.
   - **Report row**: the report name (`Top Threats`, `Review Summary`, and the like) as a small uppercase label in `--font-mono`, `--on-ground-muted`, letter-spacing 0.1em, like the site's tags.
   - **Heading row**: the subject (the review, application, or scope name) as the page's `h1`, `--font-display`, large, in `--on-ground`.
   - **Meta row**: a flex row of label/value pairs in small type, `Application`, `Scope`, `Generated <date>` and the like, label in `--on-ground-muted` `--font-text` and value in `--on-ground` `--font-mono`, separated by horizontal gap only.
2. **Standing row**: the one-line verdict in a `--card` box that overlaps the bottom edge of the band by a few pixels, set in `--font-display` with a plain `--line` border and no coloured rule, then three to five stat tiles (label in muted sans above, figure in large monospace). Tiles carry the totals Clover gave; a set that is absent, such as no threat model on record, gets a tile reading `not on record` rather than being left out.
3. **Body**: cards on `--card` with a `--line` border and generous padding (about 1.875rem 2.5rem, as the site's info cards). Field rows read `Label:` in muted sans, value in monospace, exactly as the product does.
4. **Tables** inside an `overflow-x: auto` container, never letting the page scroll sideways. Header cells in small uppercase mono, like the site's tags.
5. **Footer**: `Generated from live Clover data · <date>` in muted sans above a plain `--line` rule.

**Status pills**: a rounded capsule, `--wash` background with `--clover` text for settled states (covered, mitigated, done); `--line` background and `--ink` text for every other state, including `Requires Attention`, blocked, overdue and awaiting approval. There is no third pill colour. Never invent a colour scale for threat levels. Print the level Clover gave.

## 3. Read the answer

Nothing to read: the content arrives from the calling skill. Copy its figures verbatim: no rounding, no re-ordering by a judgement of importance, no section the source didn't provide. A gap in the source is a gap on the page, written as "not on record".

## 4. Present it

Publish, then give the user the link in one line with what's on the page. If they mention Slack or email, offer a short text cut alongside it.
