---
name: publish-clover-artifact
description: >-
  Publishes the result of any Clover skill as a shareable artifact styled as a Clover page.
  Use as the final step of any skill whose output is worth sharing. Renders what Clover already
  returned; it does not query Clover itself.
user-invocable: false
---
# Publish Clover Artifact

Turn a Clover answer into a page that looks like Clover made it, in the same visual system as Clover's one-pagers and field guides: Clover green and sage on daylight grey, Fraunces light headlines with a sage highlight, IBM Plex Mono chips, stacked sheets, and a green gradient closing band.

Clover holds the data and does the analysis. This skill only renders what another skill already received. It adds no findings, no counts, and no interpretation of its own.

## 1. Scope the request

Publish when the user asks for a page, a link, or something to share. Otherwise present in the conversation and offer this as a follow-up. Two things never publish without the user saying yes: a single application's live weaknesses, and anything naming a customer or researcher.

**Load the `artifact-design` skill before writing the file.** Then write the HTML to a file and publish it with the Artifact tool. Republish the same path to update in place: the link stays stable.

## 2. Build the page

Everything you need is in `assets/`, next to this SKILL.md:
- `template.html`: every token and component, with placeholder content. The first sheet is the report opening for a Clover answer; the rest are the general components. Start here and delete what the page does not need.
- `example-kura-and-the-mcps.html`: a finished page built with the same system. Read it to see how the components combine.
- `clover-logo.svg`: the Clover mark and wordmark, colored through `currentColor`.

### How to build it

1. Copy `assets/template.html`. Keep the `<style>` block as is. Change tokens only, never hard-code a color in a component.
2. Decide the sheets. One sheet is one printed page. Most reports need one to three: the report opening, then one sheet per large section Clover returned. Each sheet opens with the top row: logo left, one mono chip right naming what the sheet is (`Review summary`, `Top threats`, `Remediation plan`).
3. Pick components for the content Clover returned, not the other way round (see below).
4. Write the words the page adds (chips, section labels, headline) against the copy rules below.
5. The file needs no `<html>`, `<head>` or `<body>` tags. The template is already written that way.

**Title**: `<title>` is a name of two to four words: the report and its subject, such as `Payments review summary`. Put the longer description in the Artifact tool's `description`.

**Tab icon**: pass `icon: "shield"` on the first publish and omit it on a republish. A `<link rel="icon">` inside the HTML has no effect on the tab, so do not add one.

### Logo

The logo is the inline `<svg class="logo">` already in the template's top row, the same paths as `assets/clover-logo.svg`. It takes its color from `--accent`, so it follows both themes by itself. Keep it exactly as it is: no filter, no cropping to the mark, no redrawing, no emoji or other image in its place, and never type the word "Clover" beside it, since the wordmark is already in the SVG. The artifact sandbox loads no external images, so never reference the file by URL.

### Tokens

Official palette, from the Clover Brandbook:

| Token | Light | Role |
|---|---|---|
| Clover green | `#154336` | Headlines, labels, accent text |
| Dark green | `#15291f` | Body text; dark-mode sheet |
| Sage | `#cef1ae` | Headline highlight, filled chips; dark-mode accent |
| Cream | `#fcf4e1` | Text on the green band; dark-mode text |
| Daylight | `#f5f5f4` | Sheet background |

The page ground behind the sheets is a step darker (`#ecece9`) so sheets read as paper. Dark mode is already defined in the template: dark green sheets, cream text, sage accent. Keep both themes working; the page follows the viewer's setting.

**Green and neutral only.** No red, amber or other accent, and no color scale for threat levels, severities or scores. The one gradient is the closing band.

### Type

- **Fraunces**, weight 300, for h1, h2 and stat figures. Light and large. Highlight one phrase in a headline with `<mark>`, which paints sage behind it. On a report, mark the subject's name: `Top threats in <mark>Payments API</mark>`. One `<mark>` per headline, at most.
- **Public Sans** for everything else. Body 15px, lede 17px.
- **IBM Plex Mono**, uppercase with letter-spacing, for chips, table headers, `dt` labels and "Doc:" lines. Mixed-case `.mono` for data values that are identifiers: ids, levels, dates, counts inside prose. Mono means "a label or a real product term", never running text.

### Components

Report components, for rendering a Clover answer:
- **Report opening** (first sheet of the template): chip with the report name, h1 with the subject, the lede, a `dl.facts` meta row (Application, Scope, Generated), then the stat tiles.
- **Lede** (`.lede`): Clover's own verdict or status line, copied verbatim. If Clover gave none, omit the lede; never write one.
- **Stat tiles** (`dl.stats > .stat`): mono label above a Fraunces figure, three to five of them, carrying the totals Clover gave. A set that is absent, such as no threat model on record, gets a tile with `<dd class="none">not on record</dd>` rather than being left out.
- **Data table** (`.tablewrap > table.data`): threats, requirements, applications, any list Clover returned. Row label in green, levels in `.mono` exactly as Clover gave them, statuses as chips. The wrapper scrolls sideways on phones; the page never does.
- **Status chip** (`.chip.status`): a rounded capsule. `.chip.fill.status` (sage) for settled states: covered, mitigated, done. Plain `.chip.status` (outlined) for every other state, including Requires Attention, blocked, overdue and awaiting approval. There is no third style.

General components, from the Clover page design:
- **Sheet** (`.sheet`): the page. Top row, headline, then content, 32px between blocks.
- **Section label** (`.section-label`): names a section Clover returned, in Clover's order.
- **Chip** (`.chip`, `.chip.fill`): outlined for context, filled sage for the thing itself (a product name, a mechanism).
- **Card** (`.card`): one item the reader compares, such as one application, with a `dl.facts` row of up to three short fields. Never wrap a plain paragraph in a card.
- **Journey** (`ol.journey`): numbered steps. Use it only when Clover gave a real sequence, such as a remediation plan's ordered actions.
- **Key list** (`.key`): term in Fraunces, definition beside it. For levels, modes and glossary items Clover defined.
- **Band** (`.band`): closing gradient strip from Clover green, full bleed to the sheet edges, once per page on the last sheet. It holds the links Clover returned (the review, the application in Clover) and the footer line `Generated from live Clover data · <date>`. If Clover returned no links, the band holds only the footer line.
- **Says** (`.says`): quoted customer lines. Reports do not use it.

### Copy rules

For the words this skill writes itself (chips, section labels, headline, tile labels, band label):
- No em dashes. Use commas, periods or colons.
- American English (organization, license, program).
- Never write "AppSec". Write "security" or "security posture".
- Never call Clover an "assistant". Say "Clover".
- Active voice, short. The words the label needs, and no more.

Text that comes from Clover stays verbatim, even where it breaks these rules. The copy rules never justify rewording a finding.

## 3. Read the answer

Nothing to read: the content arrives from the calling skill. Copy its figures verbatim: no rounding, no re-ordering by a judgement of importance, no section the source didn't provide. A gap in the source is a gap on the page, written as "not on record".

## 4. Check it

- The page reads correctly at phone width with nothing cut off.
- Dark mode is legible.
- No em dashes in the words the skill wrote: search the file for the character.
- Every figure on the page appears in Clover's answer, and every link is one Clover returned or docs.cloversec.io.

## 5. Present it

Publish, then give the user the link in one line with what's on the page. If they mention Slack or email, offer a short text cut alongside it.
