# Kjol Icon Design Exploration

> **Status:** Concept & reference document
> **Created:** 2026-08-26
> **Directory:** `~/Desktop/kjol-icon-exploration/`
> **Renders:** `renders/` (5 × 512×512 PNG files)

## 1. Application Context

**Kjol** is a native macOS menu bar utility for Apple Silicon power management and hardware control.

### What it does
- **Clamshell Always-On** — Keep Mac awake with lid closed
- **Native Fan Control** — Auto / Quiet / Balanced / Blast / Custom profiles through SMC
- **Hardware Charge Limiter** — Battery health protection (for example, 80% threshold)
- **Daemon Suspension** — Pause Spotlight, media analysis on demand
- **Live System Telemetry** — SoC/CPU/GPU temps, fan RPMs, CPU core utilization, battery
- **In-App Updates** — GitHub Releases auto-check + one-click upgrade

### Current icon situation
- **No custom icon exists.** The menu bar icon is currently an SF Symbol: `NSImage(systemSymbolName: "bolt", accessibilityDescription: "Kjol")` — a generic system lightning bolt.
- No `.icns` file, no `Assets.xcassets`, no `Contents/Resources` images in the bundle.
- Icon is rendered as a **template** (tinted by macOS), with accent tint applied when "Always-On" is active.
- App icon (`.icns` in `Contents/Resources/`) is not referenced by `Info.plist` (no `CFBundleIconFile` key) — standard for a polished distributed app, but currently absent.

### Where to place custom art
- **Menu bar icon:** set on `NSStatusItem` button in `AppDelegate.updateStatusItemIcon()` (lines 516–530 of `main.swift`) and `applicationDidFinishLaunching` (lines 542–586). Currently `NSImage(systemSymbolName: "bolt")`.
- **App icon (`.icns`):** added to `Contents/Resources/`. Referenced (optionally) through `CFBundleIconFile` in `Info.plist`. Used in Finder, About This Mac app list, and so on.
- **Popover illustrations:** card-header accents, header motif, or central illustration in the 360×490 popover.

## 2. Meaning of "Kjol"

The name carries three related but distinct meanings (Norwegian/S Scandinavian):

### Kjol = "skirt" (noun)
A skirt wraps, flows, and covers. Visually: a curved form around a core — maps to **airflow swirl around the SoC**, or a protective "layer" the app puts around the system. Drapes low and tidy — suits a menu bar app that sits unobtrusively at the top of the screen.

### Kjol = imperative "chill!" (verb)
**The most on-theme meaning.** The app is literally about **cooling**: fan control, thermal telemetry, quiet profiles, keeping the Mac from cooking itself. "Chill!" is a command to bring the temperature down — exactly the action the app does. Carries the "whisper-quiet efficiency" tagline vibe.

### Kjol = "keel" (nautical)
A keel is the **backbone/bottom of a ship** — what keeps it steady and on course under load. Maps to **stability, foundation, "taking back control"** of a system that otherwise runs hot and unpredictable. A keel is low and central — a nice metaphor for a menu bar utility that sits at the base of the UI and keeps things level.

### Tension to lean into
"Skirt" and "keel" are structural/wrapping/base concepts. "chill" is a thermal/action concept. The app sits at that intersection: it keeps the Mac **steady (keel)** and **cool (chill)** by managing the **airflow/power around it (skirt)**. Pick one meaning as primary visual. Let the others show up as secondary cues.

## 3. The ø Character

The "o" in Kjol uses the **ø** (o with stroke) — not an accented o, but a **native letter** in Norwegian and Danish (its own letter, sorted after z). It represents the sound /ø/ (like English "u" in "burn").

### Visual anatomy
- An **o bisected by a diagonal stroke from upper-left to lower-right**.
- The stroke is **structural, not an add-on** — it is what makes the letter itself.
- The stroke **natively divides the bowl into two halves** — exactly the property we want for a chill/flow split.

### How it maps to the concept
- **The ø is the icon.** Not a bolt, fan, thermometer, or gear — an ø with a deliberate split is ownable and distinctive.
- **The stroke is the seam** between two halves: one half "chill" (cooling/stable), one half "flow" (airflow/active). The stroke is the boundary between hot and managed, raw and controlled.
- **Scalable** — an ø is a single glyph, clean geometry, reads at 16px (menu bar) and 1024px (app icon).
- **The icon *is* the name** — strongest possible brand connection.

### Design parameters agreed on
- **Stroke direction:** diagonal (traditional Nordic: upper-left → lower-right, ~135°).
- **Halves:** can move away from strictly bowl shapes, but must retain the general idea of the letter.
- **Literalness:** lean **abstract** rather than literal (no literal fan blades, thermometers, or generic speed-control clipart).
- **Color start point:** system colors (template-friendly, dark/light adaptive). Determine if a brand color pair is needed later.
- **Order of work:** start with the **app icon**, then adapt for menu bar icon and popover illustrations once the core direction is settled.

## 4. Concept Directions Discussed

### Direction 1 — "Chill" primary (cooling mark)
A bold mark reading as temperature coming down:
- A bolt (power/energy) with a chill ring or cooling arc around it — power tamed, not raw.
- A descending temperature glyph: hot core + cooler sweep/arc.
- A single drop or cooling pulse — minimal, works at menu bar size.

**Menu bar fit:** strong — chills are simple shapes.
**App icon fit:** bolt+drop or bolt+arc into a richer 512px icon with gradient/depth.
**Popover fit:** small cooling-drop accent in card headers, or larger thermal illustration in telemetry card.

**Risk:** "chill" on its own can drift into generic freezer/air-conditioning territory. Needs the power element (bolt/energy) attached to stay about the Mac.

### Direction 2 — "Keel" primary (stability mark)
A low, strong, horizontal form suggesting a keel — a centered backbone that keeps things level under thermal load:
- Shallow triangular or wedge profile (classic keel silhouette) as the core mark, possibly with a subtle airflow line along it.
- Horizontal baseline with a centered structural element — reads as "foundation / control / steady."
- Could pair with a small thermal indicator (dot or ring) to say "this is about the system running steady and cool."

**Menu bar fit:** good if kept geometric and minimal. Thin horizontal + one focal mark works at 16–22px.
**App icon fit:** strong — keel profile can be the base of a more elaborate icon with the Mac/SoC implied above.
**Popover fit:** keel-like baseline can anchor popover header or act as a divider motif.

**Risk:** "keel" is more abstract — a bare keel might read as nautical/sailing rather than Mac power management. Needs the chill/power layer on top.

### Direction 3 — "Skirt" primary (flow/wrap mark)
A flowing form that wraps around a core — airflow, protection, the app "draping" over the system:
- Single curved sweep or layered arc around a central dot/bolt — like a fan airflow profile or a protective wrap.
- Tapered form (wider at one end, narrowing) suggesting a skirt/drape without literally being a garment.
- Readable as air wrapping the SoC — directly about what the fans do.

**Menu bar fit:** trickier at small sizes. Flow marks can turn into blobs at 16px unless very geometric. A single clean arc + core dot is safest.
**App icon fit:** excellent — flow/swirl gives a richer 2D shape at 512px.
**Popover fit:** airflow swirl is a natural illustration for the fan control card.

**Risk:** "skirt" as a garment is the literal meaning but visually risky — can look like fashion/apparel rather than system control. Treat "skirt" as the abstract property (flow, wrap, coverage) rather than depicting a skirt.

### Direction 4 — Combined (layered mark)
A single icon layering the three readings: structural base (keel) + wrap/flow around it (skirt/airflow) + thermal/chill cue (cooling):
- Low keel-like baseline, central core (the SoC/power), cooling arc or ring sweeping around it.
- Bolt (power) whose base sits on a subtle keel line, with a chill ring/arrow around it showing temperature being managed.
- Tapered "skirt" flow around a cooled core — reads as "power, managed and cooled, held steady."

**Menu bar fit:** simplify to a single unified mark (whole composition compressed to one glyph). Use full layered version for app icon and popover illustrations.

**Risk:** more elements = more chance it reads as busy or unclear. Best if one element dominates. Others are subtle reinforcements.

## 5. Aesthetic Tone

Given the product — a serious, native, single-purpose macOS utility for Apple Silicon:
- **Scandinavian-ish minimalism:** clean geometry, restrained, functional, not decorative for its own sake.
- Works in **template mode** (menu bar) and in **color** (app icon, popover). Dark/light adaptive.
- Prevent literal fan blades, thermometers, or generic "speed control" clipart — those read as generic system-monitor utilities. The Kjol meanings give a more distinctive vocabulary.

## 6. Generated Renders (5 concepts)

All renders are 512×512 PNG files in `renders/`:

- File | Concept | ø-clarity | chill+flow read | Notes
- `kjol-icon-01-split-diagonal.png` | Bowl split into cool-gray left / accent-blue right by a thick diagonal stroke. Left side gets descending white ticks (chill), right side gets a purple chevron (flow). Subtle outer ring. | **Clear ø** — circle + diagonal slash. Reads as Ø with two-tone halves. | Strong — gray+blue = cool. Diagonal stroke = movement. Chevron = flow. | Stroke weight is heavy. Right chevron reads more "play/back" than "airflow/swirl."
- `kjol-icon-02-aperture-rings.png` | Concentric rings: outer ring split-tone, thin dotted violet ring inside, inner solid core split the same way. Diagonal keel line through everything. Chevron + ticks inside. | **Abstract ø-feel** — not a literal letter. Reads more like a gauge/aperture with a slash. | Strong chill+flow through cool palette + directional chevron. | Drifts toward "gauge/aperture." Letter identity is weaker.
- `kjol-icon-03-geometric-split.png` | Letter-less: rounded gray rectangle (left) + blue triangle wedge (right). Diagonal separator. Keel line at bottom. Descending ticks + chevron. | **Not an ø** — reads as "list + play button" collaged. Ditched the letter entirely. | Strong chill+flow vibe (calm column + play/energy wedge). | Good "chill+flow" abstraction, but loses the ø/name connection.
- `kjol-icon-04-typographic-ø.png` | Stylized ø hero: two-tone bowl (cool gray / accent blue), thick diagonal stroke with a thinner inner violet glow line. Crest ticks + chevron. Outer frame ring. | **Clear stylized ø** — closest to an actual Ø letter but with color-split and accent details. | Strong — most "ø-like" while still signaling chill+flow. | Letter identity is strongest here. Stroke weight still heavy relative to bowl.
- `kjol-icon-05-minimal-ink-ø.png` | Minimal ink-style: one thick bowl drawn as two arcs (gray + blue), diagonal stroke as the only strong line, tiny purple dot + tiny tick/chevron, keel dot near center. | **Clear minimal ø** — unambiguous Ø, very restrained. | Chill+flow reads through palette and direction, subtle. | Most restrained. Stroke is the only strong separator. Good for template/menu bar.

### Cross-cutting observations
- **ø-coherent candidates:** 01, 04, 05 read as an actual Ø letter (or a clean abstraction of one). 02 drifts toward "gauge/aperture." 03 abandons the letter entirely.
- All five hit chill+flow through **cool palette + directional glyphs** — that part worked across the board.
- Diagonal angle (~135°, upper-left → lower-right) is consistent across all — the Nordic stroke direction.
- The diagonal stroke weight varies: 01 and 04 carry a heavier stroke (more "ø-slash" presence). 05 is the most restrained.

### Things to refine
- **Right-half flow glyph:** currently a purple chevron in 01/04 — reads more "play/back" than "airflow/swirl." Consider a sweeping curve instead to read more "airflow."
- **Left-half chill glyph:** currently descending ticks — reads "temperature dropping" (good), but could also be a small downward arc or tapered form to feel more "settling/cooling."
- **Keel concept (stability):** currently represented by the centered dot or bottom line — subtle. If keel is a priority, make it more present (flared base, more intentional anchor).
- **Stroke weight against. bowl ratio:** in some renders the stroke is very dominant (almost too heavy against. a real ø where the stroke is lighter). Tune so it reads as a letter mark, not a bisected disc.
- **Letter anatomy fidelity:** the ø's stroke is structural — the render must feel like a letter mark with two-tone fills, not a circle bisected by an arbitrary line. The stroke must feel *native* to the form.

## 7. Feedback on Execution

> "Your concepts are right, but the execution is not."

The **concept direction** (ø letter, diagonal stroke as seam between chill/flow halves, abstract, system colors, start with app icon) is sound. The **executions** (all 5 renders) are off in a few ways:

- **Stroke weight is too heavy** relative to the bowl — makes it read as a bisected logo, not an ø letter mark.
- **Flow glyph defaults to chevron** — reads as "play/back" rather than "airflow/swirl." Needs a different shape language.
- **Chill glyph defaults to ticks** — functional but generic. Could be more deliberate.
- **Keel presence is too subtle** — if keel is part of the concept, it must be more intentional.
- ** ø anatomy is loose** — some renders drift toward "circle + slash" rather than a coherent letter form with two-tone halves.

### What "better execution" would look like
1. **Stroke weight dialed back** — closer to a real ø letter: the stroke is a clean cut through the bowl, not a thick bar dominating the face.
2. **Flow glyph = airflow/swirl language** — a curve, a swept form, a directional arc. Not a chevron or arrow.
3. **Chill glyph = cooling/settling language** — a downward taper, a cooling ring, a settling arc. Not just ticks.
4. **Keel = intentional anchor** — if present, it must read as "base/stability," not just a dot.
5. **Halves feel like a letter** — the two halves must read as "one ø, split by its native stroke," not "two shapes shoved together."
6. **Abstract but legible** — not literal fan blades or thermometers, but the chill/flow/keel readings must be discernible, not just implied by color.

## 8. Image Generation Notes

### What's available against. what was used
- **No native static image generation tool** in the Hermes tool set for this session.
- FLUX 3 tools available are for **video generation** (text-to-video, image-to-video, keyframe-to-video, video continuation) — not still images.
- The renders above were produced **programmatically** (Python + Pillow), drawing shapes directly — not by an AI image model.

### Implications for icon work
- **Programmatic rendering has real advantages for icon geometry:** exact ø letter anatomy, exact diagonal angle, exact stroke weight, repeatable, editable, scalable to any size, no randomness.
- **AI image generators (FLUX, DALL-E 3, and so on.) have advantages for:** texture, lighting, material feel (glassy, metallic, gradient warmth), more "designed" look that is hard to hand-code, faster exploration of aesthetic directions.
- **For this specific use case (app icon with a specific conceptual direction), programmatic is probably more productive** for the geometry/execution problems we identified. AI could be useful later for texture/aesthetic exploration once the geometry is settled.

### If AI generation is wanted later
- Could use `browser_exec` to access a FLUX-based web interface (Black Forest Labs, Hugging Face spaces, and so on.) and capture results.
- Could use Bing Image Creator / DALL-E 3 (free tier) through browser.
- Quality and control will be less precise than hand-coded geometry for icon work.

## 9. Next Steps

### Step 1: Refine the app icon
- Pick 1–2 directions from the 5 renders (or a hybrid) to carry forward.
- Re-render with: lighter stroke weight, airflow-style flow glyph, deliberate chill glyph, intentional keel (if kept), tighter ø anatomy.
- Iterate until the execution matches the concept.

### Step 2: Generate menu bar icon
- Simplified, template-friendly version of the chosen direction.
- Effective size ~16–22px — needs to read clearly at that size.
- Monochrome/template (tintable by macOS).

### Step 3: Generate popover illustration motif
- Small mark or mark-pair built from the same ø vocabulary.
- Usable as card-header accents or a header motif in the 360×490 popover.
- Could be one mark per card (Telemetry, Fans, Power) or a single recurring motif.

### Step 4: Produce final app icon at .icns-ready sizes
- Master at 1024×1024.
- Downscale to all required macOS icon sizes.
- Optionally add `CFBundleIconFile` to `Info.plist`.

### Step 5: Decide on color
- Start with system colors (template-friendly, dark/light adaptive).
- Determine if a brand color pair is needed for the app icon and illustrations.
- Watch for each colors to prevent.

## 10. Open Questions

1. **Preferred direction among the 5?** Or a hybrid of two? Or something pointing the wrong way that needs correction first?
2. **Stroke weight** — must it be a clean cut through the bowl (closer to a real ø) or a bolder separator?
3. **Flow glyph** — sweeping curve / swirl, or something else? How abstract?
4. **Chill glyph** — downward taper, cooling ring, settling arc, or something else?
5. **Keel** — keep as a subtle anchor (dot/line), or make it more present (flared base, intentional structure)?
6. **Color** — stay within system colors throughout, or define a brand color pair for the app icon/illustrations?
7. **Background treatment** — the renders use a near-white card background. For a real app icon, would you want a solid background, a border/ring, or a background-free mark?
8. **Menu bar icon fidelity** — how closely must the menu bar icon track the app icon? Same mark simplified, or a different (but related) mark?

## 11. File Index

```
~/Desktop/kjol-icon-exploration/
- renders/
- kjol-icon-01-split-diagonal.png   (512×512)
- kjol-icon-02-aperture-rings.png   (512×512)
- kjol-icon-03-geometric-split.png  (512×512)
- kjol-icon-04-typographic-ø.png    (512×512)
- kjol-icon-05-minimal-ink-ø.png    (512×512)
- build-icons.py                         (Python/Pillow render script)
- Kjol-Icon-Design-Exploration.md       (this document)
```

*Document captures the conceptual brief, meaning exploration, ø-character discovery, five generated renders, execution feedback, and next steps as of 2026-08-26.*
