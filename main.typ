#import "@preview/touying-flow:1.2.0": *

// Setup the presentation theme
#show: flow-theme.with(
  aspect-ratio: "16-9",
  footer: self => self.info.title,
  footer-alt: self => self.info.subtitle,
  navigation: "mini-slides",
  primary: rgb("#543795"), // Deep Purple
  secondary: rgb("#a38acb"), // Lighter Purple

  config-info(
    title: [Laziness Proposal in Nix],
    subtitle: [A Hard step towards better evaluation],
    author: [def/ a.k.a. comonad],
    date: datetime.today(),
    institution: [SJTUG],
  ),
)

#title-slide()

// Automatic outline for the presentation structure
// #outline()

// ==========================================
// SECTION 1: CONTEXT
// ==========================================
= #smallcaps("Background")

== The State of Nix Expression

// Suggestion: Use columns to separate text from visual concepts or code
#slide(composer: (2fr, 1fr))[
  *libexpr*

  Lazy evaluation (call-by-need)

  Values are computed only when:
  - strictly required for output (XML, JSON, strings).
  - forced by specific built-in functions (*builtins.deepSeq*).

  #v(1em)
  *Benefits:*
  - Infinite structures.
  - Acceptable evaluation time when importing nixpkgs.
  - Efficient package composition (override / overlays).
][
  // Placeholder for a conceptual diagram
  #align(center + horizon)[
    #rect(width: 100%, height: 60%, fill: rgb("#f0f0f0"), radius: 10pt)[
      #align(center + horizon)[
        *Lazy Graph* \
        (Visual Placeholder)
      ]
    ]
  ]
]

== Laziness beyond expression ...

nix-store

// ==========================================
// SECTION 2: THE PROBLEM
// ==========================================
= #smallcaps("Problem")

== Pain points of Nix's laziness

// Suggestion: A 3-column layout for key pain points
#slide(composer: (1fr, 1fr))[
  #align(center)[
    #circle(radius: 30pt, fill: rgb("#e0e0e0"))[#align(center + horizon)[*1*]]

    *Stack Trace*
  ]
  #v(0.5em)
  Errors happen "somewhere", making debugging difficult as the stack doesn't reflect the logical cause, e.g. stacktraces for "infinite recursion" can be totally useless.
][
  #align(center)[
    #circle(radius: 30pt, fill: rgb("#e0e0e0"))[#align(center + horizon)[*3*]]

    *Performance*
  ]
  #v(0.5em)
  Multiple Nix3 CLI commands (*nix eval*, *nix flake check*) cannot benefit from eval cache; Import-From-Derivation (IFD) prevents optimization; etc.
]

#speaker-note[
  Mention specific issue numbers from the NixOS/nix repo here to ground the problem.

  - Patching flake inputs and improved flake path copying rely on lazy-trees.
    - However lazy-trees breaks evalutaion determinism (random path name for deferred drv), which fails `builtins.unsafeGetAttrPos`, flake.parts-website, etc.
    - Upstream Nix plans to introduce lazy-paths instead for gradual improvmenets. "have rope-structured strings with lazily computed fixed-length substrings to represent lazy hashing"
  - Cachable `nix eval` and `nix flake check` rely on flake-schemas.
    - Ridiculous, but yes, eval cache does not sufficiently address eval failures, adding with lazy evaluation, results in weak caching strategy.
  - Determinate Nix experiments on new features, including parallel evalutaion, cache for pre-resolve store paths (FlakeHub only),

  https://github.com/hercules-ci/flake.parts-website/issues/1760
  Virtual path semantics https://github.com/NixOS/nix/issues/10689#issuecomment-2835688644
  Lazy trees v2 https://github.com/NixOS/nix/pull/13225
  Flake schemas https://github.com/NixOS/nix/pull/8892
]

// ==========================================
// SECTION 3: CURRENT PROPOSAL
// ==========================================
= #smallcaps("Better laziness?")

== DetSys - Lazy Tree (v2)

== Lix - Flakes Feature Freeze \@ 2.94.x

Known design issues of Nix flakes:
- *flake.lock* semantics: lack of consensus
  - implementation-dependent locking & libfecthers
  - underdetermined *fetchTree* specification
- Nix flake is NOT Nix (e.g. let-binding not allowed in flake inputs)
- Strong coupling with nixpkgs
  - *nix develop* hardcodes nixpkgs-specific internals
- Issues around impurity
  - Evaluation cache gets invalidated by maybe-unrelated file system operations
- Weak composability
  - Can *flake-parts* and *flake-schemas* do better?

== CppNix - Regression Fixes

- (Nix 2.32) C API: Add lazy attribute and list item accessors #link("https://github.com/NixOS/nix/pull/14030")[\#14030]

- (Nix 2.32) Substituted flake inputs are no longer re-copied to the store #link("https://github.com/NixOS/nix/pull/14041")[\#14041]

== CppNix - Lazy Path

Virtual path semantics #link("https://github.com/NixOS/nix/issues/10689#issuecomment-2835688644")[\#10689]

// Suggestion: Grid for structured layout of text + implementation details
#grid(
  columns: (2fr, 1fr),
  gutter: 1em,
  [
    We introduce foobar.

    - *Foo:* T.
    - *Bar:* Z.
  ],
  rect(fill: luma(240), inset: 1em, radius: 5pt)[
    *RFC Draft* \
    Status: #text(fill: olive)[*Discussion*]
  ],
)

== Devenv - Better Eval Cache

#link(
  "https://devenv.sh/blog/2024/10/03/devenv-13-instant-developer-environments-with-nix-caching",
)

Tag each evaluation cache entry, with access pattern seen from *nix log*

Show no actual usage of snix (former tvix), still confusing ...

= #smallcaps("The future of flakes")

== DetSys - Flake schemas
