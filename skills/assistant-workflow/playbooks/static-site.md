# Static Site / Landing Page

**Architecture:** Component-based, minimal structure

## Folder structure
```
src/
  index.html
  css/
    variables.css          # Design tokens
    styles.css
  js/
    main.js
  assets/
    images/
    fonts/
```

## Typical Discovery Q&A
```
1. Build tooling?
   a) Plain HTML/CSS/JS (simplest)
   b) Vite (modules, HMR)
   c) Astro / 11ty (static site generator)
2. Sections needed? (list all)
3. Responsive approach?
   a) Mobile-first: 375 → 768 → 1280 (recommended)
   b) Desktop-first: 1440 → 768 → 375
4. Animations?
   a) Minimal (fade-in, transitions)
   b) Rich (scroll-triggered, parallax)
   c) None
5. Hosting?
   a) GitHub Pages  b) Netlify / Vercel  c) Self-hosted
```

## Architecture rules (Plan phase)
- CSS variables for all design tokens
- No inline styles — all styling in CSS files
- Semantic HTML (header, main, nav, section, footer)
- Images optimized (WebP preferred, lazy loading)
- Minimal JS — CSS-only solutions preferred for animations
- No heavy frameworks unless justified

## Design rules (Design phase)
Phase 3 (Design) is **mandatory** for this project type.
- Define complete design direction before any code
- Color palette with CSS variables
- Font pairing (display + body) with CDN links
- Spacing scale (4px or 8px base)
- Create full-page HTML mockup for review
- Get approval before splitting into production files
- List ALL assets: icons, images, fonts, illustrations
- Interactive states on all clickable elements
- Responsive at 375px, 768px, 1280px

## Build/test
```
# Plain HTML — open in browser
# Vite
npm run build
npm run preview

# Lighthouse audit for performance, accessibility, SEO
```
