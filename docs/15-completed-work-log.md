# 15 — Completed-work log

Done work moves HERE out of STATUS.md the moment it completes (CONTEXT.md
hard rule 5: STATUS holds only todo/in-progress). Newest entries go at the
TOP of the 'Log' section; the bottom of this file is the verbatim archive of
STATUS.md as it stood on 2026-07-13 when the rule was introduced (nothing
was deleted — full narratives, checklists and history live in that archive
and in git history / docs/14).

## Log

- **2026-07-14 (night) — T3.1 CLOSED: the export contract is live and
  CI-gated. Training runs are unblocked.** `docs/16-export-contract.md` +
  `scripts/export_dataset.exs`. Decisions made and written down: (1) the
  **family** — the leakage unit is the base idea `a` (the 3-digit prefix),
  because every derived shape embeds its parent's text; 5,881 exportable
  dirs collapse to **83 families**, and a family is ATOMIC across splits;
  (2) the **split** — deterministic `sha256("split-v1:" <> family) mod 20`,
  no RNG and no seed file, so it can never reshuffle; ~5% → **4 whole
  held-out families** (032, 065, 073, 108 = 282 examples), a genuine
  held-out-IDEA eval rather than a memorisation score; (3) **FIM exports as
  chat**, not raw infill control tokens (the prompts already state the task
  in words — one uniform format, comparable val across shapes, no tokenizer
  lock-in; raw FIM stays re-derivable); (4) the **gold-per-shape mapping**,
  whose one trap is `write_test`: its gold is `test_harness.exs`, NOT
  `solution.ex` (that is the INPUT module embedded in the prompt — exporting
  it would train "write tests for X" → X). The round-trip validator enforces
  all of it and is proven non-vacuous: `--selfcheck` plants 5 violations
  (straddling family, the write_test gold trap, frozen `repair_` evidence,
  a silently dropped row, an emptied gold) and catches all 5. `repair_` dirs
  (17) are excluded by contract. Weights are advisory metadata (test_fim
  0.25 / fim + bugfix 0.5 / base shapes 1.0) so the first training run
  changes them on purpose, not by accident. CI runs selfcheck + check on
  every push.

- **2026-07-14 (night) — T2.2-T CLOSED IN FULL: all 89 confirmed findings
  from the 60-root review resolved, same day they were measured.** Final
  ledger: 46 gap families closed by `close_gaps.exs` (43 tool-applied over
  three passes incl. retries; 3 hand-applied after repeated solver-defect
  blind REDs: 110_001, 020_004, and 104_002 — whose candidate repeated a
  dead-waiter test-design flaw and got its three waiter spawns hand-parked
  in receives so stats observe a LIVE holder, 9/9 after), plus 100_004 and
  110_004 closed by hand earlier. ~120 tests added corpus-wide; NO family's
  kill rate dropped; standouts 037_003 0.67→1.00, 035_002 0.63→0.92,
  011_002 0.79→0.96, 107_001 0.53→0.76. All 12 gold defects and all 3
  prompt defects fixed — the last being the formerly PARKED 032_001: the
  invalid `conflict_target: :nothing` default replaced by a coherent
  contract (default stays `:replace_all`; empty target is omitted from
  insert_all; records-present + replace_all + no target →
  `{:error, :conflict_target_required}` up front, file/JSON errors first,
  empty array still zeroed-ok), gold 10/10 incl. two new conflict-option
  tests, first design draft REVERSED by the harness's own evidence (4
  existing tests rely on the replace_all default — the intent is
  upsert-by-default). En route: 110_004's fresh blind RED exposed a real
  prompt under-specification (total_weight's emptiness rule) — clarified,
  re-screened GREEN. Chronic-keep triage rows appended for 020_004 (4th
  solver failure), 110_001 (3rd), 032_001 (2nd, six days apart, same
  documented timestamp-classification rule). Freshness 332/332 with 75
  roots now proven via tool-ledger blind evidence.

- **2026-07-14 — T2.2-T HIGHS PHASE CLOSED 13/13** (same day the batch
  measured them). Two gold defects hand-fixed with full cascades (095_003
  negative-split money bug — floored division, prompt precision, bugfix
  children delete+reminted; 031_002 whole-number floats accepted per the
  spec its gold argued against). One prompt contradiction hand-fixed
  (040_001 tuples-vs-lists + the lying lock comment; fim gold re-carved;
  blind GREEN). Ten gap families closed by the new findings-seeded
  `close_gaps.exs` (strengthen mold; gold/prompt findings ride as
  context-only): 021_002 q-semantics (+5 tests, 0.89→0.94 — attempt 1's
  blind RED was the solver ignoring documented q ordering, the exact gap
  under repair), 015_001 real-timer scheduling via reporting check fns,
  105_003 max-wait discrimination via refute_receive pacing (no sleeps
  added anywhere), 043_001 cross-process + racing-submit atomicity
  (+0.07), 079_002 saturation trio (+0.07), 034_003 duplicate-key +
  nil-key corners (7 tests), 031_001 true multi-error field, 092_004 rank
  :mean override + :min_votes threading, 011_002 discriminating
  starvation-promotion ordering + documented defaults, and 100_004
  hand-applied after two more blind-compile solver defects — its FIFTH
  code-quality failure, SAME signature as the morning (`&&&` with no
  import Bitwise ×2), triage row appended; 36/40 ceiling held with the
  :window/:name gaps closed. Freshness gate now reads close_gaps.jsonl as
  S6 evidence (the F9 ledger lesson applied same-day); 332/332 fresh.
  Every added test traced to a verbatim prompt promise; kill rates held or
  rose in all 13 families.

- **2026-07-14 — T2.2 MEASUREMENT DONE: the stratified 60-root semantic
  review batch ran to completion (89 confirmed findings; 88% of roots carry
  at least one).** Tool: `scripts/semantic_review.exs` — one full-context
  review call per root (rubric = the 07-12 pilot's classes, anti-noise
  instruction) + one independent adversarial-verify call per finding; 11 of
  100 raw findings refuted as noise, 0 errors. Rule-9 pilot first: the
  positive control (pre-fix 018_003 reconstructed from git) re-found the
  planted dead-code defect verbatim AND surfaced live F10; 3-root noise
  calibration produced 7 findings, all hand-verified real. Batch breakdown:
  **74 harness_gap / 12 gold_defect / 3 prompt_defect; 13 high-severity.**
  Hand-checked 10/10 real so far, incl. both HIGH golds: **095_003** — the
  money module's `split/2` uses div/rem, so for the negative amounts the
  prompt explicitly allows, shares sum to the WRONG total (-5 split 2 →
  -4); **031_002** — the gold computes the whole-number-float distinction
  then rejects BOTH branches identically, its comment arguing against the
  prompt's own rule ("`:integer` must be a JSON number that is a whole
  number"), harness silent = three-way incoherence. Dominant corpus
  disease: PROMISE-COVERAGE debt — documented defaults never exercised
  (:name/:timeout/:size options, auto-tick paths, promised agg modes,
  promised edge directions), tests whose names claim more than their
  bodies test. Even 100_004 (hand-strengthened this same morning) took a
  justified high: no test ever passes an explicit `:window`.
  Extrapolation: ~1.5 confirmed findings/root → ~490 corpus-wide, ~66 gold
  defects. Cost: ~60 review + ~100 verify calls, well under the 3.5M
  estimate. The triage program + the full-pass decision are registered in
  STATUS (measurement half of T2.2 ends here).

- **2026-07-14 — T2.1 CLOSED 24/24: the S9 reach-in debt is purged from the
  corpus.** Zero `:sys.get_state`/`:sys.replace_state` remains in any
  harness, gold, or embed outside frozen `repair_` evidence (24 root
  harnesses / 11 base ideas / 24 wt_ copies / 7 tfim golds that had been
  TRAINING TARGETS for the cheat). Every family's semantic kill rate held
  EXACTLY — not one dropped across the whole purge — because the rewrites
  replace each reach-in with the observable consequence it was standing in
  for: refill starvation distinguishing swept-vs-retained (003_001), fresh
  burst budgets (003_002), re-query under a different capacity (003_004),
  clock REWIND to a live moment (006_001 — a retained entry would read as a
  hit again), a window wider than the retention horizon (101_001),
  monitor + refute DOWN liveness (107_003), stats/1 counts that TIGHTEN the
  old check (006_003/006_004), and sync-barrier reads ordered behind
  :cleanup/:tick everywhere. Mechanics: `scripts/rewrite_reachins.exs`
  (design docs/13 §1.7) — pilot 004_001 (rule 9, line-by-line) → fleet pass
  1 (14 applied, 5 golds re-carved in place) → pass 2 (6 applied) → 3
  chronically solver-hard stragglers hand-applied per the T2.7 recipe after
  each failed the blind gate twice on hand-verified verbatim-documented
  behavior. Tool lessons landed en route: candidates archived for triage
  (rule-9 pilot finding); the min-test-count lint EXEMPTED for this tool
  (grandfathered count debt vs the name-set-unchanged rule made 4 families
  structurally unpassable — debt ledgered as `count_shortfall`, strengthen/
  T1.4 scope); `check_screen_freshness` accepts rewrite-ledger success rows
  as S6 evidence (same blind gate as strengthen). Blind evidence: 21
  applied via the tool's own blind gate, 005_003 re-screened GREEN
  (3rd-solver success), 007_001 + 007_002 REDs hand-triaged entailed with
  multi-source histories (007_001: FOURTH failure on the same documented
  cold-start mean, incl. the 07-08 judge row; 007_002: third failure on the
  documented max_period retention bound — the candidate returned the
  untrimmed 55/15). One hand improvement: 005_003's survives-cleanup test
  sets its size override BEFORE the sweep, pinning override survival
  (isolation :killed). Latent Phase-3 note: catalog idea `tasks.md:3511` is
  a `:sys`-API task that today's S9 hard accept lint would reject — needs
  an exemption or a skip when Phase 3 reaches it. Also recorded: 007_001's
  prompt pins the internal state layout verbatim (`state.streams["name"]
  .values`) — prompt-design debt for the Phase-3 template review.

- **2026-07-14 — T2.7 fully closed: the 100_004 residue hand-strengthened
  0.42 → 0.90 (36/40), at its honest internals ceiling.** The existing
  harness used `current_code` as its own oracle, which NO code-generation
  mutant can fail; the prompt documents the entire RFC 6238 pipeline
  verbatim, so the fix was an INDEPENDENT reference computation inside the
  harness (RFC 4648 decode + HMAC-SHA1 + RFC 4226 truncation, deliberately
  written with Bitwise masks where the gold uses rem-moduli) swept over 300
  steps, plus a secret-shape test (160 bits = 32 unpadded base32 chars) and
  a window-default=1 probe (base±2 rejected, collision-guarded). Killed all
  19 killable survivors; the 4 remaining are decode_char GUARD-WIDENINGS
  (65→64, 90→91, 50→49, 55→56 — accepting `@`/`[`/`1`/`8` that no code path
  can ever feed it, since the vault only decodes its own valid secrets) =
  internals, the 003_004 redundant-clamp category, all four predicted before
  writing a line. War story: the first draft of the reference shipped
  unpinned `size(...)` bitstring variables — the EXACT defect class that
  killed this family's blind solvers — and the perfect gate caught it
  (2 warnings → hard fail). Blind property: fresh re-screen RED on a
  candidate COMPILE failure (`&&&/2` without `import Bitwise` ×2 + three
  unpinned `size(...)` matches; zero tests ran) — hand-triaged entailed,
  3rd/3rd solver-quality death; candidate archived in
  logs/screen_candidates/, triage row cites it. TOTP forces bitwise +
  bitstring size-matches (the sharpest Elixir edges for solvers) — the
  family is a hard-task keep, not a spec defect. Cascade: 10 tfim embeds +
  wt_ byte-copy resynced, wt_ twin re-measured at the same 36/40, perfect +
  raise-mutants + embeds + format + temp-path all green, registry +0 (tfim/
  bugfix pools at cap), freshness 332/332. T2.7 final tally (6 of 6):
  097_004 0.97, 101_003 1.00, 003_004 0.925, 013_003 0.69-with-ceiling,
  037_001 at spec-ceiling, 100_004 0.90-with-ceiling.

- **2026-07-14 — F9 closed (both tiers, same morning it was noticed): the
  freshness gate lied in shallow clones — CI red since the gate landed.**
  Finding (Kamil's catch): CI reported 261 STALE roots, every one "predating
  the harness commit 2026-07-14T07:22:08" — the SAME second, which is the
  tip-commit time. `actions/checkout@v4` defaults to `fetch-depth: 1`; in a
  shallow clone `git log -1 -- <file>` reports every file as last committed
  at the tip, so all 248 legacy rows (no `harness_sha` — judged by git dates)
  read stale. The other 13 "stale" were a SECOND independent gap: the
  `fresh_via_strengthen` path reads `logs/strengthen_harnesses.jsonl`, which
  was never git-tracked — absent in CI, those roots fell through to the
  git-date fallback and their harnesses are BY DEFINITION newer than their
  screen rows. CI had been red since the gate was wired in (97aa33f5, 07-13
  evening, 18 pushes) — unnoticed but SAFE: shallow clones make files look
  newer, so the bug only ever produced false REDs, never false GREENs; no
  data was mis-certified, no ledger row written. Task A (unbreak CI):
  `fetch-depth: 0` on checkout + the strengthen ledger force-tracked (28 KB,
  73 rows — same rationale as the reject ledgers on 07-13: gate evidence
  must survive a fresh clone; future strengthen runs commit their appends).
  Task B (can never lie again): the gate now refuses to run in a shallow
  clone — `git rev-parse --is-shallow-repository` → explicit environmental
  error, exit 2, remediation in the message (the F7 rule: environmental
  conditions must never become verdicts). Proven non-vacuously on both
  sides: a real `--depth 1` clone → guard fires, exit 2; full clone →
  self-test OK, 332/332 fresh (71 sha + 248 legacy + 13 strengthen), exit 0.

- **2026-07-14 — T2.5 done: randomized-ExUnit-seed full perfect sweep
  (`EVAL_SEED=20260714`, no build needed — the override existed for stability
  confirmations).** Result: NO order-dependence bugs (12 flake suspects all
  recovered serially); 017_001 environmental as always; and one REAL catch —
  `tfim_100_002_02` shipped a 113-column gold line, minted 07-12 18:21 in
  the minutes BETWEEN the last pre-gate batch and the ≤98-fragment mint gate
  landing (18:45), invisible since because only scoped sweeps ran. Gold
  rewrapped, unit perfect, class confirmed contained to this one unit by the
  same full sweep (Tier B — the mint gate — has existed since 07-12).

- **2026-07-14 (overnight) — T2.7 resolved (5 of 6; residue = 100_004 in the
  register).** Hand-strengthened through documented observation channels,
  zero timing, zero reach-ins: **101_003 0.46 → 1.00** (26/26; +5 tests +
  the 24 h cleanup horizon documented — it was unpinnable as "a reasonable
  maximum window"), **003_004 0.45 → 0.925** (37/40; +8 tests + validation/
  round-UP paragraph; 3 survivors are verified redundant-clamp internals;
  the rate-1.0-masks-arithmetic and t=0-masks-elapsed-origin probe lessons
  recorded in the commit), **013_003 0.48 → 0.69** (20/29; ceiling =
  default-random ±1 octet + polling granularity; the first measurement read
  29/29 because a broken added test failed the reference — the perfect gate
  caught it, docs/12 §5.1.9 vindicated again), **097_004 0.40 → 0.97**
  (strengthen tool, pass 1). **037_001 recorded AT ITS SPEC-CEILING (~0.42)**
  — all 21 survivors shift WHICH fake value the {:fake, seed} generator
  emits, while the prompt deliberately specifies only determinism +
  referential integrity: observable but UNPINNABLE-BY-SPEC (a third survivor
  category besides internals and killable — S8 note added to docs/13).
  Blind properties: 003_004 GREEN; 101_003 + 013_003 fresh REDs
  hand-triaged entailed (3rd/3rd independent solver slips on documented
  behavior — both rows cite the prompt lines). T2.3 (chain3): the 14
  entailed keeps second-sourced — 4 flipped to PASS; population now
  63 PASS / 10 entailed / 1 hand-triaged.

- **2026-07-14 — T2.7 passes 1–2 (partial): 097_004 0.40→0.97 (+8 tests,
  cascaded, perfect).** Retry outcomes drove three tool improvements landed
  en route: the strengthen prompt now states the chatter rule its own lint
  enforces (037_001 was rejected by the day-old F5 lint IN PRODUCTION — a
  '# Prompt:' citation comment); the blind-gate added-test rejection message
  no longer asserts "undocumented" (101_003's failing default is documented
  verbatim — solver error is the other hypothesis and must be checked first);
  and per-family diagnoses for the 5 remaining families are recorded in the
  register (hand-strengthening named as the next step — the 013_001/101_001
  pattern).

- **2026-07-13 — T1.5 closed: semantic-mutant operator set extended.**
  New operators (AST + textual twins in step): min↔max, +↔-, *→+, div↔rem;
  ranges covered by the existing ±1 (endpoints are literal children); clause
  reordering deferred (multi-line sites cannot be applied textually — the
  bugfix twin must stay in step). Rule-9 pilot reviewed line by line
  (101_001: every mutant a plausible one-token bug; applier hits only binary
  minus). Measurement rows now gate-sha-stamped ([Mutation, Evaluator]) so
  rates from different operator sets never compare silently; strengthen
  treats gate-mismatched rows as STALE-UNKNOWN. Full corpus re-measure under
  the new set: 679 tasks, 16,632 mutants, 76.2% killed, mean 0.778. Yield:
  6 new real-gap families (T2.7); at-ceiling verdicts re-confirmed (077_001
  fuzz 18/18 IDENTICAL including the 3 new survivors); bugfix pool grows but
  0 pending (3-per-seed cap already met — relevant at cap lift, docs/13 §2.5).
  F8 fixed en route: repair_ dirs (frozen evidence) leaked into the semantic
  sweep + its consumers, polluting the work list — excluded in validate,
  classify_survivors and strengthen_harnesses (both tiers = the same
  measurement-tool change). 308 tests green.

- **2026-07-13 — T3.2 + T3.3 closed: the scrutiny tools are standing.**
  T3.2: weekly CI now spot-checks BOTH sides (CONTEXT rule 8) — the
  six-property bugfix audit on a random 15-sample (accepted side; properties
  the perfect sweep cannot see) and a full reject-ledger reverify (rejected
  side; fresh checkout = nothing skipped). Both scripts got real gate exit
  codes; reverify fails only on LIVE unsound rows (purged historical finds
  stay as records). The three reject ledgers are now git-tracked (a fresh
  clone previously lost the negative cache AND made CI reverify vacuous).
  `spot_verify.sh` stays a local/manual tool — its perfect/mutant batches
  duplicate the weekly full sweeps. T3.3: (a) `scripts/fuzz_survivors.exs` —
  the at-ceiling verification layer (docs/14 rule 11) as a standing tool with
  an honest per-family driver registry (077_001 driver included, reproduces
  15/15 IDENTICAL; a driverless family exits 1 with instructions, never a
  vacuous pass); (b) environmental-failure unwrapping landed with F7.
- **2026-07-13 — F3 / T1.7 closed (both tiers): gate-sha-keyed reject ledgers.**
  Finding: verdicts written by a broken gate survived the gate's repair (the
  074_x class recurred as 15 unsound 102_001 tfim rows blocking 7 mintable
  units for two days). Task A: rows purged + 9 units minted (earlier today).
  Task B: `CycleLog.gate_sha/1` (md5s of the verdict-chain modules collapsed
  to one sha) stamped into every new tfim/fim/bugfix reject row; all three
  readers treat a row from a different gate version as RE-OPENABLE, while
  unstamped legacy rows stay valid (they were all re-audited today; the T3.2
  weekly reverify sample is the backstop). 4 new tests, 304 green; registry
  counts unchanged (no phantom re-openings).
- **2026-07-13 — F5 / T1.8 closed (both tiers): generation-process chatter.**
  Task B first (gate-first per docs/12 §7.3): `Evaluator.process_chatter/1` —
  comment-line-only scan for unambiguous process markers (`Prompt:` citations,
  `--- added` banners, `# FIX:`/`# Fixed:`, "the evaluator", chatter emoji;
  deliberately NOT bare "Wait," — 002_001 has a legitimate `# Wait, probe,
  fail` sequence comment) — wired as a HARD shortfall in `quality_shortfall`,
  4 new tests (300 total), calibrated corpus-wide: exactly 2 true hits, zero
  false positives across every solution/harness. Task A: the 097_002 banner
  (parent + wt_ byte-copy + 10 tfim embeds) reworded to behavioral style,
  family re-gated perfect, freshness re-proven (blind re-screen GREEN).
  Earlier same day: the `# Prompt:` class (063_004, 11 files) — Kamil's
  spot-catch.
- **2026-07-13 — F2 / T1.2 closed (both tiers): the S6 freshness gate.**
  Finding: blind-screen evidence was keyed by prompt sha only, so harness
  edits silently invalidated it — first spotted on 013_001, then measured at
  scale: 47 roots (mostly the 07-09 R10-tightened harnesses) carried verdicts
  for older harnesses, plus 7 S6 coverage holes. Task A: 54-root re-screen
  sweep → 42 GREEN / 12 RED; triage of the 12: 10 entailed solver slips
  (6 judge + 5 rule-10 hand verdicts, incl. refuting a pre-R10 judge proposal
  to document an internal `subs` field), 1 environmental (=F7), and **1 real
  gap — 014_004** (harness asserts ArgumentError on non-positive
  max_concurrency; prompt only said "must be a positive integer") — prompt
  fixed, cascaded, re-screened GREEN. Task B: `screen_blind_solve` stamps
  `harness_sha` into every row; `scripts/check_screen_freshness.exs` gates in
  CI + pre-push (self-tested); final state `stale=0, unscreened=0` over 332
  roots. Also fixed: `repair_` dirs (frozen evidence) leaked into the
  screenable population of both tools.
- **2026-07-13 — F7 closed (both tiers):** finding "environmental failures
  written as screen VERDICTS" (017_001's sweep row recorded 'Postgres not
  reachable' as a RED). Task A: human triage row marks it environmental —
  never a prompt-gap. Task B: `screen_blind_solve.exs` now classifies
  environment-unreachable grades as `green: nil` / `error: environmental`
  (like transport errors), so no future run can ledger an environmental RED.
- **2026-07-13 — F4 closed (both tiers):** finding "our tools imitate
  grandfathered anti-patterns" (the strengthener copied `:sys.get_state` from
  101_001's April-era tests three times). Task A: 101_001 hand-strengthened
  0.47→0.76 through documented behavior only. Task B: S9 bans named + a
  do-not-imitate warning added to the strengthen prompt and the variations
  template (base template already had them). Commits `10410bd6`, `eb44ff58`.
  The wider debt cleanup (52 reach-in harnesses) remains open as T2.1.
- **2026-07-13 — F6 closed (both tiers):** finding "an LLM-judge triage
  verdict was wrong" (101_003: the judge proposed an exclusive window boundary
  contradicted by the prompt's own line 31 and the gold). Task A: verdict
  overridden by an appended human triage row; the REAL gap (undocumented
  `keys/1`) found by grading the failed candidate, then fixed + re-screened.
  Task B: docs/14 rule 10 (judge verdicts are hypotheses — hand-verify against
  prompt + gold + candidate before acting); mechanical two-judge agreement
  remains open as T2.4. Commits `10410bd6`, `331b92c2`.
- **2026-07-13 — T1.3 closed:** S9 bans stated inside the tools' own prompts
  (see F4 Task B). Commit `eb44ff58`.

---

## ARCHIVE — STATUS.md as of 2026-07-13 ~19:00 (verbatim)

# PROJECT STATUS — read this first

This file is the single place that says what the project is doing **right now**.
It answers one question: are we **producing new data**, or are we **catching up**
on a quality improvement? Update it whenever the answer changes; everything else
(docs, scripts, plans) is secondary to this file.

---

## ▶️ RUNNING RIGHT NOW

| what | pid | log | expected result |
|---|---|---|---|
| T1.2 freshness re-screen sweep: `screen_blind_solve --only <54 roots> --rescreen` (launched 2026-07-13 ~18:5x) | **2345136** | `logs/rescreen_freshness_20260713.log` | 54 sha-stamped rows appended to `logs/screen_blind.jsonl` (47 roots whose blind verdicts predate their current harness — mostly the 07-09 R10 harness campaign — plus 7 S6 coverage holes incl. 018_003, hand-fixed 07-12 and never re-screened). Any RED → triage queue (potential new 101_002-class finds). When done: `mix run scripts/check_screen_freshness.exs` must print `stale=0` → then wire it into CI + pre-push (the LAST step of T1.2). Idempotent relaunch: same command — the ledger skips finished rows only with `--rescreen` removed, so on relaunch DROP `--rescreen` (screened-current rows are then cached). |

Poll with `while kill -0 2345136 2>/dev/null; do sleep 30; done` — never
`pgrep -f` (docs/14 rule 9).

---

## 📋 QUALITY TODO REGISTER (written 2026-07-13 on Kamil's order: "CLEAR state
## with all of the things listed as todo — why, what and how")

Everything known that would raise data quality, ranked by leverage. An item
leaves this list only when done (move to the session log below) or when Kamil
kills it. Costs are honest estimates. "FREE" = CPU/engineering only, no API calls.

### Tier 1 — make every FUTURE generated unit better (loop + gates)

**T1.1 — Wire the §5.2 blind re-screen into the generation loop.
[NEEDS KAMIL'S SIGN-OFF on the policy; build is ~half a day; runtime cost
~1 solver call per repaired accept]**
- WHY: a base/variation accepted after ≥1 repair was fixed by a model that SAW
  the harness failure report, so acceptance proves nothing about the prompt
  alone. This is not theoretical: 6 of the 22 retro-screened repaired accepts
  (101_002, 102_002, 102_003, 102_004, 626_004, 101_003) had shipped harnesses
  asserting things their prompts never said.
- WHAT: in the loop, any base/variation accepted with `attempts > 1` gets one
  independent blind re-solve (prompt only) before promotion; RED → quarantine
  for triage, never silent promotion. Plus docs/12 §5.2.2: an entailment judge
  over the harness DIFF made during repair.
- HOW: post-accept hook in the accept path, reusing the `screen_blind_solve`
  mechanism and its ledger (one mechanism, one ledger); behind a config flag
  (`GEN_BLIND_RESCREEN=1`) so Kamil flips it on; CI later refuses accepts
  lacking the evidence row. Design sketch: docs/12 §5.2.1.

**T1.2 — S6 freshness gate: blind evidence must match the CURRENT harness.
[BUILT + SELF-TESTED 2026-07-13 evening; backlog sweep RUNNING (54 roots, see
RUNNING RIGHT NOW); the LAST step — wiring into CI + pre-push — happens the
moment the sweep leaves the gate green (`stale=0`)]**
- FOUND ON FIRST RUN: 47 roots carried blind verdicts for an OLDER harness
  (mostly the 07-09 R10 harness campaign — tightened harnesses whose blind
  property was never re-proven) + 7 S6 coverage holes (prompts edited, never
  re-screened — incl. 018_003, hand-fixed 07-12). Also caught: `repair_` dirs
  leaked into the screenable population of the PAID screen tool (fixed: they
  are frozen evidence, now excluded in both tools).
- WHY: `logs/screen_blind.jsonl` is keyed by PROMPT sha only, but the blind
  property is a property of the (prompt, harness) PAIR. Editing a harness
  silently invalidates the ledger row. Hit live: after hand-strengthening
  013_001 the ledger still said "screened" — only session knowledge triggered
  the manual re-screen. Nothing systematic forces that.
- WHAT: every new screen row records `harness_sha`; a checker flags any root
  whose current (prompt, harness) pair lacks fresh blind evidence — a screen
  row for this exact harness, or a `strengthen_harnesses` SUCCESS row whose
  `harness_sha_after` matches (its blind gate ran against exactly that harness).
- HOW: `scripts/check_screen_freshness.exs` (dry gate, `--self-test`), wired
  into CI + pre-push; `screen_blind_solve.exs` stamps `harness_sha`; legacy
  rows fall back to git last-commit-time comparison.

**T1.3 — State the S9 bans inside the tools' own prompts.
[DONE 2026-07-13 evening: `gen_stronger` (strengthen tool) now names every S9
ban + "existing tests may violate these (grandfathered) — do NOT imitate
them" + "an unkillable-through-the-API mutant is a documented ceiling, not a
license to reach into internals"; the variations template (which pastes the
BASE harness as reference) got the same named bans + do-not-imitate line; the
base template already had the named bans. 296 tests green.]**
- WHY: the strengthener burned 3 attempts (~6 calls) on 101_001 because the
  model IMITATED the `:sys.get_state` calls already present in that April-era
  harness — grandfathered debt teaches our own tools to cheat. This violates
  the prompt–gate alignment rule (docs/12 §5.1.14: every gate criterion a
  generator is graded by must be STATED in its prompt).
- WHAT: the harness-writing prompts (strengthen tool + generation templates)
  state the S9 bans explicitly and add: "existing tests in this file may
  violate these rules (grandfathered debt) — do NOT imitate them."
- HOW: `gen_stronger` prompt in `scripts/strengthen_harnesses.exs`; audit
  `lib/gen_task/prompts.ex` harness templates for the same statement.

**T1.4 — Phase 3 template upgrades (docs/12 §5.3 — designed, never landed).
[FREE, forward-only; land WITH Phase 3, not before]**
- WHY: measured monoculture — 76% of seed prompts open "Write me", one frozen
  few-shot exemplar (root cause of the GenServer monoculture), ZERO doctests
  corpus-wide (26 golds carry `iex>` examples that never execute), harness
  checklists designed in docs/10 §3.4 but never landed.
- WHAT: (a) shared harness-rule constant (≥1 negative/error-path test per
  public function, boundary tests, `describe` grouping, OTP conventions) used
  by base/variation/write-test templates — they are triplicated today and have
  drifted once already; (b) request doctests + one property test where apt;
  (c) rotate 3–5 few-shot exemplars of different shapes; (d) record each
  seed's blind-screen outcome as free difficulty metadata.
- HOW: all in `lib/gen_task/prompts.ex`; list + rationale in docs/12 §5.3.

**T1.5 — Extend the semantic-mutant operator set. [FREE, CPU sweep after]**
- WHY: the S8 floor is only as sharp as its operators. Today: comparison swap,
  ±1 on literals, :ok↔:error, bool flip. Sharper operators = better tightness
  measurement AND more `bugfix_` units minted automatically (bugfix mints from
  killed mutants; its reject ledger re-opens on harness change).
- WHAT: add guard-boundary swaps (`min`↔`max`), range endpoints (`a..b`),
  clause reordering, arithmetic swaps (`+`↔`-`, `*`↔`div`).
- HOW: `lib/gen_task/mutation.ex` (`semantic_mutants_textual/2` + the AST
  measurement twin must stay in step), tests, then a corpus re-measure sweep.
  Expect new below-floor families — classify + fuzz survivors BEFORE calling
  them work (docs/14 rules 7 and 11).

**T1.6 — Dialyzer gate over the golds. [NEEDS KAMIL: one mix.exs/lockfile
change; then FREE (PLT build + weekly CI)]**
- WHY: 019_001 shipped a `@spec` contradicting its own code; specs must be
  machine-checked. Also the hard prerequisite for the dedoc shape (docs/13
  §2.3, ~331 free units) — wrong specs must never become training targets.
- WHAT/HOW: add `dialyxir`, one-time PLT, driver staging each gold with its
  deps, weekly CI gate. Pilot on 5 families first. Design: docs/13 §2.6.

### Tier 2 — raise EXISTING corpus quality (evidence says more is there)

**T2.1 — Clear the S9 grandfathered debt: 52 harnesses with `:sys.get_state`
reach-ins (11 April-era families), 142 with `Process.sleep`. [~2 calls/family
where LLM-assisted; some hand work]**
- WHY: was "evidence-deprioritized debt" (docs/12 §4.2.5) — no longer: today
  proved it actively corrupts future work (T1.3's why). Reach-in tests are
  also weaker tests.
- WHAT: a ledgered rewrite tool in the strengthen mold: replace each reach-in
  test with an observable-behavior equivalent; blind gate; restore-on-failure.
- HOW: CAUTION — modifying existing test blocks orphans their carved tfim
  golds (the add-only rule exists for this); the tool needs the re-carve path
  (docs/14 §5.0b caveat: re-carve by hand, check ≤98 cols). Start with the 11
  reach-in families; sleeps only on flake-ledger evidence (docs/12 §4.2.6).

**T2.2 — Scaled semantic review. [PAID: ~3.5M tokens for a stratified 60-root
batch; full ~330 roots ≈ 20M]**
- WHY: the 11-dir pilot found 2 real gold defects (018_003 gamed the style
  gate; 101_002's harness gap). The corpus-wide defect rate is unknown.
- HOW: stratified by era (April/July), adversarially verified findings only,
  small-batch ledger protocol; then decide whether the full pass pays.

**T2.3 — Second-source the 15 "FAIL, triaged entailed" keeps. [~15 calls]**
- WHY: each rests on a single triage verdict, and today an LLM-judge verdict
  was proven WRONG (101_003 — docs/14 rule 10). One more independent blind
  solve per keep either flips it GREEN (stronger: prompt proven sufficient) or
  confirms the solver-weak reading with two sources.
- HOW: `screen_blind_solve --only <the 15> --rescreen`; triage any new signal.

**T2.4 — Rubric LLM-judge pass over PASSING tasks (sampled). [PAID; round-#2
candidate]** — WHY: our judge only ever sees failures; OpenCodeInstruct's
ablation shows judge filtering adds quality beyond execution filtering
(docs/12 §6.4). HOW: 3-axis rubric on a stratified sample, agreement-logged
second judge family (PoLL) to guard single-judge bias — which rule 10 just
showed is real.

**T2.5 — Randomized ExUnit seed sweep. [FREE]** — WHY: eval seed pinned to 0;
order-dependence bugs are invisible (docs/12 §5.4). HOW: occasional sweep
variant re-grading with random seeds; low expected yield, cheap.

**T2.6 — Prompt-register monotony rewrite (improvement round #2 — do NOT start
before steady state). [BIG: 2,396 tfim + 302 wt_ + 80/332 seed openers; own
tool + ledger + blind re-screen budget]** — docs/12 §7.4; frozen-template
overfitting is a documented SFT failure mode.

### Tier 3 — protect the TRAINING side

**T3.1 — Export contract + family-keyed split + round-trip validator.
[MANDATORY before any training run; FREE to build]** — WHY: 91.7%
within-family text overlap BY CONSTRUCTION — a naive random split leaks
train→val and invalidates every eval. HOW: docs/13 §3.1 (per-shape spec,
FIM-as-chat decision, family-keyed splits, dedup/sampling weights, CI-gated
round-trip validation).

**T3.2 — Make the scrutiny tools standing: wire `spot_verify.sh` (sampled
accept-side re-verification) + a `reverify_rejects.exs` sample into weekly CI.
[FREE]** — WHY: today they found 15 unsound reject rows and re-confirmed 204
accepted dirs; as one-shots they rot — as CI they keep catching gate
regressions the day they happen.

**T3.3 — Small tools with real quality effect. [FREE]** — (a) promote the
077_001 public-API survivor fuzz into `scripts/fuzz_survivors.exs` (the
verification layer behind every at-ceiling claim — docs/14 rule 11); (b) the
screen's `first_failure` should unwrap `{:invalid, %ExUnit.TestModule{}}`
setup_all errors (102_003's diagnosis needed a local re-grade because the
ledger row truncated the real error).

---

### 2026-07-13 scrutiny session — COMPLETE (Kamil: "do all of these, scrutinize
### everything, random verifies of approved and rejected data")

All work ran through ledgered, resumable, detached tools (docs/14 rule 9). Results:

1. **§5.2 retro blind screen CLOSED: 59 PASS / 15 entailed / 0 open / 0
   unscreened** (74 repaired accepts). Six genuine prompt↔harness gaps found
   and fixed (+cascaded +re-screened GREEN): 102_002/3/4 (undocumented
   migration-module name; 102_003 also had its GOLD defining the repo module
   its own prompt forbade — a repair-loop artifact — plus an undocumented
   atom-deserialisation contract), 626_004 (undocumented `:cleanup_tick`),
   101_003 (harness asserts `keys/1`, never in the prompt). All six were
   repaired accepts — live proof for the §5.2 loop-wiring decision.
2. **Semantic floor (S8) CLOSED: 16 of 20 fixed, 4 at documented ceilings, 0
   open.** New this session: 063_004 0.47→0.94 (chain), 013_001 0.41→0.77
   (hand, no timing — injected-random observation), 101_001 0.47→0.76 (hand,
   clock+`:cleanup` probes; the model's 3 attempts died imitating the
   grandfathered `:sys.get_state` debt), 077_001 RECLASSIFIED at-ceiling
   (public-API fuzzing proved all 15 survivors behaviorally identical —
   docs/14's "hardest real gap" was a classifier-vocabulary artifact, fixed).
3. **Reject-ledger audit: 15 unsound 102_001 tfim rows purged** (written by
   the pre-manifest-fix gate, docs/12 §5.1.12) → 7 units minted; 073_001 rows
   + 27/27 sampled bugfix rejects re-confirmed sound. Standing tool:
   `scripts/reverify_rejects.exs`.
4. **Accept-side spot verify: 8/8 batches clean** (204 random dirs through
   validate/audit_bugfix; `scripts/spot_verify.sh`).
5. **Adaptation pairs RED-gate measured: 249/249 mintable**
   (`scripts/survey_adapt_redgate.exs`) — docs/13 §2.1 ready to build.
6. **Judge-scrutiny catch:** the 101_003 triage judge proposed a prompt fix
   contradicted by the prompt's own text and the gold; hand-verification found
   the real gap instead (docs/14 rule 10). Register cleanup: the strengthener's
   `# Prompt: "…"` citation comments (S10 chatter class, Kamil's spot-catch)
   rewritten to plain behavioral style corpus-wide.

**Still waiting on Kamil (unchanged, decisions only):** §5.2 loop wiring
(docs/12 §5.2.1 — evidence now overwhelming), §4.2 sign-offs, systemd timer
install (4 commands). Then Phase 3.

Last completed: the free derivative top-up (2026-07-13) — 6 tfim + 1 bugfix +
1 repair unit, all created BY the harness strengthening. **Registry: 0 pending
across every work type.** A flaky harness found by the post-run gate is fixed
(see below).

## 📖 START HERE → `docs/14-handover-and-work-register.md`, section "⭐ START HERE"

That section gives you: the verified current state (with the exact command +
expected output for every gate, so you can tell in 2 minutes whether anything
drifted since it was written), the four possible next actions ranked, the exact
per-family commands for the remaining work, the three traps that will bite you,
and where every piece of evidence lives.

The rest of docs/14 is the full reference: corpus inventory, every gate, every
tool, every ledger and what content key makes its rows valid, the complete
open-work register with costs and owners, nine hard-won rules (each one a scar
from a real incident), and copy-paste runbooks. STATUS is the one-screen "what
now"; docs/14 is "how, and why".

## Current mode: 🔧 CATCHING UP

**Improvement round #1 — the 2026-07 quality-assurance catch-up.**
New base-task generation is **paused**. The plan of record is
`docs/11-catch-up-plan.md` (phases) + `docs/12-quality-standard-and-steady-state.md`
(the concrete work list, the quality standard, and the exit protocol).

What that means in practice:

- **Allowed now:** deterministic corpus fixes, gate hardening, validation sweeps,
  the scope decisions listed in docs/12 §4.
- **Next (Phase 2):** one derivative top-up run
  (`GEN_ONLY=backfill scripts/run_detached.sh logs/backfill.log mix run scripts/generate.exs`)
  — only when docs/12 §4 items marked **[blocks Phase 2]** are done.
- **Then (Phase 3):** new base generation (490 queued ideas) — only when Phase 2
  is complete and the loop-hardening items marked **[blocks Phase 3]** are done.
- **Then: draw the line** (docs/12 §7): delete the catch-up tooling and the
  backfill vocabulary, and flip this file to STEADY STATE.

### Checklist to exit this round

- [x] Stale child-prompt copies resynced + staleness gate wired (docs/11 §1a, 2026-07-10)
- [x] Seed self-check fixed, 50 blocked units freed (docs/11 §1b, 2026-07-10)
- [x] Corpus format gate green again (23 embeds, 2026-07-10)
- [ ] docs/12 §4.1 deterministic punch list — DONE 2026-07-10: 020_001 rebuild
      (re-screen GREEN), 001_002 reach-in, chatter sweep (4 families), fence
      artifacts, 23-tfim re-gate (0/23), repair audit (0 flags), semantic
      re-measure (tail = 20 <0.5), register metric, backfill-script removal;
      001_004 redesign (re-screen GREEN), §4.1.3 per-fn+init/1 sweep (ZERO
      survivors across 1,612 evals — populations #1/#2 closed empty);
      §4.1.9 decontamination gate (0 exact / 0 near-miss vs 786 benchmark
      rows); STAGED: nightly-sweep systemd units (needs install, §4.1.10).
      **§4.1 is COMPLETE** except the staged timer install.
      **Every [blocks Phase 2] item is now done — Phase 2 top-up is ready to
      launch on Kamil's go (paid run).**
- [x] docs/12 §4.2.1 — 099_002/3/4 screened GREEN; S6 holds for all 303 seeds (2026-07-10)
- [ ] docs/12 §4.2 decisions signed off (spot-review scope, prompt-monotony scope, semantic floor — tail confirmed at 20 families <0.5 by re-measure)
- [x] docs/12 §5 loop hardening §5.1 — ALL DONE (items 1–7 2026-07-10; item 8
      gate + classification 2026-07-11; remediation + CI wiring 2026-07-12:
      **embed check 1266 clean / 0 reflow / 0 drift, gated in CI**). Still
      OPEN: §5.2 decision (accept-time blind screen for repaired bases +
      entailment judge) — needed before Phase 3
- [x] **Phase 2 COMPLETE 2026-07-12 ~23:0x** — `work_status --counts`:
      variations 0/83, fim 0/331, write_test 0/331, test_fim 0/331 pending.
      Original entry: derivative top-up run **LAUNCHED 2026-07-10 ~18:45** (detached,
      `logs/backfill_phase2.log`; 111 seeds / 710 units). Three passes done by
      2026-07-12 (details in "Where we are right now"). After the two
      registry-honesty fixes (phantom-326 tfim, pool-capped fim) the honest
      remainder is: **10 winnable units running now** (7 fim + 3 variation,
      relaunched 2026-07-12 with GEN_EXCLUDE_SEEDS), **12 bundle-fim units +
      4 variation units parked behind the queued triage decisions**. Phase 2
      closes when the winnable run finishes AND Kamil rules on decisions 1–3
      (each either deletes its parked units from the registry or schedules the
      fix that makes them producible)
- [x] **2026-07-12 spot-check findings RESOLVED** (~18:45: all four content
      fixes landed, resynced, re-gated; both systemic lints live; post-run
      pass executed in full — see below). Original entry: (random
      11-dir semantic review, every finding adversarially verified — Kamil:
      "resolved BEFORE we progress to new generation"):
      1. `018_003_..._01` gold carries a deliberately warning-silenced
         dead-code block + no-op `ignore/1` helper (`solution.ex:243-245,277`)
         — the model gamed the house-style gate. Hand-fix gold, re-gate
         family, resync children embeds (2 fim + wt + 10 tfim).
      2. `101_002_..._01` harness asserts `tracked_key_count/1` (never in the
         prompt — a prompt-only solver crashes) and depends on undocumented
         `:max_window_ms`. Fix the prompt, resync children (wt + 10 tfim),
         audit WHY the blind screen passed this family.
      3. `019_001_..._01` `@spec bulk_create_items` contradicts @doc and code
         (map vs tuples) — fix spec, resync children (3 fim + 10 tfim).
      4. Misleading test name "members exactly at the window boundary are
         counted" (tests 1 ms inside) in 101_002's harness + wt copy — it is
         literally the spec of tfim_101_002_08. Rename in parent + wt,
         resync.
      5. **Systemic — DONE 2026-07-12 evening:** (a) corpus-wide scan with
         the same detectors over all 4,605 dirs (`logs/spotcheck_scan.jsonl`):
         both classes fully contained to the two families above — zero other
         instances; (b) both detectors are HARD accept-gate lints now
         (`Evaluator.no_op_helpers/1`, `undocumented_api_calls/3`, wired into
         `quality_shortfall`, 288 tests green), so neither class can recur.
      **Progress:** items 1–4 hand-edits are committed; family re-gating
      (perfect + mutants) and embed resyncs run the moment the loop exits
      (resync refuses while a generate BEAM is alive).

      ### POST-RUN PASS — EXECUTED 2026-07-12 ~18:20-18:45 ✓ (all six steps;
      ### one extra find en route: tfim_072_004_03's carved test head at 100
      ### columns — renamed + the mint gate now enforces ≤98 on carved
      ### fragments at accept time. Remainder loop relaunched: 3 variations +
      ### 5 fim + 13 macro tfim.) Original checklist:

      1. **Purge `074_*` entries from `logs/tfim_rejected.jsonl`** — the
         running loop's in-memory OLD isolation gate rejected the macro-
         asserting tfim blocks as "vacuous" (11 on 074_001, 10 on 074_002,
         likely more on 074_004) and permanently ledgered them. The gate is
         fixed on disk (errored-kills now count); the verdicts are unsound.
         Purge by prefix AFTER the loop exits (it appends while running).
      2. **Embed resyncs for the four hand-edited spot-check families**
         (018_003, 019_001, 101_002, wt_101_002): `resync_embeds.exs`
         (module-FIM/wt_ from the edited parents) + `resync_tfim_embeds.exs
         --apply` (module fences changed), then both dry-runs must converge.
      3. **Re-gate the four edited families**: validate perfect + mutants
         (hand edits require the perfect eval, docs/12 §5.1.9).
      4. Corpus gates: `format_corpus --check`, `check_embeds` (expect 0
         reflow / 0 drift).
      5. Batch-commit remaining accepted dirs + push (pre-push validates).
      6. **Relaunch** `GEN_ONLY=backfill` — picks up: 034_001 variations with
         named-warning repairs, re-mint of the purged 074 macro tfim blocks
         through the fixed gate, and any remaining tail. **Blind-screen audit
      answered:** 101_002 has NO screen ledger entry; it was accepted with
      `variation_blind=True`, and the repair loop defeated blindness — the
      failure report leaks harness internals (missing-function errors), which
      the fix reply then satisfies. This is the first confirmed live instance
      of the open §5.2 gap ("accept-time blind screen for repaired bases"),
      turning that decision from theoretical to demonstrated. §5.2 stays the
      remaining pre-Phase-3 design decision.
- [ ] Phase 3: new generation resumed and first batch validated
- [ ] The line: catch-up tooling deleted per docs/12 §7.2, this file flipped

### Where we are right now (2026-07-12 ~23:15 — PHASE 2 EXECUTION COMPLETE)

**`work_status --counts`: 0 pending across every work type** (variations 0/83,
fim 0/331, write_test 0/331, test_fim 0/331). All four queued decisions were
resolved as FIXED and proven live; the spot-check blockers are resolved with
both defect classes contained and gated; five loop-level information/gate gaps
found and fixed during the runs (bundle prompts, manifest staging, repair
clobbering, named warnings, predicate-name regex; isolation errored-kills).

### Existing-data quality backlog (2026-07-12 evening — Kamil: "assure the
### best quality of already existing data"; tools built, runs on his go)

1. **Retroactive blind screen of repaired accepts** — TOOL READY:
   `mix run scripts/rescreen_repaired.exs` (dry) / `-- --go` (paid) /
   `-- --report`. Population: 74 of 126 accepted variations were accepted
   after ≥1 repair (blind property unverified — the §5.2 gap, 101_002 the
   proven hit). Ledger cross-check shows the REAL remainder: 42 already PASS
   for their current prompts, 10 FAIL-but-triaged-entailed (solver errors,
   prompts explicitly sufficient — kept), **22 never screened ≈ 22 solver
   calls**. Reuses the S6 screen + its ledger; resume-free.
2. **Semantic-mutant floor remediation** — TOOL READY:
   `mix run scripts/strengthen_harnesses.exs` (dry) / `-- --go [--limit N]`.
   30 deduped parent families below 0.5 kill rate (worst: 075_004 at 0.00).
   Per family: one ADD-ONLY strengthen call + hard gates (existing test
   blocks byte-verbatim — tfim golds carve them; reference green + zero
   warnings + lints; whole-mutant killed; semantic re-measure ≥ 0.5 and
   ≥ old; **blind gate: a prompt-only solve must pass the stronger harness**)
   then apply + wt_ twin + tfim resync with restore-on-failure. ~2 LLM
   calls/family. New tests become new carvable tfim units automatically.
3. **Dialyzer over the golds** (free, unpiloted): would have caught the
   019_001 @spec lie mechanically. Pilot parked; needs a PLT build + a
   driver staging each gold with its deps.
4. **Scaled semantic review** (the expensive one): today's 11-dir
   review+verify workflow cost ~660k subagent tokens and found 2 defective
   families. All ~330 roots ≈ 20M tokens; a stratified 60-root batch
   (≈3.5M) would tighten the defect-rate estimate first.
5. **Full --fim sweep** — DONE 2026-07-12: ALL FIM TARGETS EXERCISED ✓
   (first sweep since the day's ~40 new fim units; CI runs it weekly).

### Semantic floor — POINT 2 COMPLETE (2026-07-13, docs/13 §1.4–§1.5.2)

**13 of the 20 tail families now clear the floor** (mean +0.37; 074_001/079_001/
075_001 at 1.00). The recipe that worked, and is now the documented remediation
order: **enrich the prompt → canonical blind re-screen → re-strengthen the
harness** (`enrich_prompts.exs` → `screen_blind_solve.exs` →
`strengthen_harnesses.exs`, all ledgered/resumable). Nine families were only
strengthenable after enrichment; four had been impossible before it. Clinching
evidence: 001_001's prompt FAILED the blind screen in July; enriched (22→109
lines) it passes, and its harness went 0.47 → 0.87.

**The 7 that remain are classified, not hand-waved** (`classify_survivors.exs`):
3 are AT THEIR OBSERVABLE CEILING (041_001, 041_003, 023_002 — surviving mutants
change only internals; killing them would need the `:sys.get_state` reach-in the
S9 lint forbids, which is exactly what each attempt tried) and 4 are real gaps
with named next steps (063_004 zero-budget semantics; 101_001 free retry;
013_001 tests its own reference fails; 077_001 hardest, 0.42).

**Conceptual result for §4.2/S8:** a flat 0.5 floor is NOT universally reachable.
The honest metric is the kill rate among OBSERVABLE mutants, with the rest a
documented ceiling. Classify survivors before calling a family "work".

**Six bugs fixed en route** (see docs/13 §1.5.2), incl. 51 stale `wt_` dirs —
3 shipping a stale GOLD harness — now gated in CI + pre-push.

### Bugfix corpus MINTED — 2026-07-13 ~01:00 ✓

**957 byte-surgical bug→fix units across 326 seeds; registry converged to
bugfix 0 pending** (three passes; final 2 candidates correctly rejected as
survivors and ledgered). Every unit: task spec + one-line semantic bug with
comments intact + the real failing ExUnit report; gold byte-equal to the
parent reference. Kamil's two spot checks shaped the pipeline: the reject
audit (all verdicts cross-match the independent survivor measurements; ledger
now keys on solution+harness sha so strengthened harnesses re-open survivors)
and the accept audit (caught AST-reprint pollution → byte-surgical
`semantic_mutants_textual/2`; standing tool `scripts/audit_bugfix.exs` —
**10/10 random real units pass all six properties**). The 28 property-tfim
units minted in the same run. format_corpus knows the shape (bugfix prompts'
buggy fences are captured mutant data, never reformatted — the repair_ rule).
Next per Kamil's overnight brief: `strengthen_harnesses -- --go` (point 2).

### Semantic-floor run COMPLETE — 2026-07-13 ~04:30 (docs/13 §1.4)

`strengthen_harnesses` over all 30 weak-tail families: **10 already_ok** (the
July-8 tail was substantially a MEASUREMENT ARTIFACT — the 0.00–0.35 band was
all wt_ rows whose parents measure fine; zero calls spent), **3 applied and
committed** (002_003 0.40→0.68, 097_002 0.47→0.84, 077_004 0.48→0.52 — each
through add-only + green + lints + whole-mutant + re-measure + BLIND gate,
propagated to wt_/tfim, re-gated perfect+mutants+format), **17 rejected**:
12 by the blind gate, 2 by the S9 lint (the model tried `:sys.get_state` to
cheat mutants), 2 wrote tests the reference fails, 1 stayed below floor.

**The finding that matters (evidence in docs/13 §1.4):** for the 12 blind-gate
families the PROMPT is the weak link, not the harness — they are terse (14–18
lines) with no behavioral specificity, so any tightening test pins something
unstated. Positive control: 097_002's detailed prompt produced the biggest
win. **Work item, in this order:** enrich prompt → blind re-screen → re-
strengthen (all three tools exist; rejected families re-attempt for free).
This also largely closes the §4.2 semantic-floor question with evidence.

### Data extension research — docs/13 (2026-07-12 night; Kamil's deep-research brief)

Full catalog in `docs/13-existing-data-improvement-and-extension.md`. Built and
proven this session: **`:bugfix` work type** (verified bug→fix pairs from
killed semantic mutants — 976 pending units / 326 seeds, zero LLM, registry-
live so fresh generation mints it automatically; pilot 6/6 green) and
**property-block tfim carving** (075_001: 0 → 29 carvable, pilot 10/10
isolation-killed; zero churn on the 3,203 shipped prompts). Repair-mint
manifest fix landed (tier-B pairs re-verifiable). Ready-to-build designs with
measured volumes: adaptation pairs (base gold + variation spec, RED-gate),
multi-turn repair dialogues (86 chains — PERISHABLE, logs/attempts archived
2026-07-12), dedoc (blocked on the Dialyzer gate), style-repair pairs (207),
cap lifts (~1,900 free tfim). **Blocking prerequisite before any training
use: the export contract + family-keyed split (91.7% within-family text
overlap — a random split would leak).**

**What still stands before Phase 3** (full detail: docs/14 §5.1):
- **§5.2 decision (Kamil) — the one true blocker.** Accept-time blind screen for
  repaired bases. Evidence is live: 101_002 was accepted after a repair and
  shipped a harness asserting a function its prompt never mentioned.
  `rescreen_repaired.exs` says 22 of 74 suspects are still unscreened (~22 calls).
- §4.2 sign-offs (Kamil) — note the semantic-floor half is now ANSWERED with
  evidence (docs/14 §5.3): the floor should be "kill rate among OBSERVABLE
  mutants", not a flat 0.5.
- Nightly-sweep systemd timer install (Kamil, 4 commands).
- FREE WORK AVAILABLE NOW (no decision needed): 6 tfim + 2 bugfix units are
  pending because the strengthened harnesses created new carvable blocks and
  re-opened previously-unkillable mutants. One backfill run mints them.

(original list follows)

- **§5.2 decision (Kamil)** — accept-time blind screen for repaired bases;
  101_002 is the confirmed live instance of the gap.
- docs/12 §4.2 sign-offs (Kamil) and the nightly-sweep systemd timer install
  (§4.1.10, Kamil).
Then Phase 3 (490 queued base ideas) and, after its first validated batch,
"the line" (docs/12 §7.2: delete catch-up tooling, flip this file).

---

### Earlier today (2026-07-12 ~13:00 — push unblocked, Phase 2 tail triaged, focused relaunch)

**The failed `git push` is fixed and explained.** Two separate things looked like
"hundreds of problems" but were not corpus rot:

1. **The actual push blocker** was the corpus format gate: 218 prompt embeds
   (216 from the 2026-07-12 resync) carried a trailing blank line inside the
   fence. Canonicalized corpus-wide, root cause fixed in
   `EvalTask.Fim.rewrite_skeleton` (trims the skeleton's trailing newline), and
   `format_corpus --check` now says it is a gate instead of "report only".
   Both embed gates re-verified after formatting: 1269 clean / 0 reflow /
   0 drift, tfim resync unchanged.
2. **The "hundreds of warnings"** were unused-alias noise from the raise-body
   MUTANTS the `--mutants` gate compiles on purpose (broken by design), spilling
   to the terminal because ParallelCompiler workers print to stderr no matter
   what. Reference solutions were already warning-free (the perfect gate
   enforces zero). The spill is now captured (`EvalTask.Runner.quiet_compile`),
   verified: a planted unused-alias mutant grades `compile_warnings=1` with
   0 stderr bytes. Found en route: all five bare-`elixir` scripts let a stale
   `_build/test` beam shadow freshly-compiled dev code — path order fixed.

**Full perfect sweep re-run (logs/perfect_sweep_20260712.log): 6 failures → 0
real ones.** 034_001_03 + 089_004_04 (from the 12 hand-fixed golds — the
hand-fix left stale skeletons; the embed gate can't catch that, the perfect
eval can) rebuilt deterministically and re-graded 1.0; three tfim fragments
carried >98-char carved test heads — test names shortened in parent+child, all
30 sibling tfim prompts resynced. 017_001 fails only without a Postgres host
(environmental, expected unattended).

**Phase 2 tail triaged deterministically (zero LLM calls).** The registry said
7 variation + 32 fim units. A viable-target sweep over all pending seeds showed:

- **13 fim units could NEVER be produced** — parents with 1-2 unique functions
  already covered (063_001, 075_004, 092_001/2/3, 131_002), plus 074_001/2/4
  whose solutions are 4 defmacros + 1 def while the target enumerator is
  defmacro-blind. `missing(:fim)` now delegates to `Fim.missing_units/2`
  (pool-capped, same honesty rule as the tfim fix; 258 tests green).
- **12 fim units sit on the 4 bundle-parent seeds** (016_001, 018_001, 019_001,
  102_001) — kept visible as pending; decision below.
- **7 fim units are winnable** (100_001, 100_003, 623_002, 625_003 ×2,
  625_004, 626_004) + ~3 winnable variations (098_001 ×2, 100_001).
  034_001's 3 variations fail distinctness systematically (model converges on
  the same `reconcile/3` API) and 018_001's variation fails 0/N tests every
  attempt — both parked with the triage decisions.

**A focused relaunch is running** for the winnable units only, using the new
`GEN_EXCLUDE_SEEDS=016_001,018_001,019_001,034_001,102_001` filter (added +
tested), so the loop cannot repeat yesterday's rejected-nearly-everything run.

### Queued decisions for Kamil (updated 2026-07-12)

1. **fim on bundle parents — RESOLVED 2026-07-12: FIXED** (Kamil's criterion:
   fix if the units would be valuable — they are: multi-file Phoenix/Ecto FIM
   is scarce, realistic data, and Phase 3 bundles would hit the same wall).
   The gap was two-sided and both sides are landed + deterministically
   verified with zero LLM calls:
   - *Eval:* bundle children were reconstructed into a marker-stripped blob
     and plain-compiled — no kit, no Repo boot — so tier-B/repo parents failed
     0/N even on perfect skeletons. `Fim.reconstruct_bundle/3` now maps the
     skeleton back onto the parent's `<file>` files and grades through the
     same tier machinery as the parent. Pre-flight on all 4 seeds with gold
     candidates: 14/14, 31/31, 20/20, 18/18, 0 warnings; a raise-mutant of an
     exercised target fails 14/14 (gate discriminates), an unexercised target
     survives (correctly rejected as a fim target).
   - *Gen:* `deterministic_skeleton` now builds bundle skeletons from the
     marker-stripped parent and REPLACES-or-INSERTS the fence (a missing fence
     was the dominant `:contract` rejection). Hallucination filter and pool
     caps use the same view.
   The 4 bundle seeds (12 units) rejoin the runnable backfill; a focused run
   launches when the current 7-seed run finishes.
2. **defmacro-blind target enumeration — RESOLVED 2026-07-12: FIXED** (same
   criterion: macro FIM — quote/unquote bodies, `__using__`, assertion
   helpers — is scarce, distinctive metaprogramming data). Audit found the
   pipeline was ALREADY macro-ready end to end: `build_skeleton`/`splice`
   handle defmacro, `Fim.mutate` guts them, and a gutted macro blowing up
   harness compilation is an errored-kill (`errored_against_mutant?`, wired
   2026-07-10). Only the enumerators were blind: `Mutation.all_functions/1`
   (selector pool + isolation gate — safe there, inconclusive grades just keep
   scanning) and the gen-side covered-targets parser now count
   defmacro/defmacrop. Nine 074_x macro targets perma-rejected on 07-04/07-07
   — BEFORE the errored-kill fix existed, i.e. under tooling that could not
   see a macro kill — were purged from `logs/fim_rejected.jsonl` (the one
   non-074 entry stays). Pre-flight with zero LLM calls: gold
   `assert_recent/2` grades 17/17 + 0 warnings, its mutant errored-kills.
   The 6 units on 074_001/2/4 rejoin the runnable backfill.
3. **variation distinctness for 034_001 — RESOLVED 2026-07-12: FIXED** (same
   criterion; the fix is generic, not 034-specific — 098_003 and 101_002 hit
   the same rejection, and Phase 3 has 490 bases × 3 variation slots ahead).
   Root cause was an information gap, not bad data: the distinctness gate
   (already pre-cycle, zero grading cost) rejects a candidate whose public
   function set equals the base's or an accepted sibling's — but the
   generation prompt only listed existing variation NAMES, never the taken
   API sets, so the model kept converging on the base's natural surface
   (`reconcile/3`) under different task names. `Prompts.variations` now
   states the gate's exact criterion as a HARD CONSTRAINT with every taken
   set listed; `Variations.run` threads the sets it already computed for the
   gate into the prompt. No perma-skip ledger for these: distinctness
   failures are stochastic (LLM-quality), and a permanent verdict is only
   sound for deterministic gates — repeat offenders after this fix go to a
   human triage list instead. NOTE: rejected variation candidates were never
   in the dataset (staging-only; promotion happens on accept), so no
   accepted data was ever deleted by these rejections. 018_001's variation
   (0/N tests every attempt) is a different failure mode — watch it on the
   next pass.
4. **tfim describe-carving — RESOLVED 2026-07-12: FIXED** (same criterion;
   the strongest case of the four: tfim is fully deterministic — gold carved
   from the harness, prompt templated, gates local — so the unlock costs ZERO
   tokens). The carver, isolation gate, embeds resync and bookkeeping are now
   describe-aware with ExUnit-style qualified names; the eval splice needed no
   changes (already indent-generic). Backward compatibility proven corpus-wide:
   resync dry-run over all 2,924 existing tfim embeds reports unchanged.
   Pre-flight: seed 037_003 (zero top-level tests — minted nothing before)
   carved 8 nested tests, all isolation-kill gated, all grade 8/8 clean.
   **Registry: test_fim 0 → 219 pending units / 27 seeds — all free to mint;
   the running backfill loop mints them as derived work.**

### All four queued decisions are now resolved (2026-07-12, Kamil's criterion:
### fix if valuable). Bundle-fim additionally needed two live fixes after its
### first real run (see git log): the staged parent lacked manifest.exs (tier
### misdetection — the docs/10 §5.13 class, now fixed at read_triplet), and
### repair replies could clobber the deterministic skeleton (now re-derived
### after every repair).

Still waiting on Kamil (unchanged): nightly-sweep systemd timer install
(§4.1.10) and the §4.2 / §5.2 decisions.

### History of this round (compressed — details live in the git log and docs/12)

- **2026-07-10:** Phase 2 top-up launched (111 seeds / 710 units). Stale
  child-prompt resync, seed self-check fix, format gate re-greened.
- **2026-07-11:** embed-staleness checker built + all 64 families classified
  (ledger `logs/embed_classify/recovered.jsonl`); remediation tool
  `scripts/resync_embeds.exs` built and self-tested (one-shot, delete at the
  line; ledger `logs/embed_resync.jsonl`).
- **2026-07-12 overnight:** first pass finished; 84 accepted dirs committed;
  171 embeds resynced, 12 redesigned-parent golds hand-fixed;
  `EvalTask.Fim.signature_stub` continuation-`do:` bug fixed; embed CI gate
  wired. Second pass exposed the phantom-326: `missing(:test_fim)` counted
  units the carver can never mint (describe-grouped harnesses); now delegates
  to `TestFim.mintable_candidates/2` — test_fim honestly reads 0 pending.
- **Loop runbook** (still current): detached loop = PID in
  `logs/backfill_phase2.pid`, log `logs/backfill_phase2.log`. Never restart
  while a `beam.smp` is alive; if dead, the relaunch command is idempotent:
  `GEN_ONLY=backfill scripts/run_detached.sh logs/backfill_phase2.log mix run scripts/generate.exs`
  (add the current `GEN_EXCLUDE_SEEDS` list from "Where we are right now").

---

## The two modes (definitions)

**STEADY STATE** — one command produces new data
(`scripts/run_detached.sh logs/loop.log mix run scripts/generate.exs`), every
quality check lives inside that loop or in CI, and nothing needs to be "caught
up". No backfill tooling exists in the repository.

**CATCHING UP (improvement round #N)** — we raised the quality standard, so
existing data must be brought up to it. Every round follows the protocol in
docs/12 §7.3: bump the standard → wire the new check into the loop + CI *first*
→ write a one-shot upgrade tool with its own ledger → run it to completion →
verify the whole corpus → **delete the tool** → flip this file back.

## Round history

| # | Round | Dates | What was raised | Status |
|---|-------|-------|-----------------|--------|
| 1 | 2026-07 QA catch-up | 2026-07-07 → … | prompt↔test consistency, mutation & format gates, embed staleness, blind screening (docs/10) | **in progress** |
