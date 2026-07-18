defmodule GenTask.Dedoc do
  @moduledoc """
  The de-documentation (`:dedoc`) generator (docs/13 §2.3, TD.3).

  For an accepted `_01` (base or variation), mints a `dedoc_<a>_<b>_<slug>/`
  task **deterministically** (no LLM):

    * `prompt.md`        — the parent gold with every documentation attribute
                           stripped (`@moduledoc`/`@doc`/`@typedoc`/`@spec`/
                           `@type`/`@typep`/`@opaque`), presented as
                           working-but-undocumented code, framed as "add
                           typespecs and documentation",
    * `solution.ex`      — the parent's reference module byte-for-byte (the
                           documented original IS the gold completion),
    * `test_harness.exs` — the parent harness byte-for-byte,
    * `manifest.exs`     — copied through when the parent carries one.

  What this teaches that no other shape does: writing accurate `@spec`s and
  honest docs for EXISTING behavior. The completion is verifiable with the
  standard evaluator — the harness pins behavior and the analysis score already
  pins `has_moduledoc`, `has_doc_on_public_fns` and `has_typespecs`.

  Mint gates (all local evals, no LLM):

    1. the parent is a single-module gold (bundles are v1-skipped, as with the
       promise audit) carrying the full house trio — `@moduledoc`, at least one
       `@doc`, at least one `@spec` — and stripping removes something;
    2. the parent gold's CURRENT sha reads clean-or-waived in
       `logs/dialyzer_golds.jsonl` (T1.6: a lying spec must never become a
       training target); a `warnings` verdict or no fresh row → skip;
    3. the STRIPPED module still grades green with 0 compile warnings against
       the parent harness — machine proof that stripping changed no behavior
       (subsumes doctest coupling and unused-type residue). Ledgered sha-keyed
       in `logs/dedoc_strip.jsonl` with this module in the gate sha, so a
       changed stripper re-opens its old verdicts (CONTEXT.md rule 7);
    4. the staged dedoc triplet grades green with 0 warnings → promote.

  Coverage is inherited from the parent `_01` (full gate suite), as with
  `wt_`/`adapt_` (docs/12 §5.1 item 5).
  """

  require Logger

  alias GenTask.{Catalog, Config, Cycle, CycleLog, Evaluator}

  @ledger "dedoc_strip.jsonl"
  @dialyzer_ledger "dialyzer_golds.jsonl"

  @doc_attrs ~w(@moduledoc @doc @typedoc)
  @spec_attrs ~w(@spec @type @typep @opaque)

  @type seed :: %{
          optional(:name) => String.t(),
          num: pos_integer(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Mint the `dedoc_` derivative for a `_01` seed, unless present or skipped."
  @spec run(seed(), Config.t()) :: [map()]
  def run(_seed, %Config{skip_dedoc: true}), do: []

  def run(seed, %Config{} = cfg) do
    dedoc_id = dedoc_id(seed.task_id)

    if File.dir?(Path.join(cfg.tasks_dir, dedoc_id)) do
      []
    else
      handle = CycleLog.open(cfg, dedoc_id)

      outcome =
        try do
          mint(seed, dedoc_id, cfg)
        rescue
          e ->
            Logger.error(
              "dedoc #{dedoc_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__)
            )

            outcome(dedoc_id, seed, :error, reason: Exception.message(e))
        end

      CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
      [outcome]
    end
  end

  defp mint(seed, dedoc_id, cfg) do
    src = seed.files["solution.ex"]
    harness = seed.files["test_harness.exs"]

    cond do
      src == nil or harness == nil or seed.files["prompt.md"] == nil ->
        outcome(dedoc_id, seed, :skipped, reason: "parent triplet incomplete")

      EvalTask.Bundle.bundle?(src) ->
        outcome(dedoc_id, seed, :skipped, reason: "bundle parent (dedoc v1 is single-module)")

      not house_trio?(src) ->
        outcome(dedoc_id, seed, :skipped,
          reason: "parent lacks the @moduledoc/@doc/@spec trio — the pair would under-teach"
        )

      not dialyzer_clean_or_waived?(cfg, src) ->
        outcome(dedoc_id, seed, :skipped,
          reason:
            "no clean-or-waived dialyzer verdict for the CURRENT gold sha " <>
              "(T1.6 gate — a lying spec must never become a training target)"
        )

      true ->
        mint_strip_gated(seed, dedoc_id, src, harness, cfg)
    end
  end

  defp mint_strip_gated(seed, dedoc_id, src, harness, cfg) do
    stripped = strip(src)

    if stripped == src do
      outcome(dedoc_id, seed, :skipped, reason: "stripping removed nothing")
    else
      case stripped_verdict(cfg, seed, src, stripped, harness) do
        :stripped_green ->
          do_mint(seed, dedoc_id, src, stripped, harness, cfg)

        :stripped_skipped ->
          outcome(dedoc_id, seed, :skipped,
            reason: "parent grades `skipped` (e.g. requires Postgres)"
          )

        :stripped_red ->
          outcome(dedoc_id, seed, :rejected,
            reason:
              "stripped module is NOT green with 0 warnings vs the parent harness — " <>
                "stripping is not behavior-neutral here (heredoc/doctest coupling?)"
          )
      end
    end
  end

  defp do_mint(seed, dedoc_id, src, stripped, harness, cfg) do
    files = build_files(seed, src, stripped, harness, cfg)
    stage = Path.join(cfg.staging_dir, dedoc_id)
    Evaluator.stage!(stage, files)
    grade = Evaluator.grade(stage, cfg)
    stats = Cycle.grade_stats(grade)

    cond do
      Evaluator.green?(grade) and Evaluator.compile_warnings(grade) == 0 ->
        _ = Cycle.promote(cfg, dedoc_id, files, :dedoc)
        outcome(dedoc_id, seed, :accepted, stats: stats)

      Evaluator.green?(grade) ->
        outcome(dedoc_id, seed, :rejected,
          reason: "gold compiles with #{Evaluator.compile_warnings(grade)} warning(s)"
        )

      true ->
        outcome(dedoc_id, seed, :rejected,
          reason: "gold is not green vs the harness copy: " <> Cycle.reason_for(grade)
        )
    end
  end

  defp build_files(seed, src, stripped, harness, cfg) do
    base = %{
      "prompt.md" => prompt_md(stripped),
      "solution.ex" => src,
      "test_harness.exs" => harness
    }

    manifest = Path.join([cfg.tasks_dir, seed.task_id, "manifest.exs"])

    if File.regular?(manifest),
      do: Map.put(base, "manifest.exs", File.read!(manifest)),
      else: base
  end

  @doc """
  The `prompt.md` for a dedoc task: the stripped module framed as "document
  this". Deterministic — the resync gate (`scripts/resync_dedoc_embeds.exs`)
  re-derives prompts through this same function.
  """
  @spec prompt_md(String.t()) :: String.t()
  def prompt_md(stripped_src) do
    """
    # Document this module

    Below is a complete, working, tested Elixir module. Its behavior is correct
    and must not change — but every piece of documentation has been stripped.

    Add the missing documentation and typespecs:

    - a `@moduledoc` that explains what the module does and how it is used,
    - a `@doc` for every public function,
    - a `@spec` for every public function (add `@type`s where they make the
      specs clearer).

    Do not change any behavior: every function clause, guard, and expression
    must keep working exactly as it does now. Do not rename anything, do not
    "improve" the code, and do not add or remove functions. Give me the
    complete documented module in a single file.

    ## The module

    ```elixir
    #{String.trim_trailing(stripped_src)}
    ```
    """
  end

  # ------------------------------------------------------------------
  # The stripper (promoted from docs/prototypes/proto_dedoc.exs)
  # ------------------------------------------------------------------

  @doc """
  Strip every documentation attribute from `src`: `@moduledoc`/`@doc`/`@typedoc`
  (single-line or `\"\"\"` heredoc) and `@spec`/`@type`/`@typep`/`@opaque`
  (single- or multi-line, swallowed until brackets balance and the line stops
  ending in a continuation token). The result is re-formatted with
  `Code.format_string!/1` so the blank-line residue collapses to canonical form.

  The stripper is line-based and deliberately simple; gate 3 (stripped module
  must stay green with 0 warnings) machine-checks every root it touches, so a
  root this function would mangle is skipped, never corrupted.
  """
  @spec strip(String.t()) :: String.t()
  def strip(src) do
    src
    |> strip_raw()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\n")
    |> Kernel.<>("\n")
  end

  @doc false
  @spec strip_raw(String.t()) :: String.t()
  def strip_raw(src) do
    src
    |> String.split("\n")
    |> walk([], :code)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp walk([], acc, _mode), do: acc

  defp walk([line | rest], acc, :code) do
    t = String.trim_leading(line)

    cond do
      doc_attr_line?(t) ->
        if heredoc_opener?(t),
          do: walk(rest, acc, :heredoc),
          else: walk(rest, acc, :code)

      spec_attr_line?(t) ->
        bal = bracket_balance(t)

        if spec_done?(t, bal, rest),
          do: walk(rest, acc, :code),
          else: walk(rest, acc, {:spec, bal})

      true ->
        walk(rest, [line | acc], :code)
    end
  end

  defp walk([line | rest], acc, :heredoc) do
    if String.starts_with?(String.trim(line), ~s(""")),
      do: walk(rest, acc, :code),
      else: walk(rest, acc, :heredoc)
  end

  defp walk([line | rest], acc, {:spec, bal}) do
    bal = bal + bracket_balance(line)

    if spec_done?(line, bal, rest),
      do: walk(rest, acc, :code),
      else: walk(rest, acc, {:spec, bal})
  end

  defp doc_attr_line?(t) do
    Enum.any?(@doc_attrs, fn attr ->
      t == attr or String.starts_with?(t, attr <> " ")
    end)
  end

  defp spec_attr_line?(t) do
    Enum.any?(@spec_attrs, fn attr -> String.starts_with?(t, attr <> " ") end)
  end

  # A heredoc opener that does NOT close on its own line: `@doc """` (also the
  # ~S/~s sigil forms). `@doc """x"""` closes immediately and is single-line.
  defp heredoc_opener?(t) do
    String.contains?(t, ~s(""")) and length(String.split(t, ~s("""))) < 3
  end

  # Word tokens demand a leading space (token boundary): a spec ending in
  # `:error` must NOT match "or" — that exact bug swallowed `def … do` lines on
  # the first corpus smoke run.
  @punct_continuations [",", "|", "::", "->", "<>", "++", "--", "\\\\"]
  @word_continuations [" when", " and", " or"]

  # The formatter breaks union/when specs with the operator at the START of the
  # continuation line (`| {:error, term()}`), so the end-of-spec check needs a
  # one-line lookahead as well as the trailing-token and bracket-balance checks.
  @leading_continuations ["| ", "|\n", "when ", ":: ", "and ", "or "]

  defp spec_done?(line, bal, rest) do
    trimmed = String.trim_trailing(line)
    next = rest |> List.first() |> Kernel.||("") |> String.trim_leading()

    bal <= 0 and not String.ends_with?(trimmed, @punct_continuations) and
      not String.ends_with?(trimmed, @word_continuations) and
      not String.starts_with?(next, @leading_continuations)
  end

  defp bracket_balance(line) do
    count = fn tokens ->
      Enum.sum(for t <- tokens, do: length(String.split(line, t)) - 1)
    end

    count.(["(", "[", "{"]) - count.([")", "]", "}"])
  end

  # ------------------------------------------------------------------
  # Gate 1 helper: the house documentation trio
  # ------------------------------------------------------------------

  @doc false
  @spec house_trio?(String.t()) :: boolean()
  def house_trio?(src) do
    lines = src |> String.split("\n") |> Enum.map(&String.trim_leading/1)

    has = fn attr ->
      Enum.any?(lines, &(String.starts_with?(&1, attr <> " ") or &1 == attr))
    end

    has.("@moduledoc") and has.("@doc") and has.("@spec")
  end

  # ------------------------------------------------------------------
  # Gate 2: dialyzer clean-or-waived at the CURRENT gold sha (T1.6 ledger)
  # ------------------------------------------------------------------

  @doc false
  @spec dialyzer_clean_or_waived?(Config.t(), String.t()) :: boolean()
  def dialyzer_clean_or_waived?(%Config{} = cfg, src) do
    sha = CycleLog.content_sha(src)

    case File.read(Path.join(cfg.logs_dir, @dialyzer_ledger)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(:none, fn line, acc ->
          case Jason.decode(line) do
            {:ok, %{"key" => key, "outcome" => o}} ->
              if String.starts_with?(key, sha <> ":"), do: {:ok, o}, else: acc

            _ ->
              acc
          end
        end)
        |> case do
          {:ok, o} when o in ["clean", "waived"] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  # ------------------------------------------------------------------
  # Gate 3: the stripped module stays green — ledger-cached, sha-keyed
  # ------------------------------------------------------------------

  defp stripped_verdict(cfg, seed, src, stripped, harness) do
    key = current_key(seed, src, harness)

    case cached_verdict(cfg, key) do
      {:ok, verdict} ->
        verdict

      :none ->
        verdict = measure_stripped(cfg, seed, stripped, harness)
        append_ledger(cfg, Map.put(key, :verdict, verdict))
        verdict
    end
  end

  defp measure_stripped(cfg, seed, stripped, harness) do
    files =
      %{"solution.ex" => stripped, "test_harness.exs" => harness}
      |> then(fn base ->
        manifest = Path.join([cfg.tasks_dir, seed.task_id, "manifest.exs"])

        if File.regular?(manifest),
          do: Map.put(base, "manifest.exs", File.read!(manifest)),
          else: base
      end)

    stage = Path.join(cfg.staging_dir, "dedoc_strip_" <> seed.task_id)
    Evaluator.stage!(stage, files)
    grade = Evaluator.grade(stage, cfg)

    cond do
      skipped?(grade) -> :stripped_skipped
      Evaluator.green?(grade) and Evaluator.compile_warnings(grade) == 0 -> :stripped_green
      true -> :stripped_red
    end
  end

  defp skipped?({:ok, json}), do: Map.has_key?(json, "skipped")
  defp skipped?(_), do: false

  defp current_key(seed, src, harness) do
    %{
      task: seed.task_id,
      solution_sha: CycleLog.content_sha(src),
      harness_sha: CycleLog.content_sha(harness),
      gate_sha: gate_sha()
    }
  end

  # This module's own code judges the verdict (rule-7 corollary: a repaired
  # stripper re-opens every verdict it wrote).
  defp gate_sha, do: CycleLog.gate_sha([__MODULE__, GenTask.Evaluator])

  defp cached_verdict(cfg, key) do
    case File.read(Path.join(cfg.logs_dir, @ledger)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(:none, fn line, acc ->
          case Jason.decode(line) do
            {:ok, row} ->
              if row["task"] == key.task and row["solution_sha"] == key.solution_sha and
                   row["harness_sha"] == key.harness_sha and row["gate_sha"] == key.gate_sha,
                 do: {:ok, verdict_atom(row["verdict"])},
                 else: acc

            _ ->
              acc
          end
        end)

      _ ->
        :none
    end
  end

  defp verdict_atom("stripped_green"), do: :stripped_green
  defp verdict_atom("stripped_red"), do: :stripped_red
  defp verdict_atom("stripped_skipped"), do: :stripped_skipped
  defp verdict_atom(other), do: raise(ArgumentError, "unknown dedoc verdict #{inspect(other)}")

  defp append_ledger(cfg, row) do
    File.mkdir_p!(cfg.logs_dir)

    File.write!(
      Path.join(cfg.logs_dir, @ledger),
      Jason.encode!(Map.put(row, :ts, DateTime.utc_now() |> DateTime.to_iso8601())) <> "\n",
      [:append]
    )
  end

  # ------------------------------------------------------------------
  # Registry contract: cheap missing-count inspection
  # ------------------------------------------------------------------

  @doc """
  Units still missing for `seed` (0 or 1): a complete single-module `_01` with
  the house trio, a clean-or-waived dialyzer verdict at the current gold sha,
  no `dedoc_` dir, and no cached red strip verdict for the current shas.
  """
  @spec missing_units(Catalog.Seed.t(), Config.t()) :: non_neg_integer()
  def missing_units(%Catalog.Seed{skip?: true}, _cfg), do: 0

  def missing_units(%Catalog.Seed{} = seed, cfg) do
    dir = Path.join(cfg.tasks_dir, seed.task_id)
    sol = Path.join(dir, "solution.ex")
    harness = Path.join(dir, "test_harness.exs")

    cond do
      File.dir?(Path.join(cfg.tasks_dir, dedoc_id(seed.task_id))) ->
        0

      not (File.regular?(sol) and File.regular?(harness) and
               File.regular?(Path.join(dir, "prompt.md"))) ->
        0

      EvalTask.Bundle.bundle?(File.read!(sol)) ->
        0

      not house_trio?(File.read!(sol)) ->
        0

      not dialyzer_clean_or_waived?(cfg, File.read!(sol)) ->
        0

      red_cached?(cfg, seed, sol, harness) ->
        0

      true ->
        1
    end
  end

  defp red_cached?(cfg, seed, sol, harness) do
    key = %{
      task: seed.task_id,
      solution_sha: CycleLog.content_sha(File.read!(sol)),
      harness_sha: CycleLog.content_sha(File.read!(harness)),
      gate_sha: gate_sha()
    }

    cached_verdict(cfg, key) == {:ok, :stripped_red}
  end

  @doc "The `dedoc_` dir name for a `task_id` (drops the `_01` like `wt_`/`adapt_`)."
  @spec dedoc_id(String.t()) :: String.t()
  def dedoc_id(task_id), do: "dedoc_" <> String.replace_suffix(task_id, "_01", "")

  # ------------------------------------------------------------------
  # outcome
  # ------------------------------------------------------------------

  defp outcome(dedoc_id, seed, status, opts) do
    stats =
      Keyword.get(opts, :stats, %{
        compiled: false,
        tests_passed: 0,
        tests_failed: 0,
        tests_total: 0
      })

    Cycle.outcome(
      id: dedoc_id,
      kind: :dedoc,
      num: seed.num,
      name: "dedoc-pair",
      status: status,
      attempts: 1,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      # No mutant EVER runs for a dedoc mint — coverage is inherited from the
      # parent `_01` (which passed the full gate suite), as with `wt_`/`adapt_`.
      mutant_failed: false,
      mutation: if(status == :accepted, do: "inherited", else: nil),
      reason: Keyword.get(opts, :reason)
    )
  end
end
