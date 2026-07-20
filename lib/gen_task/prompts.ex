defmodule GenTask.Prompts do
  @moduledoc """
  Pure prompt builders for every `claude -p` step of the generation loop.

  Each builder returns a `{system, user}` tuple of strings — no I/O — so they are
  directly unit-testable. The templates are fully INLINED here (the historical
  meta-prompt files under `tasks/*.md` are dead — editing them changes nothing);
  each appends the shared file-only output contract
  (`docs/04-task-generation-loop.md` §7).

  The task-001 triplet is inlined (read at compile time) as the worked example for
  base task generation.
  """

  # T1.4(c) exemplar rotation (docs/12 §5.3; landed 2026-07-15 after the probe-4
  # review found a 4/4 singleton monoculture): three worked examples of DIFFERENT
  # shapes, rotated deterministically by idea number, so Step A stops imitating one
  # frozen GenServer template. All three have enriched-register prompts and
  # campaign-hardened harnesses (018_003 carries the F10 promise pins).
  @exemplar_dirs [
    # GenServer + injected clock + timers
    "tasks/001_001_rate_limiter_01",
    # pure functional data structure (no processes)
    "tasks/098_003_attenuable_capability_token_with_chained_caveats_01",
    # stateful hierarchical store + DateTime handling
    "tasks/018_003_cascading_archive_tree_with_origin_aware_restore_01"
  ]

  for dir <- @exemplar_dirs do
    @external_resource Path.join(dir, "prompt.md")
    @external_resource Path.join(dir, "test_harness.exs")
  end

  @exemplars Enum.map(@exemplar_dirs, fn dir ->
               {File.read!(Path.join(dir, "prompt.md")),
                File.read!(Path.join(dir, "test_harness.exs"))}
             end)

  @doc false
  @spec exemplar_for(pos_integer()) :: {String.t(), String.t()}
  def exemplar_for(num), do: Enum.at(@exemplars, rem(num, length(@exemplars)))

  @author_persona """
  You are an expert Elixir engineer authoring supervised fine-tuning (SFT) data for
  a coding benchmark. You write precise, self-contained, idiomatic Elixir/OTP tasks
  and rigorous ExUnit test harnesses. You follow the requested output format exactly
  and emit nothing outside the requested file blocks.
  """

  @solver_persona """
  You are an expert Elixir engineer. You are given a single task description and must
  implement it completely and correctly using only the specified dependencies. You
  write idiomatic, production-quality Elixir with clear @moduledoc/@doc where helpful.
  """

  # T1.4(a): the ONE authoring-rule block shared by the base and variation
  # templates (it was triplicated and had drifted once already — docs/12 §5.3).
  # Every rule here is scar tissue: each maps to a class the QA campaign found
  # shipping (docs/10–17).
  @harness_rules """
  Requirements for every prompt.md + test_harness.exs pair you produce:
  - Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
    Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
  - The harness must be self-contained: any fakes, clock Agents, or helpers are
    defined inline. It runs as `elixir test_harness.exs` beside a sibling
    `solution.ex`.
  - It must compile with ZERO warnings: prefix unused variables with `_`, and match
    float zero as `+0.0`/`-0.0` (never a bare `0.0`, which warns on OTP 27+).
  - If a test writes temp files, make the path process-unique, e.g.
    `Path.join(System.tmp_dir!(), "name_\#{System.pid()}_\#{System.unique_integer([:positive])}.ext")` —
    the corpus is graded with many harnesses running in parallel.
  - prompt.md must NOT reveal the tests; it is the standalone task statement.
  - Every assertion in the harness must be justified by an explicit statement in
    prompt.md — if a behavior is worth testing, state it in the prompt first. A
    solver who reads ONLY prompt.md must be able to pass every test. Never assert
    internal state (`:sys.get_state`), internal message names, or option values
    (e.g. `:infinity` sentinels) that prompt.md does not document.
  - COVERAGE RULE: every documented option, default value, guard, and behavioral
    mode in prompt.md must be exercised by at least one test. Do not document an
    option (for example a `:name` override) that no test exercises — either test
    it or leave it out of the contract.
  - API SHAPE: prefer a public API that takes an explicit server/pid/handle
    argument; design a singleton (module-named process) only when the idea itself
    demands one.
  - LIFECYCLE RULE (timers / scheduled work): if the module schedules repeating or
    delayed work (`Process.send_after`, periodic checks, sweeps), prompt.md MUST
    state EXPLICITLY what happens to already-scheduled work when its owner is
    replaced, re-registered, deregistered, or cancelled — e.g. "after
    re-registration the previous registration's scheduled checks never run again;
    checks happen only at the new interval". Solvers reliably forget to cancel old
    timer chains unless the prompt spells this consequence out, and
    test_harness.exs MUST include a test proving the old schedule is dead (not
    just that the new one works).
  - CALLBACK RULE: if the API accepts user-supplied callback functions (notify,
    on_change, hooks), prompt.md MUST state what happens when a callback raises
    (does the server crash, or is the callback isolated?), and the harness must
    include one test pinning that stated behavior.
  - DOC TRUTH RULE: every behavioral claim in a `@doc` string is a promise with
    the same standing as prompt.md prose — never write one the module does not
    implement AND the harness does not exercise (the F12 class: a @doc saying
    "cancels any pending check" over code that cancels nothing). If a @doc
    sentence states behavior, either the prompt states it too (so the promise
    audit anchors a test to it) or the sentence is cut. Docs describe the
    contract; they never decorate it.
  - Where the contract has a crisp input → output example, put it in the
    solution's `@doc` as an `iex>` doctest AND add `doctest <Module>` to the
    harness so the examples actually execute. Where an algebraic invariant exists
    (round-trip, idempotence, monotonicity), consider one property-based test
    (StreamData is available; `use ExUnitProperties`).
  """

  @doc false
  @spec harness_rules() :: String.t()
  def harness_rules, do: @harness_rules

  # House style every reference solution must follow (mirrors the analysis rubric the
  # evaluator scores: @moduledoc/@spec/@doc, ≤98 cols, no TODO, zero compile warnings).
  @house_style """
  House style — the solution MUST satisfy all of these:
    - a module `@moduledoc` describing the module;
    - an `@spec` AND `@doc` on every public function;
    - every line ≤ 98 columns; no `TODO`/`FIXME`/`HACK` markers;
    - compile with ZERO warnings — e.g. prefix unused variables with `_`, and match
      float zero as `+0.0`/`-0.0` (never a bare `0.0`, which warns on OTP 27+).
  """

  # ---------------------------------------------------------------------------
  # Shared output contract
  # ---------------------------------------------------------------------------

  @doc """
  The shared file-only output contract, listing the exact files the model must emit.
  `files` is a list of `{path, description}` tuples.
  """
  @spec output_contract([{String.t(), String.t()}]) :: String.t()
  def output_contract(files) do
    listing = Enum.map_join(files, "\n", fn {path, desc} -> "  - #{path} — #{desc}" end)

    """
    You have NO tools available in this session — do not attempt to read, write,
    edit, or run anything; reply directly with the file contents in your message.
    Return your answer as one or more file blocks and NOTHING ELSE — no prose, no
    markdown fences around the blocks. Each file must be exactly:

    <file path="RELATIVE/PATH">
    …verbatim file contents…
    </file>

    Emit exactly these files and nothing else:
    #{listing}
    """
  end

  # ---------------------------------------------------------------------------
  # Base — Step A: generate the task (prompt.md + test_harness.exs)
  # ---------------------------------------------------------------------------

  @doc "Prompts for base Step A: turn an idea into `prompt.md` + `test_harness.exs`."
  @spec base_task(%{num: integer(), name: String.t(), desc: String.t()}) ::
          {String.t(), String.t()}
  def base_task(%{num: num, name: name, desc: desc}) do
    {example_prompt, example_harness} = exemplar_for(num)

    user = """
    I've this idea:

    ```
    ### #{num}. #{name}
    #{desc}
    ```

    Convert it into a task prompt I could give to an AI to implement, AND a matching
    ExUnit test harness that verifies a correct implementation.

    Here is a previously generated prompt as a QUALITY example (imitate its precision,
    promise coverage, and edge-case statements):

    ```
    #{example_prompt}
    ```

    And here is its matching test harness as a template:

    ```elixir
    #{example_harness}
    ```

    Vary the rhetorical register: the example shows ONE way a task can read, not THE
    way. Do not default to opening with "Write me" — a titled specification document,
    a maintainer's change request, a design brief with sections are all good
    registers. What must never vary is precision: every behavior the harness checks
    must be stated in the prompt.

    #{@harness_rules}
    #{output_contract([{"prompt.md", "the standalone task statement"}, {"test_harness.exs", "the ExUnit harness"}])}
    """

    {@author_persona, user}
  end

  # ---------------------------------------------------------------------------
  # Base — Step B: solve blind from prompt.md only
  # ---------------------------------------------------------------------------

  @doc """
  Prompts for base Step B: implement the solution from the prompt alone (blind).

  `shape` selects the output contract: `:single` (default) asks for one
  `solution.ex`; `:multifile` asks for one `<file>` block per app source file —
  a solver cannot know the repo's inner-bundle convention, so for multifile
  tasks the caller assembles the returned blocks into the bundle form
  (`Reply.validate_bundle_answer/1` + `EvalTask.Bundle`-compatible assembly).
  """
  @spec base_solve(String.t(), :single | :multifile) :: {String.t(), String.t()}
  def base_solve(prompt_md, shape \\ :single)

  def base_solve(prompt_md, :single) do
    user = """
    #{prompt_md}

    #{@house_style}
    #{output_contract([{"solution.ex", "the complete implementation module"}])}
    """

    {@solver_persona, user}
  end

  def base_solve(prompt_md, :multifile) do
    user = """
    #{prompt_md}

    #{@house_style}
    #{output_contract([{"lib/<app_path>.ex", "one <file> block PER source file, its path mirroring the module name"}, {"priv/repo/migrations/<name>.exs", "any migration file(s) the prompt requires"}])}
    """

    {@solver_persona, user}
  end

  # ---------------------------------------------------------------------------
  # Variations — one call → 3 distinct triplets
  # ---------------------------------------------------------------------------

  @doc """
  Prompts for the 3-in-one variation generator. `base` is the accepted `_01`
  triplet map (`prompt.md`, `test_harness.exs`, `solution.ex`); `tasks_md` is the
  full catalog (freshly read) so the model avoids repeating existing ideas.
  `taken_fn_sets` renders the public-function sets already used by the base and
  accepted siblings — the EXACT criterion the distinctness gate rejects on, so
  the generator is told the rule it will be graded by (models otherwise converge
  on the base's natural API and every candidate bounces — the 034_001 pattern).
  """
  @spec variations(
          %{num: integer(), name: String.t()},
          %{String.t() => String.t()},
          String.t(),
          pos_integer(),
          [String.t()],
          [String.t()]
        ) :: {String.t(), String.t()}
  def variations(
        %{num: num, name: name},
        base,
        tasks_md,
        count \\ 3,
        existing \\ [],
        taken_fn_sets \\ []
      ) do
    already =
      case existing do
        [] ->
          ""

        names ->
          "\n\nThis task ALREADY has these variations — your new ones must be distinct " <>
            "from them too:\n" <> Enum.map_join(names, "\n", &"  - #{&1}")
      end

    taken_apis =
      case taken_fn_sets do
        [] ->
          ""

        sets ->
          "\n\nHARD CONSTRAINT — public API distinctness (an automatic gate rejects " <>
            "violations before grading): each variation's module must expose a public " <>
            "function set (name/arity) DIFFERENT from every set below. A genuinely " <>
            "different design has a different surface — different function names, " <>
            "arities, or decomposition, not the same API with a changed body:\n" <>
            Enum.map_join(sets, "\n", &"  - {#{&1}}")
      end

    user = """
    I have this SFT task (idea ##{num} — "#{name}"): its prompt, solution, and harness
    are below. I want to multiply the dataset with meaningful variations.

    Propose #{count} variation(s), each with a meaningful difference so it stands on its
    own as a distinct problem (not a trivial rename), differing from the base and from
    each other along a real axis (data structure, concurrency model, failure semantics,
    time model, API paradigm, …).

    AXIS REQUIREMENT: when the base performs its work synchronously inside one server
    process and you are proposing more than one variation, at least ONE variation must
    move the work across process boundaries — e.g. checks dispatched to spawned Tasks
    with per-task timeouts, monitored worker processes with stale-result discarding, or
    a supervised pool — with the coordination rules (timeout handling, stale replies,
    kill-on-cancel) stated in that variation's prompt and pinned by its tests. The
    cross-process axis produces the corpus's hardest and most valuable tasks; do not
    let every variation stay single-process.

    For each variation produce a full triplet (prompt.md, test_harness.exs,
    solution.ex).

    #{@harness_rules}
    NOTE: the BASE triplet below may itself violate these rules (grandfathered debt).
    Do NOT imitate its violations — your triplets are held to the rules above.#{already}#{taken_apis}

    Also, for each variation, produce a one-line catalog entry in the exact tasks.md
    format — its `idea.md` file must contain a `### Task #{num} - Vn - <Name>` header on
    the first line followed by a one-paragraph description (mirroring the entries in the
    attached catalog).

    === BASE prompt.md ===
    #{base["prompt.md"]}

    === BASE solution.ex ===
    #{base["solution.ex"]}

    === BASE test_harness.exs ===
    #{base["test_harness.exs"]}

    === EXISTING CATALOG TITLES (do NOT repeat any of these ideas) ===
    #{catalog_titles(tasks_md)}

    #{output_contract(variation_files(count))}
    """

    {@author_persona, user}
  end

  # Heading lines only: enough signal for the no-repeat constraint, without the prompt
  # growing linearly with the full catalog text (descriptions are ~10× the titles and
  # were inlined into EVERY variations call — docs/07 §6.2).
  defp catalog_titles(tasks_md) do
    tasks_md
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, ["## ", "### "]))
    |> Enum.join("\n")
  end

  defp variation_files(count) do
    for n <- 1..count,
        {f, d} <- [
          {"prompt.md", "task statement"},
          {"test_harness.exs", "ExUnit harness"},
          {"solution.ex", "reference implementation"},
          {"idea.md", "the `### Task N - Vn - Name` catalog entry + description"}
        ] do
      {"v#{n}/#{f}", d}
    end
  end

  # ---------------------------------------------------------------------------
  # FIM — candidate selection
  # ---------------------------------------------------------------------------

  @doc """
  Prompts for FIM candidate selection: pick up to `max` functions that make the
  best fill-in-the-middle targets in `module_src`.
  """
  @spec fim_select(String.t(), String.t(), pos_integer(), [String.t()]) ::
          {String.t(), String.t()}
  def fim_select(module_src, prompt_md, max, exclude \\ []) do
    exclusions =
      case exclude do
        [] ->
          ""

        targets ->
          "\n\nDo NOT pick any of these — they are already covered or known to be " <>
            "untested by the harness:\n" <> Enum.map_join(targets, "\n", &"  - #{&1}")
      end

    user = """
    Below is a completed Elixir module (a solved SFT task) and the prompt that produced
    it. I want to create "fill-in-the-middle" subtasks: each erases ONE function body and
    asks a model to reimplement it from the surrounding module.

    Pick the #{max} functions (or clauses) that make the best FIM targets — meaningful,
    self-contained logic that the module's own test harness actually exercises. Prefer
    private helpers and the core public callbacks over trivial one-liners.#{exclusions}

    === ORIGINAL PROMPT ===
    #{prompt_md}

    === MODULE ===
    ```elixir
    #{module_src}
    ```

    Return ONE file `candidates.md` containing at most #{max} lines, each a single
    function target written as `name/arity` (e.g. `refill_and_expire/2`), most valuable
    first, and NOTHING else.

    #{output_contract([{"candidates.md", "one function target (name/arity) per line"}])}
    """

    {@author_persona, user}
  end

  # ---------------------------------------------------------------------------
  # FIM — per-candidate generation
  # ---------------------------------------------------------------------------

  @doc """
  Prompts to generate a single FIM subtask for `target` (a `name/arity` string):
  a `prompt.md` (description + whole module with that one body replaced by
  `# TODO` inside an ```` ```elixir ```` fence) and a `solution.ex` (just that
  function).
  """
  @spec fim_candidate(String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def fim_candidate(module_src, prompt_md, target) do
    user = """
    I have this module which was a single-shot SFT answer. I want to create a
    "fill-in-the-middle" task out of it for the function `#{target}`.

    Generate a prompt describing how to implement `#{target}` (one function at a time),
    similar in spirit to this example:

    ```
    Implement the private `handle_closed/2` function. It should execute the provided
    zero-arity function using `execute/1`. If it succeeds, reset `failure_count` to 0 and
    return the result. If it fails, increment `failure_count`; if the count reaches
    `failure_threshold`, transition the circuit to `:open` using `trip_open/1`. In all
    cases return the result in the GenServer reply along with the updated state.
    ```

    The `prompt.md` you produce must contain:
      1. a natural-language description of what `#{target}` must do; then
      2. the WHOLE module inside a single ```` ```elixir ```` fenced block, with ONLY the
         body of `#{target}` replaced by `# TODO` (every other function intact).

    The `solution.ex` you produce is JUST the `#{target}` function (its full definition).

    === ORIGINAL PROMPT ===
    #{prompt_md}

    === WHOLE MODULE ===
    ```elixir
    #{module_src}
    ```

    #{output_contract([{"prompt.md", "description + skeleton module with a `# TODO` for #{target}"}, {"solution.ex", "just the #{target} function"}])}
    """

    {@author_persona, user}
  end

  # ---------------------------------------------------------------------------
  # Fix — the debug step (sees everything)
  # ---------------------------------------------------------------------------

  @doc """
  Prompts for the repair step. `files` is the current staged set; `report` is the
  failure feedback from the evaluator/mutation gate; `kind` is `:task` (base or
  variation — may edit `solution.ex` and/or `test_harness.exs`) or `:fim` (may edit
  `prompt.md` and/or `solution.ex`).
  """
  @spec fix(%{String.t() => String.t()}, String.t(), :task | :fim) ::
          {String.t(), String.t()}
  def fix(files, report, kind) do
    {editable, blocks} =
      case kind do
        :fim ->
          {"prompt.md and/or solution.ex",
           [{"prompt.md", files["prompt.md"]}, {"solution.ex", files["solution.ex"]}]}

        _ ->
          {"solution.ex and/or test_harness.exs",
           [
             {"prompt.md (READ-ONLY — do not return it)", files["prompt.md"]},
             {"solution.ex", files["solution.ex"]},
             {"test_harness.exs", files["test_harness.exs"]}
           ]}
      end

    contract =
      case kind do
        :fim ->
          output_contract([
            {"prompt.md", "only if the skeleton was wrong"},
            {"solution.ex", "the corrected function"}
          ])

        _ ->
          output_contract([
            {"solution.ex", "only if you changed it"},
            {"test_harness.exs", "only if you changed it"}
          ])
      end

    style_note = if kind == :task, do: "\n#{@house_style}", else: ""

    # :task — prompt.md is immutable (the statement must not drift), and deleting a
    # failing test is auto-rejected by the cycle, so say both up front.
    # :fim — prompt.md IS editable (a wrong skeleton can only be fixed there); the
    # unconditional "do NOT return prompt.md" used to contradict the contract above
    # and models resolved it by never fixing broken skeletons.
    rules =
      case kind do
        :fim ->
          "Return ONLY the file(s) you changed."

        _ ->
          "Return ONLY the file(s) you changed; do NOT return prompt.md.\n" <>
            "Never DELETE a test from test_harness.exs — a fix that reduces the test " <>
            "count is rejected automatically. Fix the code or the test instead."
      end

    user = """
    A generated task failed its automated check. Fix it. You may edit #{editable}.
    #{rules}

    === FAILURE REPORT ===
    #{report}
    #{style_note}
    === CURRENT FILES ===
    #{render_files(blocks)}

    #{contract}
    """

    {@solver_persona, user}
  end

  # ---------------------------------------------------------------------------
  # Promise audit (T1.10, docs/17 §5) — accept-time close_gaps + defect probe
  # ---------------------------------------------------------------------------

  @auditor_persona """
  You are an expert Elixir reviewer auditing an accepted training task. You are
  ruthless about one thing: every behavioral promise the task prompt makes must be
  exercised by a test, and any behavior of the module that VIOLATES a prompt promise
  must be exposed by a test. You follow the requested output format exactly and emit
  nothing outside the requested file blocks.
  """

  @doc """
  Prompts for the accept-time promise audit of a ROOT triplet (base/variation).

  The auditor sees all three files and must return ONLY new ExUnit test blocks in
  `added_tests.exs`, each preceded by a `# PROMISE: "<verbatim prompt sentence>"`
  anchor line. Two kinds of finding share one shape:

    * an UNCOVERED promise → a test that passes against a correct module (grows
      the harness after it is bite-proven);
    * a SUSPECTED defect → a test pinning the PROMISED behavior (it fails against
      the current module, machine-proving the defect; the repair loop then fixes
      the module against it).

  `max` bounds the number of blocks (`cfg.audit_max_tests`).
  """
  @spec promise_audit(%{String.t() => String.t()}, pos_integer()) :: {String.t(), String.t()}
  def promise_audit(files, max) do
    user = """
    Below is an Elixir training task that already passed compilation, its full test
    suite, house style, and mutation-coverage gates. Audit it for PROMISE COVERAGE.

    1. Read prompt.md as a contract. List (mentally) every behavioral promise it
       makes: lifecycle rules (registering/replacing/deregistering/cancelling
       scheduled work — old timers must really stop), option defaults, "exactly
       once" claims, documented edge cases, guard clauses, "never"/"always"
       sentences, and stated robustness rules.
    2. For each promise that NO existing test exercises, write ONE new ExUnit test
       that pins it through the PUBLIC API.
    3. Also read solution.ex skeptically. If you believe some behavior VIOLATES a
       prompt sentence (e.g. a replaced registration leaving the old timer chain
       alive), write a test that pins the PROMISED behavior — it will fail against
       this module and prove the defect. Judge the code only against prompt.md,
       never against your own taste.

    Audit SYSTEMATICALLY, not opportunistically — walk these known defect classes
    (each cost this project real cleanup) before anything else:
    - SCHEDULED-WORK MATRIX: for every kind of scheduled/delayed work, check every
      cell of {register, re-register/replace, deregister/remove, pause, resume,
      re-enter} × {armed timer, already-queued timer message}: who retires the old
      one? EXTENDING a window/interval must survive the replaced deadline; a
      retired registration's leftover message must never act. If the prompt
      promises it and no test drives real time past the OLD deadline, write that
      test.
    - EXACTLY-ONCE claims: drive one more event past the claimed point and assert
      no second effect (bookkeeping fields alone prove nothing — observe the
      callback/effect itself).
    - DEFAULTS and GUARDS: every documented default value and every documented
      guard needs a test that uses it.
    - NAME REGISTRATION: if the prompt promises a `:name` option (or a default
      registered name), at least one test must start the process under a name and
      drive one real call through the REGISTERED NAME instead of the pid. Names
      travel through variables and helpers — check what the start helper actually
      passes, not what the option list looks like.
    - AUTOMATIC TIMERS: if the prompt promises work that happens BY ITSELF
      (`Process.send_after` in init, a periodic sweep, an interval/period option),
      at least one test must enable it with a real but SHORT interval and OBSERVE
      one automatic firing through the public API (e.g. a two-round probe through
      a wider observation window). A suite where every test disables the timer
      (`:infinity`) or only triggers the sweep by hand leaves a no-op scheduler
      fully green.
    - DEFAULT CLOCK: a promised "when omitted, uses the real clock" default needs
      one test that OMITS the clock option and brackets the observed timestamp
      between two real-clock readings taken around the call (no sleeps, no
      margins) — never leave the promised default entirely unexercised.
    - STALENESS: any ref/token/generation the prompt implies must be tested with a
      deliberately stale message.
    - BOUNDARIES: thresholds at exactly-equal values; empty/one-element windows;
      duplicate keys compared by value.

    Rules for every test block you return:
    - Precede it with EXACTLY one anchor comment line:
      # PROMISE: "<a sentence copied VERBATIM from prompt.md>"
      The quote must be long enough to be unambiguous (a full clause, not a word).
    - Drive the PUBLIC API only — never `:sys.get_state`, internal messages, or
      option values prompt.md does not document.
    - Deterministic: no bare `Process.sleep` waits; use the harness's existing
      helpers (they stay defined — do NOT redefine them), scripted functions, and
      bounded `assert_receive`/`refute_receive`. NEVER assert margins around real
      elapsed time or race a real timer against a tight deadline. A documented
      real-time default clock IS still testable without that (the DEFAULT CLOCK
      bracket pattern above), and a promised automatic timer IS still testable
      (short real interval + a bounded observation window) — write those tests
      rather than skipping the promise.
    - NON-VACUOUS: before returning a test, check it can actually FAIL against a
      wrong module: the asserted value must be produced by the module under test,
      not by the test's own bookkeeping (a fake-clock test that advances its own
      clock and then asserts the advanced value it computed itself proves
      nothing).
    - Zero compile warnings; every line ≤ 98 columns.
    - The test NAME must not duplicate any existing test name.
    - At most #{max} test blocks, most important first. Top-level `test` blocks
      only (no `describe` wrappers).

    If every promise is covered and you find no violation, return the file
    containing exactly this single comment line:
    # NOTHING TO ADD

    ----- prompt.md (the contract) -----
    #{files["prompt.md"]}

    ----- test_harness.exs (the existing suite) -----
    #{files["test_harness.exs"]}

    ----- solution.ex (the module under audit) -----
    #{files["solution.ex"]}

    #{output_contract([{"added_tests.exs", "ONLY the new test blocks (with their # PROMISE anchors), or # NOTHING TO ADD"}])}
    """

    {@auditor_persona, user}
  end

  defp render_files(blocks) do
    blocks
    |> Enum.reject(fn {_label, body} -> is_nil(body) end)
    |> Enum.map_join("\n\n", fn {label, body} ->
      "----- #{label} -----\n#{body}"
    end)
  end
end
