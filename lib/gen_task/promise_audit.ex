defmodule GenTask.PromiseAudit do
  @moduledoc """
  The accept-time PROMISE AUDIT for root tasks (T1.10, docs/17 §5) — the in-loop
  replica of the two mechanisms that raised existing-corpus quality by hand:

    * `close_gaps.exs` — an LLM listed prompt promises with no test and wrote
      ADD-ONLY tests, each bite-proven before shipping;
    * `semantic_review`/`rubric_judge` + a human probe — suspected defects were
      never acted on until a probe PROVED them (rule 8's verify-before-verdict).

  One auditor call per accepted base/variation returns new test blocks, each
  anchored to a verbatim prompt quote. Every block is then machine-vetted:

    1. **anchor** — the quote must literally appear in prompt.md (whitespace-
       normalized, ≥ #{25} chars), so a test can only pin PROMISED behavior;
    2. **shape** — parseable top-level `test`/`property` block with a name no
       existing test uses;
    3. **verdict vs gold** — the block is staged alone on top of the accepted
       harness and graded against the accepted solution:
       * GREEN → a coverage candidate; it must then **bite** — kill ≥1
         raise-mutant of the module in isolation (`Mutation.gate_isolation`,
         the tfim gate) — or it is dropped as vacuous;
       * RED (a test genuinely ran and failed) → a **machine-proven defect**:
         the promised behavior does not hold. The block is kept so the repair
         loop must FIX the module against it.

  Kept blocks are merged (anchor comments stripped — a `# PROMISE:` citation in
  a shipped harness would be the S10 chatter class) and the grown triplet is
  re-run through the FULL shared cycle (`GenTask.Cycle.run/3`): green + house
  style + mutation + stability + repair-on-red. So a proven defect is fixed by
  the existing fixer against a failing test it cannot delete
  (`guard_test_deletion`), and the grown harness re-proves every gate.

  An audit that keeps nothing passes the gate unchanged ("harness already
  covers its prompt"). An LLM-transport failure returns `{:error, reason}` —
  environmental failures must never become verdicts (the F7 rule); the caller
  errors the unit and a later run retries.

  Hallucination containment (F6): a claim only ever acts through a test that
  (a) quotes the prompt and (b) demonstrably fails or bites against real code.
  A wrong claim either fails anchoring, fails to parse, passes greenly without
  biting (dropped), or sends the cycle into a repair that must still satisfy
  every OTHER test — the blast radius of a bad auditor reply is a rejected
  root, never silent corruption.

  Cost: roots only (docs/17 F17-10 — roots are the ~20x multiplier), one LLM
  call plus a handful of eval subprocesses per root. Dark behind
  `GEN_PROMISE_AUDIT=1` until piloted (the T1.1/T1.8 precedent).
  """

  require Logger

  alias GenTask.{Config, Cycle, Evaluator, GateLog, Mutation, Prompts, Reply}

  @min_quote_len 25
  @nothing_sentinel "NOTHING TO ADD"

  @type verdict :: {:ok, Cycle.result()} | {:rejected, String.t(), Cycle.result()}

  @doc """
  Audit an ACCEPTED cycle `result` for root `id` of `shape` (`:base` |
  `:variation`). Returns the (possibly grown + re-cycled) result, a rejection,
  or `{:error, reason}` on an environmental failure.
  """
  @spec run(Cycle.result(), String.t(), GateLog.shape(), Config.t()) ::
          verdict() | {:error, term()}
  def run(result, id, shape, %Config{promise_audit: false} = cfg) do
    GateLog.skip(
      cfg,
      id,
      shape,
      :promise_audit,
      "GEN_PROMISE_AUDIT=0 — gate DARK (T1.10, docs/17 §5; the in-loop close_gaps " <>
        "+ proven-defect probe)"
    )

    {:ok, result}
  end

  def run(result, id, shape, %Config{} = cfg) do
    files = result.files

    if EvalTask.Bundle.bundle?(files["solution.ex"]) do
      GateLog.skip(
        cfg,
        id,
        shape,
        :promise_audit,
        "bundle root — audit v1 vets single-module roots only (isolation mutants " <>
          "are single-module; docs/17 §5)"
      )

      {:ok, result}
    else
      GateLog.applying(
        cfg,
        id,
        shape,
        :promise_audit,
        "one auditor call, then per-test machine vetting (anchor → gold → bite)"
      )

      {system, user} = Prompts.promise_audit(files, cfg.audit_max_tests)

      case Cycle.generate(cfg, id, "promise_audit", system, user, &Reply.validate_audit/1) do
        {:ok, reply} ->
          vet_and_close(reply["added_tests.exs"], result, id, shape, cfg)

        {:error, reason} ->
          # F7: no reply, no verdict — the unit errors and re-runs later.
          {:error, "promise audit call failed: #{inspect(reason)}"}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Vetting + closing
  # ---------------------------------------------------------------------------

  defp vet_and_close(body, result, id, shape, cfg) do
    files = result.files

    case candidates(body) do
      :nothing ->
        GateLog.pass(
          cfg,
          id,
          shape,
          :promise_audit,
          "auditor reports NOTHING TO ADD — every promise it checked is already tested"
        )

        {:ok, result}

      {:error, why} ->
        # A malformed reply (after Cycle.generate's contract retry) proves
        # nothing about the task; drop the audit with a visible SKIP, exactly
        # like an environmental failure would — but log it loudly.
        Logger.warning("promise audit #{id}: unusable reply — #{why}")

        GateLog.skip(
          cfg,
          id,
          shape,
          :promise_audit,
          "unusable auditor reply (#{why}) — no verdict"
        )

        {:ok, result}

      {:ok, cands} ->
        {kept, dropped} = vet(cands, files, id, cfg)
        close(kept, dropped, result, id, shape, cfg)
    end
  end

  defp close([], dropped, result, id, shape, cfg) do
    GateLog.pass(
      cfg,
      id,
      shape,
      :promise_audit,
      "0 of #{length(dropped)} proposed tests admissible (#{drop_summary(dropped)}) — " <>
        "harness unchanged"
    )

    {:ok, result}
  end

  defp close(kept, dropped, result, id, shape, cfg) do
    files = result.files
    coverage = Enum.count(kept, &(&1.kind == :coverage))
    defects = Enum.count(kept, &(&1.kind == :defect))
    {grown, _s, _e} = grow(files["test_harness.exs"], Enum.map(kept, & &1.src))

    GateLog.detail(
      "merging #{length(kept)} vetted test(s) (#{coverage} coverage, #{defects} " <>
        "defect-proving; dropped #{length(dropped)}: #{drop_summary(dropped)}) — " <>
        "re-running the full cycle on the grown harness"
    )

    # The re-cycle gets its OWN attempt id: `Cycle.run/3` starts with
    # `reset_attempts`, which rm-rf's `logs/attempts/<id>/` — reusing the root id
    # would destroy the original cycle's captured attempt chain (the PERISHABLE
    # repair-mint raw material, STATUS TD.2). The `_audit` chain is itself
    # mintable and clearly provenance-labeled in every ledger it touches.
    ctx = %{
      dir: Path.join(cfg.staging_dir, id <> "_audit"),
      mutant_dir: Path.join(cfg.staging_dir, id <> "_audit_mut"),
      id: id <> "_audit",
      shape: shape
    }

    grown_files = Map.put(files, "test_harness.exs", grown)
    result2 = Cycle.run(grown_files, ctx, cfg)
    attempts = result.attempts + result2.attempts

    case result2.status do
      :accepted ->
        before_n = count_tests(files["test_harness.exs"])
        after_n = count_tests(result2.files["test_harness.exs"])

        GateLog.pass(
          cfg,
          id,
          shape,
          :promise_audit,
          "kept #{length(kept)} test(s) (#{coverage} coverage, #{defects} proven-defect); " <>
            "harness #{before_n}→#{after_n} tests; grown cycle green" <>
            if(defects > 0, do: " (module repaired against the proven defect(s))", else: "")
        )

        {:ok, %{result2 | attempts: attempts}}

      :rejected ->
        why =
          "promise audit: #{defects} machine-proven defect(s) / #{coverage} coverage " <>
            "test(s) could not be closed — #{result2.reason}"

        GateLog.fail(cfg, id, shape, :promise_audit, why)
        {:rejected, why, %{result2 | attempts: attempts}}
    end
  end

  # ---------------------------------------------------------------------------
  # Candidate extraction
  # ---------------------------------------------------------------------------

  @typep cand :: %{name: String.t(), quote: String.t() | nil, src: String.t()}

  @doc false
  @spec candidates(String.t()) :: {:ok, [cand()]} | :nothing | {:error, String.t()}
  def candidates(body) do
    cond do
      String.contains?(body, @nothing_sentinel) and not String.contains?(body, "test \"") ->
        :nothing

      true ->
        with {:ok, normalized} <- normalize(body) do
          case extract_blocks(normalized) do
            [] -> {:error, "no parseable top-level test/property blocks"}
            blocks -> {:ok, blocks}
          end
        end
    end
  end

  # Wrap the reply in a module and format it, so block scanning sees canonical
  # 2-space indentation regardless of how the model indented. A body that does
  # not parse is a contract failure (the auditor writes plain test blocks).
  defp normalize(body) do
    wrapped = "defmodule PromiseAuditWrap do\n" <> body <> "\nend\n"

    case Code.string_to_quoted(wrapped) do
      {:ok, _} ->
        formatted = wrapped |> Code.format_string!() |> IO.iodata_to_binary()
        {:ok, formatted}

      {:error, {meta, msg, token}} ->
        {:error, "reply does not parse: #{inspect(meta)} #{inspect(msg)} #{inspect(token)}"}
    end
  rescue
    e -> {:error, "reply could not be formatted: #{Exception.message(e)}"}
  end

  # Scan the formatted wrapper for 2-space-indented test/property blocks, each
  # with its contiguous immediately-preceding comment lines (the PROMISE anchor).
  defp extract_blocks(formatted) do
    lines = String.split(formatted, "\n")

    openers =
      for {line, i} <- Enum.with_index(lines),
          Regex.match?(~r/^  (test|property)\s+"/, line),
          do: i

    Enum.flat_map(openers, fn s ->
      case close_of(lines, s) do
        nil ->
          []

        e ->
          src = lines |> Enum.slice(s..e) |> Enum.join("\n")

          [
            %{
              name: block_name(Enum.at(lines, s)),
              quote: promise_quote(lines, s),
              src: src
            }
          ]
      end
    end)
  end

  # The block closes at the FIRST line where the accumulated slice parses as a
  # complete expression — one scan handles both forms: `test "x" do … end`
  # (parses only once its `end` is included) and the keyword one-liner
  # `test "x", do: …` (parses at its own line, no `end` exists).
  defp close_of(lines, s) do
    Enum.find(s..(length(lines) - 1), fn i ->
      src = lines |> Enum.slice(s..i) |> Enum.join("\n")
      match?({:ok, _}, Code.string_to_quoted(src))
    end)
  end

  defp block_name(opener) do
    case Regex.run(~r/^  (?:test|property)\s+"((?:[^"\\]|\\.)*)"/, opener) do
      [_, name] -> name
      nil -> ""
    end
  end

  # The nearest contiguous run of comment lines directly above the opener;
  # the anchor is the first of them matching `# PROMISE: "..."`.
  defp promise_quote(lines, s) do
    comments =
      (s - 1)..0//-1
      |> Enum.take_while(fn i -> Enum.at(lines, i) =~ ~r/^\s*#/ end)
      |> Enum.map(&Enum.at(lines, &1))

    Enum.find_value(comments, fn line ->
      case Regex.run(~r/#\s*PROMISE:\s*"(.+)"\s*$/, line) do
        [_, quote_text] -> quote_text
        nil -> nil
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Per-candidate vetting
  # ---------------------------------------------------------------------------

  defp vet(cands, files, id, cfg) do
    taken = existing_test_names(files["test_harness.exs"])

    {kept_rev, dropped_rev, _taken} =
      Enum.reduce(cands, {[], [], taken}, fn cand, {kept, dropped, taken} ->
        cond do
          length(kept) >= cfg.audit_max_tests ->
            {kept, [{cand, "over the GEN_AUDIT_MAX_TESTS cap"} | dropped], taken}

          true ->
            case vet_one(cand, files, id, taken, cfg) do
              {:keep, kind} ->
                detail(cand, "KEPT (#{kind})")
                {[Map.put(cand, :kind, kind) | kept], dropped, MapSet.put(taken, cand.name)}

              {:drop, why} ->
                detail(cand, "dropped — #{why}")
                {kept, [{cand, why} | dropped], taken}
            end
        end
      end)

    {Enum.reverse(kept_rev), Enum.reverse(dropped_rev)}
  end

  defp vet_one(cand, files, id, taken, cfg) do
    cond do
      cand.quote == nil ->
        {:drop, "no # PROMISE anchor comment"}

      not anchored?(cand.quote, files["prompt.md"]) ->
        {:drop,
         "anchor quote not found verbatim in prompt.md (or shorter than " <>
           "#{@min_quote_len} chars)"}

      cand.name == "" ->
        {:drop, "unparseable test name"}

      MapSet.member?(taken, cand.name) ->
        {:drop, "duplicates an existing test name"}

      true ->
        vet_against_gold(cand, files, id, cfg)
    end
  end

  defp vet_against_gold(cand, files, id, cfg) do
    {grown, _s, _e} = grow(files["test_harness.exs"], [cand.src])
    dir = Path.join(cfg.staging_dir, id <> "_audit_vet")
    Evaluator.stage!(dir, Map.put(files, "test_harness.exs", grown))
    grade = Evaluator.grade(dir, cfg)

    cond do
      Evaluator.green?(grade) ->
        bite_proof(cand.src, files, id, cfg)

      Evaluator.killed_by_tests?(grade) or Evaluator.errored_against_mutant?(grade) ->
        # The promised behavior does not hold on the accepted gold — a
        # machine-proven defect (this is exactly how F17-1 would have surfaced).
        {:keep, :defect}

      true ->
        {:drop, "inconclusive against the gold (compile failure or eval timeout)"}
    end
  end

  # A green candidate must prove it asserts real behavior: ALONE (plus the
  # harness's setup/helpers) it must kill at least one raise-mutant of the
  # module — `Mutation.gate_isolation`, the tfim gate. The sibling tests are
  # stripped from the harness AST (line-based span dropping misses keyword-form
  # `test "x", do: …` one-liners, which would then steal the kill and let a
  # vacuous candidate pass); `gate_isolation`'s own sanity re-grade guards the
  # other direction — a stripped harness that no longer works reads as
  # `{:survived, …}` and merely drops this candidate (add-only stays safe).
  defp bite_proof(cand_src, files, id, cfg) do
    with {:ok, bare} <- strip_test_blocks(files["test_harness.exs"]) do
      {isolated, _s, _e} = grow(bare, [cand_src])
      iso_dir = Path.join(cfg.staging_dir, id <> "_audit_iso")

      case Mutation.gate_isolation(iso_dir, files["solution.ex"], isolated, cfg) do
        :killed -> {:keep, :coverage}
        {:survived, why} -> {:drop, "vacuous (bite-proof failed: #{why})"}
      end
    else
      {:error, why} -> {:drop, "bite-proof impossible (#{why})"}
    end
  end

  # The harness with every `test`/`property` call removed from the module body
  # (AST-level, so keyword one-liners and do/end blocks are treated alike),
  # reprinted with `Macro.to_string/1`. Staging-only text — never promoted.
  @doc false
  @spec strip_test_blocks(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def strip_test_blocks(harness) do
    case Code.string_to_quoted(harness) do
      {:ok, ast} ->
        stripped =
          Macro.prewalk(ast, fn
            {:__block__, m, exprs} ->
              {:__block__, m, Enum.reject(exprs, &test_node?/1)}

            [do: {:__block__, m, exprs}] ->
              [do: {:__block__, m, Enum.reject(exprs, &test_node?/1)}]

            other ->
              other
          end)

        {:ok, Macro.to_string(stripped) <> "\n"}

      {:error, _} ->
        {:error, "harness does not parse"}
    end
  end

  defp test_node?({name, _, [_ | _]}) when name in [:test, :property], do: true
  defp test_node?(_), do: false

  # ---------------------------------------------------------------------------
  # Text plumbing
  # ---------------------------------------------------------------------------

  @doc false
  @spec anchored?(String.t(), String.t()) :: boolean()
  def anchored?(quote_text, prompt) do
    q = normalize_ws(quote_text)
    String.length(q) >= @min_quote_len and String.contains?(normalize_ws(prompt), q)
  end

  defp normalize_ws(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()

  @doc false
  @spec existing_test_names(String.t()) :: MapSet.t()
  def existing_test_names(harness) do
    ~r/^\s*(?:test|property)\s+"((?:[^"\\]|\\.)*)"/m
    |> Regex.scan(harness, capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  # Insert `blocks` (comment-stripped test sources) before the harness module's
  # final `end`. Returns `{merged, s, e}` — the 0-based line span the inserted
  # region occupies (used by the single-block bite-proof isolation). The merged
  # text is NOT re-formatted here: the accepted harness is already canonical and
  # the final merge goes through `Cycle.run`, whose autoformat owns canonical
  # bytes; keeping lines stable makes the span arithmetic exact.
  @doc false
  @spec grow(String.t(), [String.t()]) :: {String.t(), non_neg_integer(), non_neg_integer()}
  def grow(harness, blocks) do
    lines = String.split(harness, "\n")

    end_idx =
      lines
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find_value(fn {line, i} -> if line =~ ~r/^end\s*$/, do: i end)

    end_idx || raise ArgumentError, "harness has no module-closing `end` line"
    block_lines = blocks |> Enum.join("\n\n") |> String.split("\n")
    {before, rest} = Enum.split(lines, end_idx)
    merged = (before ++ [""] ++ block_lines ++ rest) |> Enum.join("\n")
    {merged, end_idx + 1, end_idx + length(block_lines)}
  end

  defp count_tests(harness), do: MapSet.size(existing_test_names(harness))

  defp detail(%{name: name}, text) do
    GateLog.detail("promise test \"#{name}\" ... #{text}")
  end

  defp drop_summary([]), do: "none dropped"

  defp drop_summary(dropped) do
    dropped
    |> Enum.map(fn {_cand, why} -> why |> String.split(" (") |> hd() end)
    |> Enum.frequencies()
    |> Enum.map_join(", ", fn {why, n} -> "#{n}× #{why}" end)
  end
end
