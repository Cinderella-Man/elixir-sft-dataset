# 20 — Prompt-register rotation (G3, deterministic half): design

Written 2026-07-23, before implementation, per the rule-9 discipline: the
frozen-anchor inventory below was verified by reading every parser that
touches prompt text (resync battery, check_embeds, format_corpus,
lint_harnesses, the evaluator's S9 contract scan, audit_bugfix). The G3
STATUS item records the same constraints in short form.

## 1. Problem

Nine task shapes render their `prompt.md` through ONE fixed template each
(`lib/gen_task/` builders). Thousands of units therefore share identical
boilerplate register — a monotone surface a trained model can overfit to.
G3's deterministic half rotates the template PROSE across a small variant
set, selected reproducibly per unit, with zero LLM involvement and zero
change to what any parser reads.

## 2. Non-negotiable constraints (verified, with the parser that owns each)

**Frozen byte-exact — marker lines and layouts:**

| Anchor | Owner(s) |
|---|---|
| `## New specification` | evaluator + lint `contract_text` (adapt: contract = AFTER) |
| `## Module under test` | contract_text (wt/tfim: contract = BEFORE); lint backfill patcher anchor |
| `## The module` | contract_text (dedoc: contract = BEFORE) |
| `## The task` (sfim/bundlefim, exact `\n## The task\n\n`) | resync_sfim sniffer |
| `## The buggy module` + blank line + ```` ```elixir ```` fence | resync_bugfix + audit_bugfix capture |
| `## Failing test report` + blank line + ```` ``` ```` fence | resync_bugfix + audit_bugfix capture |
| `## The module with `NAME` missing` | resync_sfim name recovery; format_corpus shape pair |
| `## The bundle with `PATH` missing` | resync_bundlefim path recovery; format_corpus shape pair |
| Sentence `the `@spec` for `NAME/ARITY` has been removed` | resync_specfim id recovery (regex tolerates one `\n` inside) |
| H1 `# Implement the missing function` | resync_sfim + format_corpus sniffer (numbered namespace!) |
| H1 `# Implement the missing file` | resync_bundlefim + format_corpus sniffer (numbered namespace!) |
| Every ```` ```elixir ```` / ```` ``` ```` fence layout | check_embeds/resync_embeds fence extraction |
| `# TODO` blank markers (incl. `# TODO: @spec`) | carver contracts, `EvalTask.Fim.extract_skeleton` (LAST TODO-bearing fence) |

**Frozen semantically — content that must survive any rewording:**

- wt's requirement bullets (async: false, no `ExUnit.start()`, self-contained,
  zero warnings incl. `+0.0`/`-0.0`, single file) — the literal code tokens stay.
- Every shape's "change nothing else / only the X" completion contract.
- tfim's `#{kind}` interpolation ("test"/"property"); sfim/specfim/bundlefim
  name/arity/path interpolations.

**Vocabulary ban in rotated prose:** no `Process.send_after`, no
`:interval`/`:period`-shaped atoms. Reason: contract_text includes the
BEFORE-marker prose for wt/tfim/dedoc and the WHOLE prompt for bugfix/tdd,
and the S9 timer scan keys on exactly those tokens.

**Selection determinism:** `variant = :erlang.phash2(unit_id, n_variants)`
where `unit_id` is the dir basename (`wt_109_001_…`, `tfim_…_04`). phash2 is
portable and stable across OTP releases (and the toolchain is pinned). Same
id → same bytes, forever — resyncs reproduce prompts exactly (constraint b).

**Single source of truth:** variants live in the template modules; the
miners AND the resync tools render through the same builder (constraint c),
so the corpus rotates via the standing `--apply` battery and stays gated by
the same dry runs.

## 3. Architecture

- New `GenTask.Register` module: `variant(unit_id, n)` (phash2 wrapper) +
  shared doc of the constraints above.
- Each builder gains a REQUIRED trailing `unit_id` argument (no default —
  a caller that forgets renders nothing silently wrong; it fails to compile).
  Builders keep their existing names/return shapes.
- Each template module holds `@variants` — 3 entries. **Variant 0 is the
  current wording, byte-for-byte** (a compatibility anchor that also proves
  the frozen-marker claim: `phash2(id, 3) == 0` units resync to UNCHANGED
  prompts). Variants 1–2 are new registers:
  - v1 "workshop": colleague-to-colleague, task-first framing.
  - v2 "spec sheet": terse, requirement-first framing.
- Property test over ALL shapes × ALL variants: renders with dummy payloads
  and asserts every frozen anchor of §2 appears byte-exactly, fences parse,
  `extract_skeleton` finds the TODO fence where applicable, and the banned
  vocabulary is absent from the template prose (payload excluded).
- A `variant 0 == today's bytes` golden test per shape (renders v0 and
  compares against a fixture captured from the pre-rotation builder).

## 4. Callers to thread `unit_id` through

Miners: `bugfix.ex`, `write_test.ex`, `adapt.ex`, `dedoc.ex`, `test_fim.ex`,
`mint_sfim.exs`, `mint_tdd.exs`, `mint_specfim.exs`, `mint_bundlefim.exs`.
Resyncs: `resync_bugfix_embeds`, `resync_embeds --wt-all`, `resync_adapt_embeds`,
`resync_dedoc_embeds`, `resync_tdd_embeds`, `resync_tfim_embeds`,
`resync_sfim_specs`, `resync_specfim_embeds`, `resync_bundlefim_embeds`.
Tests under `test/gen_task/` and `test/scripts/` that call the builders.

## 5. Rollout (after the stale-gold batch remint exits — gate-sha trap)

1. Land Register + variants + API threading + tests (all lib edits between
   sweeps). `mix test` + every resync `--self-test` green.
2. Run the full resync battery with `--apply` (each tool rebuilds through
   the rotated builders): ~2/3 of templated prompts rewrite, 1/3 stay
   (variant 0). Deterministic, no LLM, resumable per tool.
3. Verify: every resync dry-run back to 0; `check_embeds` 0 reflow/0 drift;
   `format_corpus --check` 0; scoped perfect validate on a sampled family
   per shape + the standing weekly gates; `mix test`.
4. Commit (tasks tree staged via `git add tasks/`, per the standing lesson).
5. THEN the LLM half (register rewrites of monotone SEED `_01` prompts with
   mandatory blind re-screens) — separate item, detached ledgered sweep.

## 6. Why variant 0 stays in the set

Two-thirds rotation already breaks the monotone-register surface; keeping
today's wording as a live variant (a) anchors the frozen-marker property
test to reality, (b) makes the corpus diff exactly attributable (a dir
whose prompt changed did so ONLY because its hash picked v1/v2), and
(c) keeps a canonical register the docs and meta-prompts can keep quoting.
