# Element 10 — Platform Overview

_A comprehensive functional + UI/UX reference. Written for an LLM (or a new teammate) to understand the tool end to end. Each "Major page" section is meant to pair with a screenshot of that page._

---

## 1. What it is

Element 10 is a **command center for running a trading-card-selling operation on Whatnot livestreams.** It is card-focused and **domain-neutral**: sports cards, TCG, and entertainment are peers, and no domain is privileged in the data model, the UI, or the defaults. One operator (plus optional teammates) uses it to plan shows, manage inventory, design and price "breaks," run those breaks live on stream with broadcast overlays, and fulfill orders afterward.

**Domain neutrality is a standing constraint, not a preference.** Inventory carries an explicit `domain` (`Sports cards` / `TCG` / `Entertainment` / `Other`) with a contextual field per domain (`sport` / `game` / `franchise` / `category_detail`). Nothing may default to, hardcode, or infer a specific game, sport, or franchise. Two mislabel bugs have already been paid for by assuming one: players defaulting to Soccer (559 records backfilled, Phase 1), and TCG sets stamped Pokémon on import. Any new surface that needs a domain asks for it.

It is a single-page web app the operator keeps open alongside OBS and Whatnot. It is **not** a Whatnot integration — Whatnot has no open API — so Element 10 is the operator's own planning, live-tracking, and inventory system that sits beside the stream, plus a set of browser-source overlays that render into the OBS scene.

**Primary jobs it does:**
1. Plan the week's shows (schedule + auto-generated show ideas).
2. Manage inventory — graded singles/slabs and sealed wax tracked down to the box, with cost, market value, reservations, and a schedule-driven buy list.
3. Import and browse card checklists (tens of thousands of cards), with players and teams as reusable master records.
4. Design and price a "break format" (how a sealed product is split into sellable spots) and model its viability before running it.
5. Run the break live: mark spots sold, assign winners, watch ROI climb in real time, toggle stream incentives, and cross chases off the board.
6. Broadcast a live overlay into OBS (vertical 1080×1920) that mirrors the break state.
7. Fulfill: a buyer-grouped ship list produced automatically from what sold.

**A "break," briefly:** a breaker opens sealed product live and sells "spots." Common formats: **team breaks** (each spot = one team; the buyer gets that team's cards), **player breaks**, and hybrids like "PICK 2 KEEP 1." Chases are the marquee cards everyone is playing for. Element 10 models, prices, runs, and reports on all of this.

---

## 2. Architecture (context an LLM may need)

- **Client:** `index.html` — a single-file vanilla-JS app, no build step. Companion standalone pages: `open.html` (full-screen pack-opening stage for OBS) and `overlay.html` (the OBS overlays, two selectable layouts via `?layout=`). A viewer companion page also exists.
- **Backend:** Supabase (Postgres 17). Row-Level Security throughout; realtime subscriptions drive the live break + overlays. Storage bucket holds card/logo images.
- **Deploy:** GitHub Actions → GitHub Pages on push to `main`. Live at `https://rev-edge.github.io/element10-app/`.
- **Data lives in three layers (post-M4, 2026-07-15):**
  - **JSONB workspace** (`e10_workspace`, rows scoped `shared` / `universal` / `user:<uid>`): light collaborative data only — notes, to-dos, shows, break models, copy sets, repacks, chase lists, dashboards. **Inventory no longer lives here** (M4 retired the blob copy). Writes are CAS-protected with section-level merge (H2).
  - **Relational tables:** `e10_inventory_items` + `e10_inventory_reservations` (the authoritative inventory, migrated via Chain M/M4); `e10_cards` (~57.3k), `e10_players` (~1,542), `e10_sets` (~538), `e10_checklists`; `e10_teams` (176 rosters); `e10_break_sessions` (now carrying `source_show_ref`) / `e10_break_slots` / `e10_break_events`; `e10_members` + `e10_role_permissions`; `e10_viewers`.
  - **Append-only inventory ledger + receipts:** `e10_inventory_movements` (every inventory change, transactionally emitted by the `e10_inv_*` SECURITY DEFINER RPCs — the ONLY mutation path) and `e10_mutation_receipts` (mutation-level idempotency: key + fingerprint checked before any mutation). No client UPDATE/DELETE path exists on either.
- **Current strategic state:** the platform is mid-**Foundation Gate** (tenancy, environments, CI, bounded reads — see `Element10_ROADMAP.md` product-direction section) in preparation for productization, with a parallel UX/replatform track prototyping the new operator experience. New production modules are not built on the single-org model.
- **Auth:** email/password, invite-only. The account owner is admin. Teammates sign up, then an admin adds them from Settings → Team.
- **Multi-tenant model:** a shared team workspace plus per-user scopes, switchable via a "Viewing" selector (My space / shared / Universal). Inventory ownership is tracked per item with a Mine/Everyone filter.

---

## 3. Navigation & information architecture

Five top-level nav items, each with a sub-nav of rolled-up modules:

| Top nav | Rolls up |
|---|---|
| **Home** | Home cockpit |
| **Schedule** | Schedule · Schedule Generator |
| **Inventory** | Inventory · Checklists · Players · Teams · Break / Format |
| **Live Toolkit** | Live Break · Repack Studio · Ship (fulfillment) · Copy Studio |
| **Reporting & Analytics** | Overview · Reports · Whatnot Export |

Clicking the **profile name** (top-right) opens an account menu: Account settings + Log out, and — for admins only — a **Settings** section linking Team, Lists & Settings, and Permissions.

---

## 4. Major pages (pair each with a screenshot)

### 4.1 Home — the cockpit
An operation-wide financial rollup: **Capital deployed**, **Market value** (with unrealized delta), **Committed to shows**, **Free to break**, **Aging (>30d idle)**, and **Realized (sold)**. Plus quick notes/to-dos. It answers "where is my money and is it working." Numbers roll up from inventory + reservations + realized sales.

### 4.2 Schedule
Plans the week's shows. **Day / Week / Month view toggle** (remembers the last used). Shows are keyed by day-of-week × daypart (a recurring weekly template projected onto the calendar in month view).
- **Show pop-out** (quick edit / go-live only): show name, format, duration, streamer; the break-format model dropdown (+ Build, + Start Live Break); reserved inventory.
- **Full-screen show builder** (from "Create show" or the pop-out's Configure): configures a break end to end — details, break format, products + cost, reserved inventory, title/description copy, repacks, needs, notes. The pop-out and builder edit the same show and stay in sync.
- **Schedule Generator** proposes show ideas from inventory/format data.

### 4.3 Inventory
The economic spine. A configurable data grid plus an add/edit form.
- **Grid:** framed, ruled, zebra table with **Excel-style per-column filtering** (text: contains / does not contain / equals / starts-with / empty; number: = ≠ ≥ ≤ between; enum: multi-select), coexisting with header-click **sort**. Column chooser, saved views, Reset. A top rollup band (Capital deployed / Market / Committed / Free / Aging / Realized). Owner filter (Mine/Everyone).
- **Add/Edit item (in-place edit):** name, category, set/product, **cost basis (per box / per case) + boxes-per-case + derived per-box cost**, quantity (boxes on hand), market value, grading company, grade, card #, year, parallel, card type, serial, condition, owner, image (upload or URL). Inline validation (name required; costs/qty ≥ 0; boxes/case ≥ 1).
- **Box/case model:** sealed wax is tracked at the **box** as the atomic unit; a product carries boxes-per-case so it can be sliced full case / half case / N boxes. Committing boxes to a break decrements on-hand; removing returns them (idempotent, reversible).
- **Quick-add from the card library:** type a player/card/set → autofill fields and link the item to its `e10_cards` record (+ player).
- **Reservations & buy list:** items can be hard-reserved to a scheduled show; the schedule-driven buy list surfaces what needs acquiring; `available = qty − reserved`, clamped so it can't go phantom.

### 4.4 Checklists
Manages the card catalog.
- **Checklists list:** each checklist file (name, set, card count) with Open / Break / delete actions.
- **Import:** two paths, both accept `.xlsx` and `.csv` and both let you review/edit before commit. **Smart import** uses an LLM (server Edge Function) to map arbitrary layouts (Topps/Beckett/etc.) to the app's fields and infer base/parallel/insert. **Direct import** is for an already-formatted file (no AI). Required column: Card Name; optional: card #, set, rarity, market value, parallel, card type, chase.
- **Card grid:** server-backed and paginated over the full dataset (55k+), with open-ended multi-word search, per-column filters that push down to the query (filter across all pages, not just the visible one), sort, and a column chooser. Cards carry structured fields (grade, parallel, type, serial, chase, etc.) and link to a player and team.
- **Chase lists:** reusable, per-sport/league lists of **players**. Apply a chase list to a checklist to flag every matching card as a "chase" (match by player id, then normalized name). Also bulk-mark chase by the current filter. Chase flags flow automatically to the break planner's chase pool and the on-cam chase board.

### 4.5 Players
Master records — every card of a player across all sets/years. Searchable/sortable grid (Player / Team / Nationality / Sport). Each player links to an "all cards" view. Players are deduped by a normalized-name unique index.

### 4.6 Teams
A **sport → league → team** hierarchy browser. 176 rosters are seeded (NBA 30, MLB 30, NFL 32, NHL 32, Premier League 20, Soccer Nations 32). Browse a league's roster; add/edit/remove teams; add a new league or a custom character set for non-sports breaks. **Per-team logo** via upload or pasted URL (renders on the overlay team board; a monogram is the fallback). This is where team logos get populated.

### 4.7 Break / Format planner
Designs and prices how a product is split into sellable spots.
- **Generate spots** four ways: attach a saved format; by **team** (pick sport → league → load that roster, one slot per team); by **player** (from a checklist's players); or build on the fly. A rule-based slot model supports carve-outs (e.g. "Liverpool minus Rio" + "Rio only") with a server-side partition check (every card covered once, no overlaps).
- **Tiers + pricing:** assign tiers with expected-hammer bands (pre-ranked by modeled value); per-spot **sale method** ($1 auction / set-start / fixed); a **low/expected/high viability projection** vs product cost and margin goal, with a **concentration flag** (how much a few marquee spots carry) and a downside scenario.
- **Chase pool:** the chase-flagged cards for the product.

### 4.8 Live Toolkit → Live Break
The core live-show module. Built on the relational break-session tables with realtime.
- **Pre-flight review:** starting a break opens a review before going live — stream title, participants (hosts), products included (with case/half/N-box slicing and live break cost), slot loading (roster/player/on-the-fly/attach), last-minute slot edits, and the average slot target. Confirm → commits box decrements and goes live.
- **Live board:** a fast, forgiving worklist of spots. Per spot: **Mark sold** → assign the winning handle (typeahead over the session viewer roster; new handles allowed) + hammer price; one-tap edit/reopen. Live header shows **actual hammer vs projection vs cost, ROI% climbing negative→positive (green past break-even), per-slot target-vs-actual deltas, and "to break even / to margin goal."**
- **Incentives:** toggle Stash-or-Pass, Case Hit, Trade Block, See-2-Pick-1 → these drive **placard cards** on the on-cam overlay and are **stamped onto each sold slot** so slot performance can later be split by incentive (attribution).
- **Chase board:** mark a chase "hit" and it crosses off the on-cam overlay live, with the "N LEFT" count dropping.
- **Products / cost editor:** add/remove products mid-show; cost and ROI update live.
- **End** ends the session server-side.

### 4.9 Live Toolkit → Repack Studio + Opener
Build "repacks" (curated card packs) and run a full-screen **pack opener** (`open.html`) as an OBS scene, with reveal animation, sound, and a chase-hit celebration.

### 4.10 Live Toolkit → Ship (fulfillment)
The off-stream payoff. Flips sold spots from by-spot to **by-buyer across all shows**: each buyer → every spot they won (show, date, spot, hammer, and the cards to pull), a per-buyer total, and packed/shipped status with a tracking note. Also surfaces **modeled-vs-actual** margin per completed break.

### 4.11 Live Toolkit → Copy Studio
Generates Whatnot show titles and descriptions from templates (curiosity / search / drama variants), pulling in set, character, format, host, difficulty, and price.

### 4.12 Reporting & Analytics
Overview, Reports, and **Whatnot Export** (mapping Element 10 data to Whatnot's inventory import template). Deeper cohort analytics (e.g. 30-slot vs 50-slot breaks, stash vs no-stash) are planned once real break-run data accumulates.

### 4.13 OBS overlays (`overlay.html`, vertical 1080×1920)
Two selectable layouts, both driven by the live session over realtime, styled to survive Whatnot's ~3 Mbps compression (bold, high-contrast, no hairlines). The bottom ~15% is kept clear for Whatnot's native bid bar.
- **On-cam** (`?layout=oncam`): a transparent top camera zone for the streamer's face, name-plates + branding ticker, **physical-placard status cards** (Stash-or-Pass / Case Hit / Trade Block / See-2-Pick-1) that pop in only when active, a **live cross-off chase board**, and an "On the block" current-spot bar.
- **Graphics-forward** (`?layout=graphics`): a dominant **team board** (one tile per spot; logo or monogram; bright = available, dim = sold; "N LEFT" count), format-mechanic text down both side rails, a LIVE pill, a configurable **giveaway module** (label + countdown + entries, operator-run), a socials bar, and brand chevrons framing the product cam.

### 4.14 Settings (admin) — Team, Lists & Settings, Permissions
- **Team:** add/remove members, assign roles.
- **Lists & Settings:** user-maintained pick-lists (categories, formats, grading companies, conditions, etc.) that feed the searchable pickers app-wide.
- **Permissions:** a roles × capabilities matrix. Capabilities cover module access (Home/Schedule/Inventory/Live Toolkit/Reporting/Settings) and key actions (edit inventory, run/assign live breaks, manage team, edit lists, export, configure permissions). Admin is a hard-wired superuser. **Enforcement is two-layer:** client gating hides what a role can't use (UX), and server-side RLS additively gates the sensitive mutations (the real security). Note: module-visibility gating is UI-level; the true security boundary is the server action gates.

---

## 5. Core end-to-end workflow

1. **Import a checklist** (Smart or Direct) → cards land in `e10_cards`, linked to players/teams; flag chases (bulk or via a player chase list).
2. **Load inventory** — add the sealed product (box/case cost basis) and any singles; quick-add links singles to the catalog.
3. **Design the format** — generate spots (team roster / players / on the fly), tier + price them, read the viability projection.
4. **Schedule the show** and attach the format, products, copy, repacks, needs.
5. **Go live** — pre-flight review sets products/cost/slots → live board. As spots sell, assign winners + hammer; ROI climbs; toggle incentives; cross off chases. The OBS overlay mirrors it all.
6. **Fulfill** — the Ship view groups everything by buyer into a pack-and-ship list; modeled-vs-actual shows the break's real margin.

---

## 6. Design language & UI conventions

Element 10 follows a deliberately **terse, low-noise** aesthetic. Codified rules:
- **No grey instructional/helper prose anywhere** — the muted-grey text style is reserved strictly for genuine secondary data (values, counts, deltas, timestamps), never for "how to use this" text or descriptions.
- **Minimal placeholders** — a labeled field gets no "e.g. …" placeholder; a single format hint only where truly non-obvious (e.g. a dual grade "10 / 9.5").
- **No decorative emojis** in titles/headers; functional status glyphs only, sparingly.
- **No redundant info** — never repeat data shown in an adjacent column/tag.
- **Consistent casing** — one convention per element type (sentence-case field labels, uppercase-mono column headers/keys, etc.).
- **Empty states**: one terse line, no how-to.
- **Universal data-grid** styling (framed, ruled, zebra) and **Inter** typography with a volt-green accent.
- **Reusable components:** a searchable entity picker (typeahead that stores an id link, e.g. cards/players/sets/teams/inventory) and a searchable picklist (combobox over the user's pick-lists). Fields across the app store real id links, not typed strings, so relationships are queryable.

---

## 7. Roles & data-integrity notes (for accurate mental model)

- Chase status is a **card-level flag** materialized from player-driven chase lists; the break board/planner read that flag.
- Break spots are **rules over a checklist**, not fixed teams — a partition check keeps a break's spots covering every card exactly once with no overlap.
- Inventory writes and live-break mutations are **server-enforced** by RLS + capability gates; the account owner/admin always retains full access.
- Live-break capture is designed to be fast and forgiving (one-tap sold/edit/reopen) because the operator runs it solo while hosting.

---

## 8. Known gaps / roadmap (so the picture is complete)

**The canonical plan and sequencing live in `Element10_ROADMAP.md`** — this section lists standing gaps, not order of work.

- **Concurrency and write integrity (in active repair):** output encoding gaps (`esc()` quote escaping) and failed-write cache poisoning are fixed in Hotfix H1; blind whole-document workspace writes get compare-and-swap protection in H2. Until H2 lands, concurrent edits to the shared/scoped workspace rows are last-write-wins.
- **Inventory mutations are not yet transactional:** the movement ledger + emit RPC exist, but inventory writes and movement emission are not committed together. Passes 2.7–2.9 (after the D1 storage decision) build the transactional mutation RPCs.
- **Team logos** not yet populated (monogram fallback renders); the Teams page is the surface to add them.
- **Uniform grid filtering** is live on Inventory + the card grid; other tabular surfaces (buy list, reporting tables, players/teams lists, fulfillment detail) are being migrated onto the shared engine one at a time.
- **Phase D reporting** (cohort comparison across breaks) is intentionally held until real break-run data exists.
- **Real show revenue import** (Whatnot Weekly Orders CSV) is the largest remaining "am I making money" gap for non-break sales.
- Working brand name is "Element 10."
