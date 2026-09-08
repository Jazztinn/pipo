## Design Review Rules

When reviewing UI/UX designs, follow the design review process defined in:

- `.design-rules/SKILL.md` - Main review methodology
- `.design-rules/references/hig-lookup.md` - Topic-to-file mapping
- `.design-rules/references/hig/` - Design guideline documents

Load only the relevant guideline files before providing design feedback or changing UI.

## Pipo Website

- Use `/caveman` for website work. Keep decisions practical and concise.
- Treat `PIPO_WEBSITE_PLAN.md` as the primary brief. Preserve the native SwiftUI/Rust app unless the user explicitly requests native changes.
- Website code lives in `website/`: Vite, vanilla ES modules, CSS, GSAP, and ScrollTrigger. Avoid adding a framework or dependency without a concrete need.
- Design direction: Clucky controls content density, Keeby controls horizontal behavior, and Pipo controls identity. Use the supplied references for structure and proportion without importing their branding or metaphors.
- Focus on desktop. Do not add or redesign mobile behavior until requested.
- Keep the site sparse: one canvas color, no dividers, no numbered section labels, no generic SaaS filler, and no unsupported privacy or security copy.
- Do not recreate the evolving Pipo product UI. Reserve replaceable white demo containers with a black outline for future product graphics.
- Use a 12-column page grid. Feature summaries use an asymmetric mosaic with clear hierarchy instead of an equal card wall.
- Brand styling: lowercase `pipo` in Itim; Sunghyun Sans for interface and marketing copy; restrained maroon and gold accents.
- Header stays minimal: Pipo brand left, browser-local visit count centered, Apple Download button right. Do not show “For LPU Cavite.”
- Download buttons use an Apple mark, a slight top-lit gradient, a clearer stationary hover state, and a brief recessed press state.
- Desktop scrolling is one GSAP-pinned horizontal track. Vertical input maps down to right and up to left; horizontal gestures also work. Hide the scrollbar, prevent edge bounce, and preserve keyboard navigation.
- Keep product artwork and demo markup replaceable without changing page panels, the grid, or scrolling logic.
- Before handoff, run `npm run build` from `website/`, run available tests, run `git diff --check`, and browser-check the changed desktop surface. State any Safari or device limitation plainly.
- Production is hosted on Vercel at `https://pipo.jazztinn.me`. Deploy only when requested or when deployment is an explicit part of the active workflow.
