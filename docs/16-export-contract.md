# 16 — The export contract (T3.1)

**Status: LIVE (2026-07-14). `scripts/export_dataset.exs` implements exactly
this document; `--check` is the CI gate. Nothing may be trained on this corpus
except through this exporter.**

The corpus has never been exported. This document fixes *how* — because the
obvious way is wrong in a way that silently invalidates every eval you would
run afterwards.

---

## 1. The problem this exists to prevent

**Measured: 91.7% within-family text overlap, by construction.** It is not a
defect — it is what the derived shapes ARE:

- `tfim_016_001_07`'s prompt embeds `016_001`'s entire module *and* its entire
  harness, with one test blanked.
- `wt_016_001`'s prompt embeds `016_001`'s module verbatim.
- `bugfix_016_001_02`'s prompt embeds `016_001`'s whole task spec plus a
  one-token-mutated copy of its module.
- `016_001_..._03` (a code-FIM child) embeds the module with one function
  blanked.
- `adapt_016_002`'s prompt embeds `016_001`'s entire gold as the starting
  point *and* `016_002`'s entire spec; its gold is `016_002`'s gold verbatim.

A random 95/5 split therefore puts near-copies of the same module on both
sides of the line. The val score you would read is a memorisation score, and
it would look *great* — which is the dangerous part.

**The unit of leakage is the base idea `a`** — the first 3-digit group of the
directory name — because everything derived from a base idea shares its text,
and different variations (`b`) of one idea are themselves close paraphrases
(`001_001_rate_limiter` vs `001_003_hierarchical_limiter` share the domain,
the API register and much prose). 5,898 dirs collapse to **83 families**.

**Rule (enforced): a family is atomic. Every example of family `a` lands in
exactly one split.** Never split by directory, by shape, or at random.

---

## 2. What one exported example is

One JSONL row per task directory, chat-shaped:

```json
{
  "messages": [
    {"role": "user", "content": "<prompt.md verbatim>"},
    {"role": "assistant", "content": "<gold, wrapped in one ```elixir fence>"}
  ],
  "metadata": {
    "task": "016_001_paginated_list_endpoint_01",
    "shape": "single",
    "family": "016",
    "split": "train",
    "sample_weight": 1.0,
    "family_size": 61,
    "prompt_sha": "…", "completion_sha": "…",
    "difficulty_tier": "blind_solvable",
    "screen_attempts": 3, "screen_greens": 2
  }
}
```

The three difficulty fields (T1.4 sliver d, 2026-07-19) are ADVISORY,
ledger-derived (`logs/screen_blind.jsonl` aggregated per `a_b` root):
`difficulty_tier` is `blind_solvable`, `keep_class` (the judged-keep
hard-task family), or `unscreened`; `screen_attempts`/`screen_greens` are
the raw counts. Since 2026-07-23 (the G9 probe: 5 of 10 sampled "hard"
roots solved ≥2 of 3 fresh blind attempts — single verdicts are
luck-contaminated) the tier is the MAJORITY of the root's last up-to-3
verdicts: one row keeps its verdict, a 2-row split reads `keep_class`
(hard until a majority proves otherwise). Derived shapes inherit their
owner root's tier — a training run can curriculum-sort or re-weight by
tier without re-deriving anything.

- **`user` is `prompt.md` verbatim.** Every prompt in this corpus is already a
  complete, self-describing request (the blind-solve screen, S6, is precisely
  the property that an independent solver can satisfy it from the prompt
  alone). Nothing is prepended, no system message is invented: the corpus's
  own quality gate is defined against this exact text, so the training text
  must be that text.
- **`assistant` is the gold**, wrapped in a single ```elixir fence — the form
  every gate already validates the gold in.

### 2.1 The gold, per shape (the ONLY mapping)

| shape | gold file | what the assistant produces |
|---|---|---|
| `single` | `solution.ex` | the whole module |
| `multifile` | `solution.ex` | the bundle (inline `<file path=…>` blocks) |
| `fim` | `solution.ex` | the ONE function whose body the prompt blanked |
| `write_test` | **`test_harness.exs`** | the whole ExUnit harness |
| `test_fim` | `solution.ex` | the ONE `test` block the prompt blanked |
| `bugfix` | `solution.ex` | the repaired module |
| `adapt` | `solution.ex` | the variation's module, produced by modifying the embedded base gold |
| `dedoc` | `solution.ex` | the parent's documented module (the prompt embeds it stripped of all doc/spec attributes) |
| `style` | `solution.ex` | the accepted attempt's module (the prompt embeds the working-but-style-rejected attempt + the style review) |
| `dialogue` | `solution.ex` | the accepted final module of a frozen repair chain (§5b — multi-turn) |
| `tdd` | `solution.ex` | the module that passes the embedded test suite (tests-as-spec; gold is a parent byte-copy, weight 0.25) |
| `spec_fim` | `solution.ex` | the ONE `@spec` attribute the prompt blanked (`# TODO: @spec` marker; graded by normalized AST equality) |

Bundle-FIM units (2026-07-19, "write the missing file") are `fim`-shaped
`_0N` children of the six multi-file roots — the prompt blanks one whole
file of the bundle; the existing `fim` row covers them.

`write_test` is the one shape whose gold is NOT `solution.ex` (its
`solution.ex` is the *input* module, embedded in the prompt). Getting this
wrong would train the model to answer "write tests for X" with X itself —
the exporter asserts it.

### 2.2 The FIM-as-chat decision

Code-FIM (`fim`) and test-FIM (`test_fim`) are exported as **ordinary chat
turns, not as raw infilling with control tokens** (`<PRE>/<SUF>/<MID>`).

Why: the prompt already *states the task in words* and shows the code with a
`# TODO` marker in place. It reads as a request, not as a raw infill context.
Exporting it as chat keeps one uniform training format, keeps the val metric
comparable across shapes, and matches how the model will actually be asked
(an editor asking "fill this in" sends a chat message). A raw-infill export
would need a different tokenizer contract per model family and would strand
these 4,258 units behind that choice. If a future run wants raw FIM, it can
re-derive it from the same dirs — the prompts keep the marker.

### 2.3 What is NOT exported

- `repair_*` dirs (17): frozen *evidence* — captured failing attempts kept to
  prove gates worked. They are a legitimate future multi-turn source (TD.2),
  but they are not single-turn training data, and their prompts are not
  S6-screened. Excluded by prefix, asserted by the round-trip check.

---

## 3. The split

**Deterministic, content-free, family-atomic:**

```
val  ⇔  first 8 hex chars of sha256("split-v1:" <> family) mod 20 == 0
```

- ~5% of families → val. No RNG, no seed file: the same corpus always
  produces the same split, on any machine, forever. Re-running the exporter
  cannot reshuffle the eval.
- The `split-v1:` prefix is the version handle. Changing the split at all
  means bumping it to `split-v2:` — which is a visible, reviewable, one-line
  diff, not an accident.
- **The split is over FAMILIES, and the family count is small (83).** With
  ~5% of 83 families, val holds a handful of *whole* families — a genuine
  held-out-idea test, which is the only thing worth measuring here.

---

## 4. Sampling weights (advisory metadata, not enforced)

Volume per shape is wildly uneven (3,267 `test_fim` vs 343 `single`), and the
big shapes are the ones that share context text with their parents. Training
on raw counts would drown the base task in its own derivatives.

The exporter emits a per-example `sample_weight` — a *suggestion*, applied at
training time, never by dropping rows:

| shape | weight | why |
|---|---|---|
| `single`, `multifile` | 1.0 | the irreducible task; nothing else teaches it |
| `write_test` | 1.0 | distinct skill (authoring tests), one per family |
| `fim` | 0.5 | shares the parent module verbatim |
| `bugfix` | 0.5 | shares the parent spec + a near-copy module |
| `adapt` | 0.5 | distinct skill (brownfield editing) but shares the base gold verbatim and the variation's gold+spec |
| `dedoc` | 0.5 | distinct skill (documenting existing behavior) but its completion IS the parent gold byte-for-byte |
| `style` | 0.5 | distinct skill (style-preserving refactor of working code) but shares the parent spec + a near-copy module |
| `test_fim` | 0.25 | 3,267 units sharing parent module AND harness text |

These numbers are a starting point, deliberately written down so the first
training run can *change* them on purpose rather than inherit them by
accident. `metadata.family_size` is also emitted so a run can re-weight by
family instead.

---

## 5. The round-trip validator (the actual gate)

`--check` re-derives every row from disk and fails on ANY of:

1. **Split leak** — a family with rows in both splits. (The whole point.)
2. **Shape mismatch** — a row whose `(prompt, completion)` pair does not
   reproduce byte-for-byte from its dir under its declared shape's gold rule
   (§2.1). Catches a `write_test` row exported from `solution.ex`.
3. **Unknown / unmapped shape** — a dir the exporter did not classify.
4. **Excluded data present** — any `repair_*` row.
5. **Empty content** — an empty prompt or gold.
6. **Coverage** — every gradable dir on disk is either exported or explicitly
   excluded; nothing is silently dropped.
7. **Duplicates** — the same task exported more than once (a duplicate
   round-trips cleanly, so without this check it would pass silently).
8. **Metadata drift** — a `sample_weight` that does not match the §4 shape
   mapping, or a `family_size` that does not match the on-disk family count.

`--selfcheck` proves the gate is not vacuous: it plants each violation class
in a copy of the export (a straddling family, a `write_test` row whose
completion is its input module, a `repair_` row, a duplicated row, drifted
weight/family_size metadata) and asserts `--check` catches each one, then
asserts the clean export passes.

CI runs `--selfcheck` then `--check` on every push (cheap: no LLM, no eval).

---

## 5b. Multi-turn repair dialogues (TD.2, docs/13 §2.2 — added 2026-07-19)

The one register single-turn examples cannot teach: **iterative repair** —
receive a spec, produce an attempt, receive a real failure report, fix it.
The generation loop captured exactly this trajectory for every accepted root
that needed repairs; the dialogue export replays it verbatim.

**Source and shape.** The raw chains live in git-ignored `logs/attempts*` —
so the export could never be CI-reproducible from them directly. The minter
(`scripts/mint_dialogues.exs`) therefore promotes each qualifying chain (last
attempt `accepted`, ≥1 earlier `rejected` with a captured `repair_report`)
into a TRACKED `tasks/dialog_<id>/` dir: `prompt.md` (the original spec),
`attempt_NN.code` + `report_NN.txt` per rejected attempt (VERBATIM frozen
evidence — the non-`.ex` extension keeps every formatter and lint off them),
and `solution.ex` + `test_harness.exs` (the accepted pair, canonical — the
dir grades like `:single`, so `validate` re-proves the gold forever). The
exporter derives ONE example per dir into the SAME `train/val.jsonl`:

```
messages: [
  {user:      <the original prompt.md>},
  {assistant: <attempt 0's module, one ```elixir fence>},
  {user:      <attempt 0's captured repair_report, verbatim>},
  …(one assistant/user pair per further rejected attempt)…,
  {assistant: <the ACCEPTED module, one ```elixir fence>}
]
metadata.shape: "repair_dialogue"
```

**Verification at export.** The final (gold) attempt is re-graded green
against the chain's accepted harness before the dialogue is emitted — same
discipline as `mint_repairs`. Earlier attempts and their reports are FROZEN
CAPTURED EVIDENCE (never re-graded, never edited): the report text is the
loop's real feedback, which is the point.

**Loss convention (documented, not enforced here):** the training run should
apply loss to ASSISTANT turns only, and may choose final-turn-only loss; both
are standard. The intermediate assistant turns are real-but-rejected code —
training on them WITH loss teaches the mistake, so final-turn-only is the
recommended default.

**Split and weights.** Dialogues carry the same `family` key as their chain's
root and obey the family-atomic split (a dialogue's text contains its family's
prompt + modules — atomicity contains the leak, as with `adapt`). Advisory
`sample_weight` 1.0: the shape is unique in the corpus and shares text only
within its own family.

**Round-trip.** `dialog_` dirs are frozen, so `--check` re-derives every
dialogue from its dir's files and byte-compares — the same determinism gate
as the single-turn shapes, fully CI-reproducible from the corpus.

## 6. Runbook

```
mix run scripts/export_dataset.exs                 # → results/export/{train,val}.jsonl + report
mix run scripts/export_dataset.exs -- --check      # the gate (CI)
mix run scripts/export_dataset.exs -- --selfcheck  # prove the gate bites (CI)
mix run scripts/export_dataset.exs -- --stats      # split/shape/family census, no writes
```

Output lives in `results/export/` (git-ignored — it is a build artifact,
reproducible from the corpus at any commit; the corpus is the source of
truth, never the export).
