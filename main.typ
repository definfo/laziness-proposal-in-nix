#import "@preview/touying-flow:1.2.0": *
#import "@preview/fontawesome:0.4.0": *

/// Utils
#let iconlink(
  uri,
  text: "",
  icon: "link",
  solid: false,
) = {
  // let uri = to-string(uri)
  // let icon = to-string(icon)
  if text != "" {
    [#box(fa-icon(icon, solid: solid), inset: (right: 2pt))#link(uri)[#text]]
  } else {
    link(uri)[#fa-icon(icon, solid: solid)]
  }
}

#let githublink(
  uri,
  text: "",
) = {
  iconlink(uri, text: text, icon: "github")
}

// Setup the presentation theme
#show: flow-theme.with(
  aspect-ratio: "16-9",
  footer: self => self.info.title,
  footer-alt: self => self.info.subtitle,
  navigation: "footer",
  primary: rgb("#5277C3"),
  secondary: rgb("#7EBAE4"),

  config-info(
    title: [Laziness in Nix],
    // subtitle: [],
    author: [def/ a.k.a. comonad],
    date: datetime.today(),
    institution: [SJTUG],
  ),
)

#title-slide()

= #smallcaps("Background")

== What is Laziness?

(https://notashelf.dev/posts/not-for-the-lazy#laziness-in-haskell)

=== Laziness in Haskell

```haskell
lazyNumbers :: [Int]
lazyNumbers = [1..]

firstFiveNumbers :: [Int]
firstFiveNumbers = take 5 lazyNumbers
```

`lazyNumbers` is an infinite list. However, the values are not computed all at once.

`take 5 lazyNumbers` only computes the first 5 elements of the list when required.

== Laziness in Nix: Conditionals

```nix
let
  expensive = builtins.trace "This should not print!" (throw "Error");
  value =
    if false
    then expensive
    else "Safe";
in
  value
```

In Nix, the `false` branch is never evaluated, so the program executes safely.

== Laziness in Nix: Functions

```nix
let
  alwaysReturnsOne = x: 1;
in
  alwaysReturnsOne (throw "This should never be evaluated")
```

Function arguments are not evaluated unless explicitly used.

== Laziness in Nix: Lazy Lists

```nix
let
  lazyList = {
    head = 1;
    tail = lazyList.tail;
  };
in
  lazyList.head
```

= #smallcaps("The Reality of Nix")

== The State of Nix Expression - *libexpr*

#slide(composer: (2fr, 1fr))[
  Lazy evaluation (call-by-need)

  Values are computed only when:
  - strictly required for output (XML, JSON, strings).
  - forced by specific built-in functions (*builtins.deepSeq*).

  #v(1em)
  *Benefits:*
  - Enable heavy imports (e.g. nixpkgs).
  - Enable efficient package composition (override / overlay).
  - ...
]

== Pain points of Nix's laziness

*Stack Trace*
- Unreadable error messages out of stack trace, e.g. "error: infinite recursion detected" can be filled with internal implementation details.
- Lengthy Nix path info *≪github:NixOS:nixpkgs/very-long-hash/foo/bar.nix≫*

*Performance*
- Overhead with network/filesystem, e.g. bad fallback strategy with multiple substituters.
- Evaluation of huge thunks prevents static analysis.
- Import-From-Derivation (IFD) causes potential degrade on parallelism.

*Interaction with Real-world Workload*
- impure eval: stateful, unpredictable
- flakes: flake evaluation is ANOTHER evaluation semantics.
- ...

== Deep Dive: Why `nix eval` is slow?

Based on `src/libexpr/eval-cache.cc`:

- *Cache Schema*: Stores keys (`FullAttrs`) and basic values (int, bool, string).
  - Recursive attribute sets are NOT cached in most cases.
- Outcome:
  - `nix eval` needs to fully traverse the value of an attrSet, where uncached `nAttrs` will force re-evaluation of the entire structure.

For NixOS configuration, each rebuild waits for
\
`nix eval path_to_flake#nixosConfigurations.config.system.build.toplevel`
\
which is very time-consuming, even for a minor change.

== Laziness & Performance beyond *libexpr* ...

(NOTE: the following statements are not directly referring to sub-directories in Nix source.)

Is *libstore* (nix-store) lazy?
- Not really, esp. with flakes
- Known issues:
  - #githublink(
      "https://github.com/NixOS/nix/issues/5551",
      text: " #5551 flakes: avoid copying local flake to the store when self arg is omitted",
    )
  - #githublink(
      "https://github.com/NixOS/nix/issues/3121",
      text: " #3121 Copy local flakes to the store lazily",
    )
- Nix currently has merely no reliable method to trace copy-tree dependency.

Is *libflake* (flakes) lazy?
- No. Evaluation requires the "Lock -> Fetch -> Eval" pipeline.
  - *Locking* (`lockFlake`) requires fetching the flake source to read/update `flake.lock`.
  - Inputs are fetched/copied *before* evaluation even begins.
- `builtins.fetchTree` should be, but is not lazy right now

= #smallcaps("Proposals")

== DeterminateSystem - Lazy Tree (v2)

PR
#githublink("https://github.com/NixOS/nix/pull/13225", text: " (Nix)#13225")
|
#githublink(
  "https://github.com/DeterminateSystems/nix-src/pull/27",
  text: " (Determinate Nix)#27",
)

- Pre: flake evaluation triggers copying all flake inputs into Nix store.
  - `outputs = { self, ... }: foobar` results in copying a shallow clone of current Git repository into Nix store.
  - Heavy overhead in monorepo / on edge devices with limited I/O performance.

- Post: put *lazily* "copied" flake inputs into Nix store.
  - Actual behaviour: flake inputs are "mounted" as virtual filesystems on top of Nix store as *RANDOM* "virtual" store paths.

- Outcome:
  - #sym.plus Possibly reduce unnecessary copying
  - #sym.plus Allow patching flake inputs.
  - #emoji.warning\Breakage: undeterminism caused by random store path for a lazily copied tree. Currently this fails `builtins.unsafeGetAttrPos`, flake.parts-website, etc.

== DeterminateSystem - Parallel Evaluation

PR
#githublink(
  "https://github.com/DeterminateSystems/nix-src/pull/125",
  text: " #125 Multithreaded evaluator",
)

- Pre: single-threaded evaluation

- Post: thread-pool evaluation; parallelized flake checks, flake show, search, and JSON/XML rendering

- Outcome:
  - #sym.quest Possibly reduce evaluation time, along with overhead of async lock.

However this may not be quite useful in the following cases:

- Use with unsupported commands (due to lock/sync issues).
- Face network bottleneck (esp. for China mainland users).
  \
  (Check `nix flake prefetch-inputs`.)
- ...


== CppNix - Regression Fixes & Steady Improvements

- #githublink(
    "https://github.com/NixOS/nix/pull/14030",
    text: " (Nix 2.32) C API: Add lazy attribute and list item accessors",
  )

- #githublink(
    "https://github.com/NixOS/nix/pull/14041",
    text: " (Nix 2.32) Substituted flake inputs are no longer re-copied to the store",
  )

== CppNix - Lazy Path Semantics

#githublink(
  "https://github.com/NixOS/nix/issues/10689#issuecomment-2835688644",
  text: " Issue#10689 Virtual Path Semantics? Lazy Path Values?",
)

#githublink(
  "https://github.com/NixOS/nix/issues/11161",
  text: " Issue#11161 Tracking Issue for lazy, async instantiation and fetching",
)
\
#emoji.arrow.t Almost dead :(

== Devenv - Better Eval Cache Strategy

#link(
  "https://devenv.sh/blog/2024/10/03/devenv-13-instant-developer-environments-with-nix-caching",
)

Tag each evaluation cache entry, with access pattern seen from `nix log`.

No actual usage of Snix (former Tvix), flake evaluation  fully relies on the underlying Nix.

= #smallcaps("The Future")

== DeterminateSystem - Flake schemas

PR:
#githublink("https://github.com/NixOS/nix/pull/8892", text: " (Nix)#8892")
|
#githublink(
  "https://github.com/NixOS/nix/pull/8892",
  text: " (Determinate Nix)#8892",
)

- Pre: Nix flakes only accept certain top-level outputs.

- Post: Users can define a specific schema to manipulate flake outputs.

- Outcome:
  - #sym.plus `nix flake check` can recognize custom attributes
  - #sym.plus `nix eval` and `nix flake check` can benefit from eval cache.
    \
    (Related to "Record failure in flake evaluation".)

== Lix - Flakes Feature Freeze \@ 2.94.x

Lix Project listed several known design issues of Nix flakes:
- *flake.lock* semantics: lack of consensus
  - implementation-dependent locking & libfecthers
  - underdetermined *builtins.fetchTree* specification
- Nix flake is NOT Nix (e.g. let-binding not allowed in flake inputs)
- Strong coupling with nixpkgs
  - *nix develop* hardcodes nixpkgs-specific internals
- Issues around impurity
  - Evaluation cache gets invalidated by maybe-unrelated file system operations
- Weak composability
  - Think: Can *flake-parts* and *flake-schemas* solve this?


== Read More

#link(
  "https://samuel.dionne-riel.com/blog/2023/09/06/flakes-is-an-experiment-that-did-too-much-at-once.html",
)[- Flakes is an experiment that did too much at once - Samuel Dionne Riel]
