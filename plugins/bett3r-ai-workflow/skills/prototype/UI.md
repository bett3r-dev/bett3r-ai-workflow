# UI Prototype

Generate **several radically different UI variations** on a single route, switchable from a floating bottom bar. The user flips between variants in the browser, picks one (or steals bits from each), then throws the rest away.

If the question is about logic/state rather than what something looks like, this is the wrong branch. Use [LOGIC.md](LOGIC.md).

## When this is the right shape

- "What should this page look like?"
- "I want to see a few options for this dashboard before committing."
- "Try a different layout for the settings screen."
- Any time the user would otherwise spend a day picking between three vague mockups in their head.

## Two sub-shapes: strongly prefer sub-shape A

A UI prototype is much easier to judge when it's **butting up against the rest of the app**: real header, real sidebar, real data, real density. A throwaway route on its own is a vacuum: every variant looks fine in isolation. Default to sub-shape A whenever there's a plausible existing page to host the variants. Only reach for sub-shape B if the prototype genuinely has no nearby home.

### Sub-shape A: adjustment to an existing page (preferred)

The route already exists. Variants are rendered **on the same route**, gated by a `?variant=` URL search param. The existing data fetching, params, and auth all stay. Only the rendering swaps. This is the default; pick it unless there's a specific reason not to.

If the prototype is for something that doesn't yet have a page but *would naturally live inside one* (a new section of the dashboard, a new card on the settings screen, a new step in an existing flow), it's still sub-shape A. Mount the variants inside the host page.

### Sub-shape B: a new page (last resort)

Only use this when the thing being prototyped genuinely has no existing page to live inside (e.g. an entirely new top-level surface, or a flow that can't be embedded anywhere sensible).

Create a **throwaway route** following whatever routing convention the project already uses. Don't invent a new top-level structure. Name it so it's obviously a prototype (e.g. include the word `prototype` in the path or filename). Same `?variant=` pattern.

Before committing to sub-shape B, sanity-check: is there really no existing page this could be embedded in? An empty route hides design problems that a populated one would expose.

In both sub-shapes the floating bottom bar is identical.

## On a pv4 host

A repo with `pv4.yaml` at its root is a pv4 app, and pv4 owns its UI: framework partials and layouts, styled by framework tokens, enhanced by framework behaviours that markup switches on by attribute. Build the variants from those same parts, so the winner promotes into a real composed route unchanged. This section replaces steps 2 to 4's stack choices below; the rest of the process holds. Paths are under pv4's source, the folder `go list -m -f {{.Dir}} github.com/bett3r-dev/pv4` prints; the design behind them is its `docs/mvp/designs/ui-port.md` (§2 the rule, §4.1 the composed route).

- **Picture first.** A page's scripts-off render is its _picture_: the HTML the server sends before any script runs is the whole screen, and JavaScript adds behaviour, never content. Build each variant scripts-off, GET it and read its picture before adding any behaviour attribute. The user judges the pictures.
- **Mount.** Each variant renders in one composed route: a hand route declared under `routes:` in `pv4.yaml` (e.g. `SettingsPrototype: { method: GET, path: /prototype/settings }`), its body the stub `make gen` writes at `handroutes/<route>_serve.go`, listed in the app's `escape-hatches.yaml` with "prototype" as its reason. Gen writes the generated pages, so sub-shape A on pv4 is this route reading the page's own read model with `web.Rows[T](r, "<module>/<page>", filters)` (`web/rows.go`): the same rows, tenant and role filtering `/api` serves, so the real data and density come along.
- **Compose.** Parse the partials in `web/ui/partials/` with `ui.Funcs()` (`web/ui/funcs.go`) and one layout from `web/ui/layouts/` (`column`, `topbar`, `sidebar`, `console`, `stage`); the package comment of `web/ui/ui.go` shows the parse, and each partial's data contract is the comment above its `{{define}}`. Variants disagree by layout and by which partials carry the hierarchy. Link the styles with `web.AssetTags` (`web/assets.go`): `tokens.css`, then the theme the generated pages use, `themes/plain.css` (`web/styles/themes/`), then `pv4.css` (`web/styles/pv4.css`).
- **Behaviours by attribute.** pv4 serves its behaviours from `/pv4/v1/` (`web/behaviours/`), each file's header comment its contract and attribute vocabulary. Refresh a region with `data-poll`, `data-poll-every`, `data-poll-push[=URL]` and `data-poll-key` (`shim.js`). A live page gets its one EventSource from `web.Live(r, "<module>/<page>", filters)`, whose tag already carries the shim, so the page links the shim through that tag alone.
- **Markup and attributes only.** `make pv4lint` refuses an inline `<script>` (a JSON data block excepted), an `on*=` attribute and a `javascript:` URL, and a route's own stylesheet or a script from outside `/pv4/` is a hatch needing its reason. Where a variant wants behaviour pv4 lacks, show its scripts-off form and note the behaviour as a pv4 proposal.
- **Switcher.** The bar is a row of plain links (`?variant=A`, `?variant=B`, …) with the current one marked: it works scripts-off, shareable and reload-stable, with no keyboard cycling. A hand route with no capability serves admin only, which keeps the bar from users while the route lives on the throwaway branch.
- **Promote.** The winner's template becomes the real composed route, without the bar. Its scenario test GETs it and calls `pvtest.Picture(t, "<module>_ui_<route>", res.Body)` (`pvtest/picture.go`), which writes `pictures/<node>.html` for the board, and the pictures lint judges that it carries data.

## Process

### 1. State the question and pick N

Default to **3 variants**. More than 5 stops being radically different and starts being noise, so cap there.

Write down the plan in one line, in the prototype's location or a top-of-file comment:

> "Three variants of the settings page, switchable via `?variant=`, on the existing `/settings` route."

This works whether the user is here to push back or not.

### 2. Generate radically different variants

Draft each variant. Hold each one to:

- The page's purpose and the data it has access to.
- The project's component library / styling system (TailwindCSS, shadcn, MUI, plain CSS, whatever; on pv4, its partials and tokens, per [On a pv4 host](#on-a-pv4-host)).
- A clear exported component name, e.g. `VariantA`, `VariantB`, `VariantC`.

Variants must be **structurally different**: different layout, different information hierarchy, different primary affordance, not just different colours. Three slightly-tweaked card grids isn't a UI prototype, it's wallpaper. If two drafts come out too similar, redo one with explicit "do not use a card grid" guidance.

### 3. Wire them together

Create a single switcher component on the route:

```tsx
// pseudo-code, adapt to the project's framework
const variant = searchParams.get('variant') ?? 'A';
return (
  <>
    {variant === 'A' && <VariantA {...data} />}
    {variant === 'B' && <VariantB {...data} />}
    {variant === 'C' && <VariantC {...data} />}
    <PrototypeSwitcher variants={['A','B','C']} current={variant} />
  </>
);
```

For sub-shape A (existing page): keep all the existing data fetching above the switcher; only the rendered subtree changes per variant.

For sub-shape B (new page): the throwaway route under `/prototype/<name>` mounts the same switcher.

### 4. Build the floating switcher

A small fixed-position bar at the bottom-centre of the screen with three pieces:

- **Left arrow**: cycles to the previous variant (wraps around).
- **Variant label**: shows the current variant key and, if the variant exports a name, that name too. e.g. `B (Sidebar layout)`.
- **Right arrow**: cycles forward (wraps around).

Behaviour:

- Clicking an arrow updates the URL search param (use the framework's router, e.g. `router.replace` on Next, `navigate` on React Router, etc) so the variant is shareable and reload-stable.
- Keyboard: `←` and `→` arrow keys also cycle. Don't intercept arrow keys when an `<input>`, `<textarea>`, or `[contenteditable]` is focused.
- Visually distinct from the page (e.g. high-contrast pill, subtle shadow) so it's obviously not part of the design being evaluated.
- Hidden in production builds: gate on `process.env.NODE_ENV !== 'production'` or an equivalent check, so a stray prototype merge can't ship the bar to users. (On pv4, the plain-link bar of [On a pv4 host](#on-a-pv4-host).)

Put the switcher in a single shared component so both sub-shapes can reuse it. Locate it wherever shared UI lives in the project.

### 5. Hand it over

Surface the URL (and the `?variant=` keys). The user will flip through whenever they get to it. The interesting feedback is usually **"I want the header from B with the sidebar from C"**, which is the actual design they want.

### 6. Capture the answer and clean up

Once a variant has won, capture the answer (which variant and why), then capture the prototype the way the [SKILL](SKILL.md) describes. Fold the winner into the real code and move the rest onto the throwaway branch, not into main:

- **Sub-shape A**: fold the winner into the existing page; drop the losing variants and the switcher from main.
- **Sub-shape B**: promote the winning variant to a real route; drop the throwaway route and the switcher from main.

The full set of variants is the primary source, so it lands on the throwaway branch, not the bin, since variant components and the switcher left in the main branch rot fast and confuse the next reader.

## Anti-patterns

- **Variants that differ only in colour or copy.** That's a tweak, not a prototype. Real variants disagree about structure.
- **Sharing too much code between variants.** A shared `<Header>` is fine; a shared `<Layout>` defeats the point. Each variant should be free to throw out the layout.
- **Wiring variants to real mutations.** Read-only prototypes are fine. If a variant needs to mutate, point it at a stub: the question is "what should this look like", not "does the backend work".
- **Promoting the prototype directly to production.** The variant code was written under prototype constraints (no tests, minimal error handling). Rewrite it properly when you fold it in.
