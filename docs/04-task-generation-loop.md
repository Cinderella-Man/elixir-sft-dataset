# 04 — Deterministic Task-Generation Loop (non-agentic, subscription-backed)

Status: **implemented and in production use.** The design below was grilled, prototyped, and
then built in full under `lib/gen_task/**` + `scripts/generate.exs`; it has generated ~150 new
base/variation/FIM tasks across idea groups 065–131. Everything in §4–§16 is live code (module
layout in §16 matches the tree). See the README "Automated generation loop" section for the
day-to-day run commands, and `docs/05-generation-loop-audit.md` for the audit that motivated the
house-style, per-function-mutation, and top-up gates.

A single command walks the idea catalog in `tasks/tasks.md` and, for each base idea, drives
Claude Opus through a **fixed, hardcoded, non-agentic procedure** that authors a complete
task and everything derived from it — the single-file base task, its three variations, and
fill-in-the-middle (FIM) subtasks for every accepted `_01` — grading each with the existing
evaluator, repairing on failure, and gating on **green + house style + a per-function mutation
check** so a vacuous harness or an off-house-style solution can never ship. Every cycle logs to
its own file; failed cycles' logs move to `logs/errors/`.

This automates all three contribution workflows in `README.md` ("How to contribute"):
implement a single-file task, generate variations, generate FIM subtasks.

> This document was refined through grilling passes (`/grill-me`) in which each load-bearing
> mechanism was prototyped against the real code. The **full base cycle was validated
> end-to-end with real `claude -p` calls**: idea #95 (Multi-Currency Money) → generated
> `prompt.md` + harness → solved blind from the prompt → **23/23 green on the first shot,
> score 1.0** → mutation gate killed a gutted solution 23/23. §3 lists all the evidence.

---

## 1. Command & runtime

```bash
mix run scripts/generate.exs            # whole catalog (leave running; see §11 usage-window pause)
mix run scripts/generate.exs 80         # a single base idea (dev/test)
GEN_LIMIT=5 mix run scripts/generate.exs   # first 5 pending ideas
```

- Runs under `mix` so `lib/gen_task/**` is compiled and available.
- **LLM transport = the `claude` CLI as a subprocess** (`claude -p`, single-shot, tools off) so
  calls draw on the user's **Claude Max x5 subscription**, not a pay-per-token API key (§10).
- Each **grade** shells out to `elixir scripts/eval_task.exs …` — a separate OS process, one
  BEAM per grade — identical to `run_all.exs`/CI, and crash/hang-isolated (§12).

---

## 2. Locked decisions (and why)

| # | Decision | Rationale |
|---|---|---|
| Scope | Generate **base + variations + FIM**, all in v1. | User choice — maximum dataset yield per run. |
| Run structure | **Chain everything per idea**: base `_01` → (if accepted) V1/V2/V3 → FIM on every accepted `_01`. | User choice — a fresh base immediately spawns its derivatives in the same run. |
| Backfill | **Also derive from existing `_01`s**: existing reviewed tasks that lack variations/FIM get them, in the same default run. | User choice — maximize coverage of the whole corpus; already-reviewed bases are the safest seeds (no cascade). |
| Accept gate | **Green + house-style + mutation gate**: the reference passes, meets the house style (`@moduledoc`+`@spec`+`@doc`, no TODO, **zero compile warnings**), *and* a raise-mutant of **each public function** makes the harness fail. | With no human review before derivation, these are the signals that prove the code is idiomatic AND actually tested per-function; both the house-style and mutation shortfalls feed the repair step. The house-style/warning gate is skippable (`GEN_SKIP_QUALITY_GATE`); per-function mutation falls back to whole-module (`GEN_SKIP_PER_FN_MUTATION`). |
| Variations | **One call → the missing variations** (path-prefixed `<file>` blocks) → grade/repair each independently → promote the passers into their free slots → **auto-append their idea entries to `tasks.md`**. | Meta-prompt produces a mutually-distinct set; independent grading keeps a partial success shippable; a partial batch is **topped up** on a later run (only the free V-slots are filled); `tasks.md` stays in sync with `tasks/`. |
| FIM targets | **Model picks** candidate functions (bounded per task); FIM **every accepted `_01`** (base + variations), **topped up** to `fim_max_per_task`. | Matches README; the mutation gate auto-rejects under-tested picks; already-covered and permanently-rejected targets are excluded from selection so top-up finds new ones. |
| FIM answer | **Model emits skeleton + function; grading validates** (no brittle Elixir text-surgery). | The eval's `:fim` shape + `Fim.mutate` already prove correctness; offloading text work to the model and gating with grading is more robust than regex surgery. |
| Transport | **`claude -p` CLI subprocess** (single-shot, tools off) on the Max x5 subscription — *not* a raw HTTPS call. | Explicitly reconsidered (user asked "why not a plain HTTPS API call?"): raw `x-api-key` isn't free (pay-per-token) and has no 5-hour window; raw HTTPS + a subscription OAuth token is a ToS gray area and couldn't be verified (extracting the token is blocked); the CLI is the only path that is $0 **and** official **and** auto-refreshes auth **and** preserves the 5-hour window. Subprocess overhead (~1.5s) is negligible vs 10–60s generations. |
| Cost | **No spend cap** — subscription, effectively free. | User runs it on Max x5; cost accounting is irrelevant. |
| Usage window | On subscription-limit exhaustion, **wait and retry every 15 min until the 5-hour window resets**, then continue. | User requirement — leave it running overnight; ride out the limit gracefully. |
| Repair surface | Fixer may edit `solution.ex` **and/or** `test_harness.exs`; **never** `prompt.md`. | The mutation gate makes harness edits safe; `prompt.md` is the task statement and must not drift. |
| Grade sandbox | Separate OS process + `timeout --signal=KILL` wall-clock kill. | Generated code is untrusted and may hang; container/VM is a later hardening. |
| Model | `GEN_MODEL` default `opus` (CLI alias → current Opus). | Follows the subscription's Opus; alias survives CLI version bumps. |

---

> **Safety invariant — existing tasks are never removed or modified.** The loop only *adds*:
> it creates **new** `tasks/…` directories and **appends** (insert-only) entries to `tasks.md`.
> It never deletes, overwrites, or edits any existing task's files.
> - **Done-detection skips** any idea/variation/FIM that already exists (§5), so an existing
>   task is never regenerated.
> - **Promotion refuses to write** if the target `tasks/<id>` already exists — a belt-and-
>   suspenders guard beyond done-detection; it logs-and-skips rather than clobber.
> - **Backfill reads** existing `_01` triplets as context but never writes to them.
> - Every destructive op (`File.rm_rf`, `File.rename!`) targets only `.gen_staging/`, `logs/`,
>   or the OS temp dir — **never `tasks/`**.
> - `tasks.md` edits are **insert-only + idempotent**, and the file is **git-tracked**, so every
>   change is visible in the diff and reversible.

## 3. What was prototyped (evidence)

Every mechanism below was run against the real code during planning:

| Claim | Evidence |
|---|---|
| **END-TO-END base cycle (real `claude -p`, first shot):** idea #95 → Step A generated `prompt.md` + a `MoneyTest` harness (pure `<file>` output, contract followed, `async:false`, no `ExUnit.start`, no fences; 77s) → Step B solved blind from `prompt.md` → `solution.ex` (16s) → graded **23/23 pass, compiled, score 1.0** (no repair) → mutation gate: gutted solution → **23/23 fail**. The full green+mutation accept gate passed. | 2 real `claude -p` calls + grade + `Fim.mutate` + grade. |
| `tasks.md` = **557 base ideas** + 48 variations + 127 section headers; **53 base done / 504 todo**; no dup idea numbers. | Prototype parser over `tasks/tasks.md`. |
| Done-detection: base idea `N` done iff `tasks/{pad3 N}_001_*_01/` exists. | Prototype vs existing dirs. |
| Model output parsed via the repo's own `<file path="…">` convention + `EvalTask.Bundle.parse/1`; prose outside blocks ignored; a fix reply may carry a subset. | Prototype fed mock replies. |
| **Markdown-fence hazard**: models wrap `<file>` bodies in ```` ```elixir ````; the fence lands in the file and breaks compilation. A `sanitize_file_body/1` (strip a wrapping ```` ```lang ````/```` ``` ```` pair) fixes it, is a no-op on clean bodies, and recovers a whole-reply-in-one-fence case. | Prototype (§7). |
| Grade bridge: staging dir **outside** `tasks/` grades correctly (exit 0, `shape:single`, `10/10`, `score 1.0`). | Prototype (copied task 001 into `.gen_staging/…`, graded). |
| **Grade exit-code rule**: `timeout --signal=KILL` exits **137** (not 124); a hung ExUnit test is killed at the deadline and produces **0 JSON lines**. Rule: **exit 0 ⇒ parse JSON (compile-fail and test-fail both exit 0); else ⇒ timeout/crash** — no magic number. | Prototype (`timeout … elixir scripts/eval_task.exs` on an infinite-loop harness). |
| **Base mutation gate**: `EvalTask.Fim.mutate/1` on a whole module → every body `raise`s → the real harness → **10/10 fail**. Distinguishes a genuine harness from a vacuous one. | Prototype (§13). |
| **FIM accept-path**: reconstruct original candidate → parent harness **10/10 pass**; reconstruct a candidate-mutant → parent harness **10/10 fail**. `eval_task.exs <fim_dir> <alt_solution>` accepts an override solution path. | Prototype (§13). |
| Per-cycle `:logger_std_h` file handler captures info→error verbatim under real `mix run`; `filesync`+`File.rename!` to errors works; a fresh handler per cycle isolates cycles; `Logger.Formatter.new/1` exists in 1.19. It **also** mirrors to console → progress must use `IO.puts` and the console handler level must be raised. | Prototype (§14). |
| **`claude -p` transport**: `printf … \| claude -p --output-format json --model opus --max-turns 1 --allowedTools ""` runs headless, non-agentic, via **stdin**; exit 0; JSON has `type/subtype/is_error/result/api_error_status/stop_reason/usage/modelUsage/total_cost_usd/num_turns`; `.result` is the model's text. | Prototype (minimal real call). |
| **Harness invariant**: 0/122 corpus harnesses call `ExUnit.start()` (the runner does, `autorun:false`); a stray `ExUnit.start()` in a harness still grades 10/10 (harmless). So the contract must not *require* it; harnesses `use ExUnit.Case` (recommend `async:false`). | grep + grade of task 001 harness with a prepended `ExUnit.start()`. |
| **`tasks.md` insertion** (variation entries): inserting `### Task N - Vn - …` after the last existing block for idea N and before the next base idea/section is correctly placed (V4 lands after V3, before idea 2), **idempotent** (re-insert → `already_present`), and never duplicates. | Prototype on a copy of `tasks.md`. |
| `claude -p` supports a **full `--system-prompt` override** and `--setting-sources`/`--strict-mcp-config`/`--no-session-persistence` to run without CLAUDE.md/skills/MCP context. | `claude --help`. |
| Runtime: Elixir 1.19.5 / OTP 28; `claude` CLI 2.1.197 present; `req`/`jason` deps present. **No `ANTHROPIC_API_KEY`, no `ant` CLI** (subscription auth is via the `claude` login). | Env checks. |

---

## 4. The chained pipeline

**The run has two work-lists, processed in order:**

1. **New bases** — every *todo* base idea (no `tasks/NNN_001_*_01` yet): generate the base, then
   chain its variations + FIM (the diagram below).
2. **Backfill** — every *existing accepted* `_01` (hand-authored base or variation) that lacks
   derivatives: run just the missing steps — variations for a base with none, FIM for any `_01`
   with none. Existing tasks are taken **as-is as seeds** (their own triplet is the context);
   only the *generated derivatives* pass the accept gate. If an existing seed's own harness
   can't kill a mutant, that's logged as a warning but does not block deriving from it.
   (`GEN_SKIP_BACKFILL=1` runs only work-list 1; `GEN_ONLY=backfill` runs only work-list 2.)

Both work-lists feed the same per-task cycle (§6) and per-derivative generators (§9, §10).

```
for each pending base idea (file order; skip if tasks/NNN_001_*_01 exists):

  ┌─ BASE ────────────────────────────────────────────────────────────────┐
  │ CycleLog.open("NNN_001_slug_01")                                        │
  │ A. gen task    claude -p → <file prompt.md> + <file test_harness.exs>   │
  │ B. gen answer  claude -p (prompt.md ONLY) → <file solution.ex>          │
  │ C. accept?     green AND house-style/0-warnings AND per-fn mutant fails │
  │ D. repair loop while !accepted and attempts<max: feed report → regrade  │
  │ E. accepted?   promote → tasks/NNN_001_slug_01/    else → logs/errors/  │
  └────────────────────────────────────────────────────────────────────────┘
              │ accepted
              ▼
  ┌─ VARIATIONS (needs base _01 triplet; only the FREE V-slots) ────────────┐
  │ one claude -p call → v1/…../vK/… triplets + K tasks.md entries (K≤3)     │
  │ for each v:  run the SAME task cycle (green+house-style+per-fn mutation) │
  │   accepted → promote → tasks/NNN_00{free slot}_slug_01/                 │
  │             + insert "### Task N - Vn - …" into tasks.md (idempotent)   │
  │   else     → logs/errors/                                               │
  └────────────────────────────────────────────────────────────────────────┘
              │
              ▼
  ┌─ FIM (for every accepted _01: the base + each accepted variation) ──────┐
  │ claude -p → list of candidate functions (bounded by GEN_FIM_MAX_PER_TASK)│
  │ for each candidate:                                                      │
  │   claude -p → <file prompt.md(skeleton+desc)> + <file solution.ex(fn)>  │
  │   accept? grade via :fim (parent harness passes) AND candidate-mutant   │
  │            makes parent harness fail;  repair fn/skeleton up to max      │
  │   accepted → promote → tasks/NNN_00b_slug_0d/   else → logs/errors/     │
  └────────────────────────────────────────────────────────────────────────┘
```

Cascade rules: a base that isn't accepted spawns **no** derivatives. A failed variation goes
to `logs/errors/` and does not block its siblings. FIM runs only against accepted `_01`s.

Numbering (confirmed against the corpus): base = `_001_` (`b=1`); variation **Vn → `b = n+1`**
(V1→`_002`, V2→`_003`, V3→`_004`); FIM subtasks are `_02+` (`d≥2`) under each `_01`.

---

## 5. Idea catalog (`GenTask.Catalog`)

Parsing rules (prototyped):

- **Base idea** = `^### (\d+)\. (.+)$`. **Variation** = `^### Task (\d+) - (V\d+) - (.+)$`.
  Any other `###`/`##` line is a **section header** → not an idea (terminates the previous
  idea's description, starts nothing). Order = file order (deterministic).
- `%GenTask.Idea{num, name, desc, slug, task_id, done?}` where
  `slug = name |> downcase |> replace(~r/[^a-z0-9]+/, "_") |> trim("_")` (cosmetic — the eval
  resolves dirs by numeric prefix; module names come from the generated `prompt.md`),
  `task_id = "#{pad3(num)}_001_#{slug}_01"`, `done? = File.dir?` of any `tasks/#{pad3(num)}_001_*_01`.

Done-detection is the durable, idempotent skip: a failed cycle leaves no `tasks/` dir, so a
re-run cleanly retries it. Enumeration (both work-lists of §4):

- **New base** — a base idea with no `tasks/NNN_001_*_01`.
- **Variations** (for an accepted base `_01`) — triggered when the base has **fewer than 3**
  variations (`count_variations/2` counts `NNN_00{2,3,4}_*_01`). A partial batch is **topped up**:
  the generator requests only the missing count, fills the free V-slots, and is given the names of
  the existing variations so the new ones stay distinct.
- **FIM** (for any accepted `_01`, base or variation) — triggered when that `_01` has **fewer than
  `fim_max_per_task`** FIM subtasks (`count_fim/3`). Candidate selection excludes functions already
  covered by an existing `_0d` and targets permanently rejected on a prior run (§10), so a top-up
  run produces new subtasks rather than duplicates.

---

## 6. The shared task cycle (`GenTask.Cycle`)

Base tasks and each variation are full tasks and flow through one scaffold. FIM reuses the
same skeleton with a different grade target (§10).

```elixir
# accepted := green AND house-style AND every public-fn mutant fails
def run_task_cycle(files, ctx, cfg) do          # files: %{"prompt.md"=>, "test_harness.exs"=>, "solution.ex"=>}
  stage!(dir, sanitize(files))
  Enum.reduce_while(0..cfg.max_retries, {files, nil}, fn attempt, {files, _} ->
    grade  = Evaluator.grade(dir, cfg)                       # §12
    result = accept?(grade, dir, cfg)                        # green → house-style (§12) → per-fn mutation (§13)
    cond do
      result == :accept          -> {:halt, {:ok, files, grade}}
      attempt == cfg.max_retries -> {:halt, {:error, files, grade}}
      true ->
        report = Evaluator.repair_report(result)             # compile/test | quality shortfall | vacuous fn | timeout
        upd    = Opus.fix(files, report, cfg) |> sanitize()  # returns changed subset (solution.ex and/or test_harness.exs)
        files  = Map.merge(files, upd)
        {:cont, {files, grade}}
    end
  end)
end
```

- **Accept** applies three gates in cheap-first order so a failure short-circuits before the
  expensive per-function mutation grades: (1) **green**; (2) **house-style / zero-warning** — a
  green solution missing `@moduledoc`/`@spec`/`@doc`, carrying a `TODO`, or compiling with warnings
  is rejected `{:quality, "…"}` so the fixer adds them (skip with `GEN_SKIP_QUALITY_GATE`); (3)
  **mutation**, which mutates **each public function** independently — if any function's raise-mutant
  still passes, that function is untested and the report names it `{:vacuous, "…covers foo/2…"}`,
  which is exactly when a harness edit is warranted (skip with `GEN_SKIP_PER_FN_MUTATION` to fall
  back to a single whole-module mutant).
- **Repair surface**: `solution.ex` and/or `test_harness.exs`; a fix that returns `prompt.md`
  is rejected by the contract validator.
- **Solver blindness** is preserved only at generation (Step B sees `prompt.md` only); the
  fixer sees everything (it is the debug step).

---

## 7. Output contract, parsing & sanitizing (`GenTask.Reply`)

Every `claude -p` call ends with the shared contract:

```
Return your answer as one or more file blocks and NOTHING ELSE — no prose, no markdown
fences around the blocks. Each file must be exactly:

<file path="RELATIVE/PATH">
…verbatim file contents…
</file>

Emit only the files listed above.
```

- `parse(text)` = `EvalTask.Bundle.parse(text) |> Map.new()` → `%{path => body}`.
- **`sanitize_file_body/1`** (proven necessary): strip a wrapping ```` ```lang ````/```` ``` ````
  pair from each body — models add fences even when told not to, and the fence would otherwise
  be written into the `.ex`/`.exs` file and break compilation. No-op on already-clean bodies.
- Per-step contract validation:
  - task → `prompt.md` + `test_harness.exs`, non-empty; harness defines a `defmodule …Test`
    with `use ExUnit.Case` (**not** `ExUnit.start` — 0/122 corpus harnesses call it; the
    evaluator's `Runner.run_harness` already does `ExUnit.start(autorun: false)`, and a stray
    call in the harness is harmless — verified);
  - answer → non-empty `solution.ex` with `defmodule`;
  - fix → ≥1 of `{solution.ex, test_harness.exs}`, no `prompt.md`;
  - variations → `v{1,2,3}/{prompt.md,test_harness.exs,solution.ex}` (path-prefixed) + 3 idea entries;
  - FIM → `prompt.md` (with a ```` ```elixir ```` skeleton containing a `# TODO`) + `solution.ex`.
- A contract violation consumes one attempt and re-prompts with a "return ONLY `<file>` blocks"
  reminder (rather than crashing).

---

## 8. Base generator (`GenTask.Base`)

- **Step A (task):** system = the SFT-authoring persona (from `tasks/single_shot_prompt.md`);
  user = the idea block (`### N. Name` + description) + the example `prompt.md` and
  `test_harness.exs` from `tasks/001_001_rate_limiter_01/` + the contract requesting
  `prompt.md` and `test_harness.exs`.
  - **Harness requirements stated in the prompt** (from the corpus invariants): define a
    `<Module>Test` using `use ExUnit.Case, async: false`; **do not call `ExUnit.start()`** (the
    evaluator starts ExUnit); the harness is self-contained and may define fakes/clock Agents
    inline (as task 001 does); it runs as `elixir test_harness.exs` beside a `solution.ex`;
    compiles with **zero warnings** (`_`-prefix unused vars, match `+0.0`/`-0.0`); and makes any
    **temp-file path process-unique** (`…_#{System.pid()}_#{System.unique_integer([:positive])}…`)
    since the corpus is graded with many harnesses in parallel — a per-BEAM-only unique name
    collides across processes and flakes.
- **Step B (answer):** user = the generated `prompt.md` **verbatim and nothing else** (no
  tests — README Step 5) + the contract requesting `solution.ex`.
- Then the shared cycle (§6).

---

## 9. Variation generator (`GenTask.Variations`)

- Runs for an **accepted** base `_01` that lacks some variations. `run/2` first computes the
  **free V-slots** (of `_002`/`_003`/`_004`) from disk; if all three exist it returns `[]`.
  One `claude -p` call, seeded from `tasks/variation_prompt.md`, inlining the base `_01` triplet,
  the full `tasks.md`, **and the display names of any existing variations** (so a top-up stays
  distinct), requests exactly the missing count. Output contract: path-prefixed triplets
  `v1/…`..`vK/…` **plus** a `### Task N - Vn - Name` idea entry each (`vN/idea.md`).
- Each variation is materialized to its own staging dir and run through the **shared task cycle**
  (§6) independently — green + house-style + per-function mutation + repair. Partial success is
  fine; the missing slots are filled on a later run (§5 top-up).
- **Promotion of an accepted variation** = write `tasks/NNN_00{slot}_slug_01/` (`slot` = the free
  b-index it was assigned, so the catalog label is `V{slot-1}`) **and** insert its idea entry into
  `tasks.md`, immediately after the base idea's block, guarded so a re-run never double-inserts
  (skip if `### Task N - Vn -` already present). `tasks.md` is git-tracked, so every insertion
  shows up in the diff for review.
- **Live-run read/write model** (`tasks.md` is both read and mutated during a run):
  - **Enumeration** (which ideas are work) uses the **in-memory catalog snapshot taken at
    start**, so newly-inserted `### Task N - Vn` entries are never mis-read as new base ideas
    (they aren't base-idea shaped anyway) and the work-list is stable for the whole run.
  - The **variation-distinctness context** ("1000+ ideas to not repeat") inlines a **fresh
    on-disk read** of `tasks.md` per variation call, so each new set avoids repeating variations
    added earlier in the same run.
  - The loop is **sequential** (§14), so there are no concurrent writers; each insertion is a
    read-modify-write of the file with the idempotent guard above.

---

## 10. FIM generator (`GenTask.Fim`)

- Runs for **every accepted `_01`** (base + accepted variations) with **fewer than
  `fim_max_per_task`** FIM subtasks. No text-surgery — grading is the guardrail.
- **Top-up cap:** a run requests only `fim_max_per_task - existing_fim_count` candidates, so a
  partially-derived `_01` (backfill) fills only the missing subtasks rather than another full
  batch — the total per `_01` never exceeds the cap.
- **Candidate selection:** one `claude -p` call ("which functions/clauses are the best
  fill-in-the-middle targets for this module?") returns a list, truncated to the top-up cap
  above. The call is told to **exclude** functions already covered by
  an existing `_0d` (their target is parsed from the `_0d` `solution.ex`) and targets permanently
  rejected on a prior run (`logs/fim_rejected.jsonl`); the same exclusions are re-applied to the
  parsed list, so a top-up run selects genuinely new targets.
- **Per candidate:** one `claude -p` call (from `tasks/fill_in_the_middle_prompt.md`) returns
  `prompt.md` (a natural-language description **plus** the whole module inside a ```` ```elixir ````
  fence with that one function's body replaced by `# TODO`) and `solution.ex` (just that
  function). Both parsed + sanitized.
- **Accept** = grade via the eval's `:fim` shape (`Fim.reconstruct` + parent `_01` harness)
  **passes**, AND a `Fim.mutate` of the candidate makes the parent harness **fail** (proving
  the target is actually exercised — the `validate.exs --fim-only` gate).
  - Original fails → skeleton/function is off → repair (regenerate) up to max, else errors.
  - Mutant passes → the parent harness doesn't test this function → **reject the candidate**
    (unfixable here — we may not edit the parent `_01` harness); the target is appended to
    `logs/fim_rejected.jsonl` so it is never re-selected, and the next candidate is tried.
- **Promote** an accepted candidate → `tasks/NNN_00b_slug_0d/` (`d` = next free subtask index,
  advanced only on a promotion so `_0d` dirs stay gap-free). Each attempted candidate logs under a
  distinct id (`…_fimNN`) so distinct rejects never overwrite each other's cycle log.

---

## 11. The non-agentic LLM transport (`GenTask.Opus` → `claude -p`)

Calls go through the `claude` CLI so they draw on the **Max x5 subscription**.

**Why the CLI and not a raw HTTPS call?** A plain `POST /v1/messages` is only "free" with a
**subscription** bearer token, not an `x-api-key` (which is pay-per-token and has no 5-hour
window). Using the subscription's OAuth token against the raw REST API is a ToS gray area —
this machine's own guardrails *blocked* extracting that token for a test — and its acceptance
by `/v1/messages` is unverified. The `claude` CLI is the only path that is simultaneously $0,
officially supported, auto-refreshing, and 5-hour-window-aware. This was chosen deliberately
over a raw HTTPS call. (`--max-turns 1 --allowedTools ""` makes each call a single completion
with no tools, so it behaves exactly like a one-shot text API call.)

**Invocation** (prompt via **stdin** — big prompts exceed argv limits):

```elixir
# system prompt → a temp file (--system-prompt-file avoids argv/shell quoting for a large
# prompt); user prompt (idea/context + contract) → stdin. This exact flag set was exercised
# end-to-end successfully (§3 headline row).
System.cmd("claude",
  ["-p", "--output-format", "json", "--model", cfg.model,
   "--max-turns", "1", "--allowedTools", "",   # non-agentic: one turn, no tools/file access
   "--system-prompt-file", sys_path,            # FULL override of Claude Code's agentic default
   "--setting-sources", "",                     # skip CLAUDE.md / skills / local-settings discovery
   "--strict-mcp-config",                       # no MCP servers (none supplied)
   "--no-session-persistence"],                 # don't write session files
  # feed the user prompt on stdin (Port with the prompt written to the port, or bash `< file`)
  ... )
```

- **Non-agentic guard:** `--allowedTools ""` ⇒ no tools and no file access — pure text-in/text-out,
  and `--max-turns 1` ⇒ one completion per call (single-shot). **Fixed 2026-07-02** (was `--max-turns 20`,
  audit finding #9): 20 turns let the model occasionally engage the CLI's agentic loop and burn all
  turns → `error_max_turns`, which `GenTask.Opus` retries 5× with backoff (~15 min stall). One turn
  fast-fails that case; the transient-retry then gets a clean single-shot reply.
- **Clean, reproducible context** (flags exercised end-to-end, §3): `--system-prompt-file`
  **replaces** Claude Code's default agentic system prompt with *only* our SFT-authoring persona
  (better than `--append-system-prompt`, which keeps CC's default; a file avoids argv/shell
  quoting for a large prompt); `--setting-sources ""` (**accepted** — the verified run used it)
  skips CLAUDE.md/skills/hooks/local-settings auto-discovery; `--strict-mcp-config` (with no
  `--mcp-config`) means no MCP; `--no-session-persistence` avoids session-file clutter. So
  generation isn't polluted by the user's `~/.claude/CLAUDE.md`, project skills, or MCP.
- **Auth hygiene:** ensure `ANTHROPIC_API_KEY` is **unset** in the child env so the CLI uses the
  subscription login, not a pay-per-token key. (Verified: none is set today.)
- **Parse:** decode stdout JSON; the model's text is `.result`. Record `.usage`/`.modelUsage`
  (+ `.total_cost_usd`, informational only) for the ledger. `.stop_reason` for truncation/refusal.

**Result classification** (drives control flow):

| Signal | Meaning | Action |
|---|---|---|
| exit 0, `is_error:false`, `subtype:"success"` | normal | parse `.result` → `<file>` blocks |
| `is_error:true` AND (`api_error_status == 429` OR `.result`/`.subtype` matches `/usage limit\|rate.?limit\|limit reached\|quota (exceeded\|reached)\|too many requests/i`) | **subscription window exhausted** | **usage-window pause** (below) |
| `is_error:true`, transient (network / 5xx / overloaded) | transient | short exponential backoff, few retries |
| `stop_reason:"max_tokens"` | truncated | never parse; retry with reminder / higher cap |
| refusal / other content error | model declined | cycle-level: skip idea / send to errors |

**Usage-window pause (user requirement):** on a usage-limit signal, log
`"usage limit reached — waiting 15m (attempt K)"`, sleep `GEN_USAGE_WAIT_MS` (default
**15 min**), and **retry the same call**; loop until it succeeds, then continue exactly where
it paused. The pause happens at the single call site, so the current idea/cycle stays
resumable. This is distinct from the short transient backoff.

> **Cap (bug-fix):** the retry loop is **bounded** by `GEN_USAGE_MAX_WAIT_MS` (default **6 h**) —
> once the cumulative usage-wait would exceed it, the call returns `{:error, {:usage_limit,
> :exhausted}}` instead of sleeping forever. The 6 h cap covers a full 5-hour window reset while
> ensuring a *misclassified* persistent transient error can never hang the whole run. The
> detection regex was also tightened to strong usage phrases only (dropping bare `try again` /
> `resets at`, which appear in generic 5xx/gateway bodies) so a transient is never read as a
> usage limit in the first place.

> **Residual unknown:** the exact usage-limit message/subtype from `claude -p` couldn't be
> triggered during planning (no way to exhaust the window on demand). Detection is therefore
> defensive (status 429 **or** a message/subtype regex **or** a non-zero exit that isn't a
> clean content result). This is the one thing to confirm against a real limit event and tune.

---

## 12. Grading bridge (`GenTask.Evaluator`)

- `stage!(dir, files)` writes the triplet into a git-ignored staging dir (default
  `.gen_staging/<task_id>/`) — outside `tasks/` so `Discovery`/`run_all`/`validate` never see
  in-flight artifacts.
- `grade(dir, cfg)` runs the canonical evaluator in a separate OS process under a wall-clock
  kill:

  ```elixir
  case System.cmd("timeout", ["--signal=KILL", to_string(cfg.eval_timeout_s),
                              "elixir", "scripts/eval_task.exs", dir, "solution.ex"]) do
    {out, 0} -> {:ok, out |> last_json_line() |> Jason.decode!()}   # compile-fail & test-fail also exit 0
    {_,   _} -> {:timeout_or_crash}                                 # killed (137) ⇒ no JSON line
  end
  ```

  `eval_timeout_s` default **120**. `last_json_line/1` = the last `{`-prefixed stdout line
  (mirrors `run_all.exs`). No 124/137 matching — non-zero simply means "no usable JSON."
- For FIM, grade the `_0d` dir (the eval auto-detects `:fim`, reconstructs, runs the parent
  harness); the mutation-gate grade passes an **override solution path** (verified supported).
- `green?(json)` = `compiled and tests_total>0 and tests_failed==0 and tests_errors==0`.
- `quality_shortfall(json)` = `nil` when a green base/variation meets the house style, else a
  `; `-joined description of what's missing (compile warnings, `@moduledoc`/`@spec`/`@doc`, TODO)
  — drives the `{:quality, …}` reject/repair.
- `repair_report(reason)` handles `:timeout_or_crash`, `{:failed, grade}` (compile errors *or*
  test failures `test`/`module`/`message`), `{:quality, shortfall}` (house-style/warnings), and
  `{:vacuous, why}` (the named public function the harness fails to exercise).

---

## 13. Mutation gate (`GenTask.Mutation`)

AST prewalk that replaces a `def`/`defp` body with `raise` — for the whole module (`mutate/1`)
or for one named function (`mutate_fn/3`).

- **Base / variation** — **per-function by default** (`GEN_SKIP_PER_FN_MUTATION` reverts to
  whole-module): `public_functions/1` lists every public `def` (name/arity); for each,
  `mutate_fn/3` guts just that function, stages it with the same harness, and grades — **every**
  such mutant **must fail**. The first survivor names an untested public function → `{:survived,
  "…covers foo/2…"}` → repair the harness. This closes the whole-module hole where asserting one
  of N functions passed the gate. Falls back to a single whole-module `mutate/1` when no public
  function parses (or when disabled).
- **FIM** (candidate function): `EvalTask.Fim.mutate/1` of the candidate → grade the `_0d` dir with
  the mutant as the override solution → parent harness **must fail**. If it passes, reject the
  candidate (the parent harness doesn't cover it) — and record it in `logs/fim_rejected.jsonl`.

The mutant is graded then discarded — its reformatting (via `Macro.to_string`) doesn't matter.

---

## 14. Logging (`GenTask.CycleLog`, modeled on the reference `Tunex.RowLog`)

**Per-cycle text log — `logs/<task_id>.log`** (one file per generated task — base, each
variation, each FIM candidate):

- `open(task_id)` → `File.write!(path,"")` then attach a **fresh** single global `:logger_std_h`
  handler at `:debug`, formatter `"$time [$level] $message\n"` (verified in 1.19). A fresh
  handler per cycle (remove-then-add) because `logger_std_h` won't change a live file.
- Everything is logged via `Logger.*` in the step functions: each `claude -p` call (model, the
  **full system + user prompt**, elapsed, `.usage`, `stop_reason`, and the **full `.result`
  text**); parse + contract + sanitize results; the exact eval command + **full eval JSON**;
  the mutation-gate result; each repair attempt with the report fed back; promotion/rejection;
  any exception + stacktrace.
- `close(outcome)` → `:logger_std_h.filesync/1`, `remove_handler`, then **success ⇒ leave in
  `logs/`; failure/error ⇒ `File.rename!` to `logs/errors/<task_id>.log`** (the exact requested
  behavior).
- **Console hygiene** (from the prototype: the file handler also mirrors to console): raise the
  default console handler's level (e.g. `:warning`) so full prompts/responses land only in the
  file; **terminal progress uses `IO.puts`** (like `run_all.exs`), not `Logger`.
- **Sequential loop** — the file handler is one global, so cycles run one at a time
  (deterministic; parallelism would need per-process handles — out of scope).

**JSONL ledgers** (append + fsync-per-line via `:file.open(…, [:append,:raw,:binary])`):

- `logs/runs.jsonl` — one line per generated task: `{id, kind: base|variation|fim, num, name,
  ts, outcome, attempts, compiled, tests_passed, tests_failed, tests_total, mutant_failed,
  elapsed_s, tokens_in, tokens_out}`.
- `logs/usage.jsonl` — one line per `claude -p` call: `{id, step, model, in_tokens, out_tokens,
  stop_reason, cost_usd, elapsed_ms, ts}`.
- `logs/waits.jsonl` — one line per usage-window pause: `{ts, waited_ms, attempt, signal}`.
- `logs/fim_rejected.jsonl` — one line per permanently-rejected FIM target `{ts, prefix, target}`
  (the parent harness does not exercise it); consulted by candidate selection to never re-attempt
  it (§10).

**Terminal** — one line per task, `run_all`-style:
`[  7/504] 065_001_saga_coordinator_01 (base) … ACCEPTED (17 passed, mutant killed, 2 attempts)`.

**Resume** — primary skip = existing `tasks/` dir (base/variation/FIM); failed items sit in
`logs/errors/` and are re-attempted only under `GEN_RETRY_FAILED=1`. A killed run resumes by
re-scanning (JSONL is fsynced; no partial `tasks/` dirs are ever left).

---

## 15. Configuration (`GenTask.Config`, env + a few CLI positionals)

| Knob | Env | Default | Meaning |
|---|---|---|---|
| Model | `GEN_MODEL` | `opus` | `claude --model` alias/id |
| Repair retries | `GEN_MAX_RETRIES` | `3` | fix iterations per task (base/variation/FIM) |
| FIM targets/task | `GEN_FIM_MAX_PER_TASK` | `3` | cap on candidate functions per `_01` |
| tfim targets/task | `GEN_TFIM_MAX_PER_TASK` | `3` | cap on test-FIM subtasks per `_01` (see `docs/06`) |
| Eval timeout | `GEN_EVAL_TIMEOUT_S` | `120` | wall-clock kill for a hung grade |
| Call timeout | `GEN_CALL_TIMEOUT_S` | `900` | wall-clock kill for a single `claude -p` |
| Usage-window wait | `GEN_USAGE_WAIT_MS` | `900000` | sleep between retries while limited (15 min) |
| Usage-wait cap | `GEN_USAGE_MAX_WAIT_MS` | `21600000` | give up after this cumulative usage-wait (6 h) — stops a misclassified transient from hanging the run |
| Transient retries | `GEN_TRANSIENT_RETRIES` | `5` | short-backoff retries for network/5xx |
| Quality gate | `GEN_SKIP_QUALITY_GATE` | `0` | when unset, a green base/variation must ALSO have `@moduledoc`+`@spec`+`@doc`, no TODO, and **zero compile warnings** — else it is repaired, then rejected (§13) |
| Per-fn mutation | `GEN_SKIP_PER_FN_MUTATION` | `0` | when unset, the base/variation mutation gate mutates **each public function** independently and requires every one killed (§13), not just a whole-module mutant |
| Batch limit | `GEN_LIMIT` | `∞` | at most N base ideas this run |
| Range / single | `GEN_FROM`/`GEN_TO`, positional arg | — | restrict idea numbers; positional = one idea |
| Retry failed | `GEN_RETRY_FAILED` | `0` | re-attempt items in `logs/errors/` |
| Skip variations/FIM | `GEN_SKIP_VARIATIONS`, `GEN_SKIP_FIM` | `0` | run only part of the chain |
| Skip wtest/tfim | `GEN_SKIP_WRITE_TEST`, `GEN_SKIP_TEST_FIM` | `0` | skip the deterministic derived kinds (`docs/06`) |
| Backfill control | `GEN_SKIP_BACKFILL` / `GEN_ONLY` | `0` / — | skip work-list 2; or `GEN_ONLY=backfill`/`bases` to run one work-list (§4) |
| Reconcile catalog | `GEN_RECONCILE` | `1` (on; `GEN_RECONCILE=0` disables — flipped in docs/09 §13) | before running, insert a `tasks.md` entry for any variation dir missing one (heals crash-orphans / pre-Finding-E losses). Insert-only + idempotent; skipped in dry-run; done-detection is dir-based, so the loop is correct either way |
| Dry run | `GEN_DRY_RUN` | `0` | do everything except promotion / `tasks.md` edits |

No spend cap — subscription. `ANTHROPIC_API_KEY` must be **unset** (auth hygiene).

---

## 16. Module layout

```
lib/gen_task/
  cli.ex          # GenTask.CLI.main/1 — parse args/env, load catalog, drive the chained loop, terminal status
  config.ex       # env + flag resolution (§15)
  catalog.ex      # parse tasks.md → [%Idea{}]; slug; task_id; done?; count_variations/count_fim (top-up); tasks.md insertion (§5, §9)
  opus.ex         # claude -p subprocess; result classification; capped usage-window pause; text/usage extract (§11)
  reply.ex        # parse <file> blocks (EvalTask.Bundle.parse) + sanitize_file_body + per-step contract (§7)
  cycle.ex        # shared task cycle: stage → grade → accept(green → house-style → per-fn mutation) → repair (§6)
  evaluator.ex    # timeout-wrapped eval_task.exs, decode, green?, quality_shortfall, repair_report (§12)
  mutation.ex     # public_functions/all_functions + mutate/mutate_fn(+:defp) + base/FIM/isolation gates (§13, docs/06)
  base.ex         # base generator (§8)
  variations.ex   # missing-slot generation, split, per-variation cycle, tasks.md insert (§9)
  fim.ex          # candidate selection (excl. covered/rejected), per-candidate generation, FIM accept via :fim + mutation (§10)
  write_test.ex   # wtest generator — deterministic repackage of an _01 into wt_<slug>/ (docs/06)
  test_fim.ex     # tfim generator — carve top-level `test` blocks, isolation-kill gate, tfim_<slug>_0d/ (docs/06)
  cycle_log.ex    # RowLog-equivalent handler + move-to-errors + JSONL ledgers (+ fim_rejected) + console hygiene (§14)
scripts/generate.exs   # thin entry: GenTask.CLI.main(System.argv())
```

Runs under `mix run`; shells `elixir scripts/eval_task.exs …` per grade (that script prepends
`_build/*/lib/*/ebin`, so deps resolve as they do for `run_all.exs`).

---

## 17. Failure modes & mitigations

| Failure | Handling |
|---|---|
| Subscription window exhausted | usage-window pause: log, sleep 15 min, retry same call — **capped** at `GEN_USAGE_MAX_WAIT_MS` (6 h) so a misclassified transient can't hang the run (§11) |
| Model wraps files in ```` ``` ```` fences | `sanitize_file_body/1` strips them (§7) |
| Model ignores `<file>` contract | contract-validation catch → re-prompt reminder (consumes an attempt) |
| Truncated reply (`max_tokens`) | not parsed; retry with reminder / higher cap |
| Refusal / content error | log; skip idea (base) or send candidate/variation to errors |
| Generated code hangs the grade | `timeout --signal=KILL` → no JSON → treated as failed grade; report "timed out"; repair |
| Off-house-style solution (no docs/spec, warnings, TODO) | quality gate rejects `{:quality, …}` → repair adds them, else errors (`GEN_SKIP_QUALITY_GATE` to disable) (§6) |
| Vacuous / weak generated harness | per-function mutation gate rejects (a function's mutant passes) → repair the harness to cover it, else errors (blocks derivation) (§13) |
| Buggy generated harness | repair may edit `test_harness.exs` (safe: mutation gate still applies) |
| Base rejected | no variations/FIM spawned for it |
| Variation rejected | to errors; siblings unaffected; no `tasks.md` entry inserted; free slot retried on a later run (§5) |
| FIM candidate untested by parent harness | mutant passes → reject candidate + record in `logs/fim_rejected.jsonl` (never re-selected); try next |
| `tasks.md` double-insert on re-run | idempotent guard (skip if entry already present) |
| A cycle raises | rescued; log + stacktrace; move to `logs/errors/`; loop continues |
| Interrupted run | resume by re-scanning `tasks/`; no partial dirs; JSONL fsynced |
| Variation dir orphaned (crash between promote and `tasks.md` insert) | harmless to the loop (done-detection is dir-based, so backfill still counts it); `GEN_RECONCILE=1` inserts the missing catalog entry when desired (§15) |

**Post-run:** optionally finish by invoking `elixir scripts/validate.exs` (reference-green +
FIM-mutation gate across the whole corpus) to catch any cross-task regressions.

---

## 18. Testing the generator

- **Unit tests** (`test/gen_task/…`): catalog parsing (base/variation/section) + **count-based
  top-up** enumeration, reply parse + `sanitize_file_body` (fence cases) + per-step contract,
  `green?`, `quality_shortfall`, `repair_report`, `tasks.md` insertion (idempotency), result
  classification + the **usage-wait cap** (`try again` ⇒ transient, not usage), and per-function
  mutation (`public_functions`/`mutate_fn`) over canned `claude -p` JSON fixtures.
- **`GEN_DRY_RUN`**: full wiring (generate → parse → grade → mutation → repair) with **no**
  promotion / `tasks.md` edits — safe iteration without touching `tasks/`.
- **Single-idea mode** (`mix run scripts/generate.exs 80`): end-to-end on one idea before a
  batch run.

---

## 19. Open items

All major decisions are resolved (§2). Remaining recommendations, adopted unless changed:

1. **Repair surface** = `solution.ex` + `test_harness.exs` (not `prompt.md`) — accepted.
2. **Non-agentic guard** = `--max-turns 1 --allowedTools ""`; persona via **`--system-prompt`
   full override** (+ `--setting-sources ""`, `--strict-mcp-config`, `--no-session-persistence`)
   to strip Claude Code's agent framing and project-context pollution — accepted (flags verified).
3. **Auth hygiene** = child env with `ANTHROPIC_API_KEY` unset — accepted.
4. **Model** = `opus` alias — accepted.
5. **Run scoping** = whole catalog by default; `GEN_LIMIT`/`GEN_FROM`/`GEN_TO`/positional to bound — accepted.
6. **Grade sandbox** = separate OS process + `timeout --signal=KILL` for v1 — accepted.

**To confirm against reality (not blocking design):** the exact `claude -p` usage-limit
signature (§11 residual unknown) — tune the detection regex/status once a real limit event is
observed.
