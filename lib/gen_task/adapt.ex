defmodule GenTask.Adapt do
  @moduledoc """
  The adaptation-pair (`:adapt`) generator (see `docs/13-existing-data-improvement-and-extension.md` §2.1).

  For an accepted VARIATION `_01`, mints an `adapt_<a>_<b>_<slug>/` task
  **deterministically** (no LLM):

    * `prompt.md`        — the family BASE's verified gold presented as the starting
                           point, followed by the variation's spec, framed as
                           "modify this existing code to the new specification",
    * `solution.ex`      — the GOLD completion (copy of the variation's `solution.ex`),
    * `test_harness.exs` — copy of the variation's harness (the gate that gold passes).

  The adapt SFT example is `prompt.md → solution.ex`. It teaches **brownfield
  modification** — start from working code and change it to a new spec — the one
  register absent from every other shape (all start blank or from a skeleton).

  **Mint gate (docs/13 §2.1): only mint where the BASE gold grades RED under the
  variation harness** — deterministic proof that the delta is real work. Verdicts
  are ledgered in `logs/adapt_redgate.jsonl`, keyed by (variation, base-solution
  sha, variation-harness sha); the gate re-measures whenever either sha drifts,
  so a repaired gold or strengthened harness auto-invalidates its old verdict
  (CONTEXT.md rule 7 corollary).

  Coverage is inherited: the variation `_01` already passed the full gate suite,
  and minting only confirms the copied gold still grades green in the copied dir.

  `run/2` returns `[]` (nothing to do) or a one-element list with the outcome map.
  """

  require Logger

  alias GenTask.{Catalog, Config, Cycle, CycleLog, Evaluator, GateLog}

  @ledger "adapt_redgate.jsonl"

  @type seed :: %{
          optional(:name) => String.t(),
          num: pos_integer(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Mint the `adapt_` derivative for a variation `seed`, unless present or skipped."
  @spec run(seed(), Config.t()) :: [map()]
  def run(_seed, %Config{skip_adapt: true}), do: []

  # Adaptation pairs exist only for variations: the base IS the starting point.
  def run(%{b: 1}, _cfg), do: []

  def run(seed, %Config{} = cfg) do
    adapt_id = adapt_id(seed.task_id)

    cond do
      File.dir?(Path.join(cfg.tasks_dir, adapt_id)) ->
        []

      true ->
        handle = CycleLog.open(cfg, adapt_id)

        outcome =
          try do
            mint(seed, adapt_id, cfg)
          rescue
            e ->
              Logger.error(
                "adapt #{adapt_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__)
              )

              outcome(adapt_id, seed, :error, reason: Exception.message(e))
          end

        CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
        [outcome]
    end
  end

  defp mint(seed, adapt_id, cfg) do
    var_dir = Path.join(cfg.tasks_dir, seed.task_id)

    case base_dir(cfg, seed.num) do
      nil ->
        outcome(adapt_id, seed, :skipped, reason: "no base `_001_*_01` sibling on disk")

      base ->
        if mintable_inputs?(base, var_dir) do
          mint_gated(seed, adapt_id, base, var_dir, cfg)
        else
          outcome(adapt_id, seed, :skipped,
            reason: "base gold or variation triplet incomplete on disk"
          )
        end
    end
  end

  defp mint_gated(seed, adapt_id, base, var_dir, cfg) do
    GateLog.applying(
      cfg,
      adapt_id,
      :adapt,
      :red_gate,
      "grading the BASE gold under the variation harness (must be RED to teach anything)"
    )

    case red_gate(cfg, base, var_dir) do
      :green_not_mintable ->
        GateLog.fail(
          cfg,
          adapt_id,
          :adapt,
          :red_gate,
          "base gold already grades green under the variation harness — " <>
            "the pair teaches nothing (docs/13 §2.1 mint gate)"
        )

        outcome(adapt_id, seed, :skipped,
          reason:
            "base gold already grades green under the variation harness — " <>
              "the pair teaches nothing (docs/13 §2.1 mint gate)"
        )

      red when red in [:red_tests, :red_compile, :red_crash] ->
        GateLog.pass(
          cfg,
          adapt_id,
          :adapt,
          :red_gate,
          "base gold grades #{red} under the variation harness — adaptation is non-trivial"
        )

        do_mint(seed, adapt_id, base, var_dir, cfg)
    end
  end

  defp do_mint(seed, adapt_id, base_dir, var_dir, cfg) do
    files = build_files(seed, base_dir, var_dir)
    stage = Path.join(cfg.staging_dir, adapt_id)
    Evaluator.stage!(stage, files)
    grade = Evaluator.grade(stage, cfg)
    stats = Cycle.grade_stats(grade)

    cond do
      skipped?(grade) ->
        GateLog.skip(
          cfg,
          adapt_id,
          :adapt,
          :gold_green,
          "variation grades `skipped` (e.g. requires Postgres) — nothing can be verified here"
        )

        outcome(adapt_id, seed, :skipped,
          reason: "variation grades `skipped` (e.g. requires Postgres)"
        )

      Evaluator.green?(grade) and Evaluator.compile_warnings(grade) > 0 ->
        GateLog.pass(
          cfg,
          adapt_id,
          :adapt,
          :gold_green,
          "#{stats.tests_passed}/#{stats.tests_total} tests passed"
        )

        GateLog.fail(
          cfg,
          adapt_id,
          :adapt,
          :zero_warnings,
          "gold compiles with #{Evaluator.compile_warnings(grade)} warning(s)"
        )

        outcome(adapt_id, seed, :rejected,
          reason:
            "gold compiles with #{Evaluator.compile_warnings(grade)} warning(s) vs the harness copy"
        )

      Evaluator.green?(grade) ->
        GateLog.pass(
          cfg,
          adapt_id,
          :adapt,
          :gold_green,
          "#{stats.tests_passed}/#{stats.tests_total} tests passed"
        )

        GateLog.pass(cfg, adapt_id, :adapt, :zero_warnings, "0 compile warnings")
        _ = Cycle.promote(cfg, adapt_id, files, :adapt)
        outcome(adapt_id, seed, :accepted, stats: stats)

      true ->
        GateLog.fail(
          cfg,
          adapt_id,
          :adapt,
          :gold_green,
          "gold is not green vs the harness copy: " <> Cycle.reason_for(grade)
        )

        outcome(adapt_id, seed, :rejected,
          reason: "gold is not green vs the harness copy: " <> Cycle.reason_for(grade)
        )
    end
  end

  # The adapt_ directory files. `manifest.exs` is copied through when the VARIATION
  # carries one, so the staged/promoted dir grades identically to the variation.
  defp build_files(seed, base_dir, var_dir) do
    base = %{
      "solution.ex" => seed.files["solution.ex"],
      "test_harness.exs" => seed.files["test_harness.exs"],
      "prompt.md" =>
        prompt_md(File.read!(Path.join(base_dir, "solution.ex")), seed.files["prompt.md"])
    }

    manifest = Path.join(var_dir, "manifest.exs")

    if File.regular?(manifest),
      do: Map.put(base, "manifest.exs", File.read!(manifest)),
      else: base
  end

  @doc """
  The `prompt.md` for an adapt task: the family base's `module_src` presented as the
  code to modify, followed by the variation's `spec`. Deterministic — the resync gate
  (`scripts/resync_adapt_embeds.exs`) re-derives prompts through this same function.
  """
  @spec prompt_md(String.t(), String.t()) :: String.t()
  def prompt_md(module_src, spec) do
    """
    # Adapt existing code to a new specification

    Below is a complete, working, tested Elixir solution to a related task. Do not
    start from scratch: treat it as the codebase you have been asked to change.
    Modify it to satisfy the new specification that follows — keep whatever carries
    over, and change, add, or remove whatever the new specification requires.

    Where the existing code and the new specification disagree (module name, public
    API, behavior, constraints, output format), the new specification wins. Give me
    the complete final result.

    ## Existing code (your starting point)

    ```elixir
    #{String.trim_trailing(module_src)}
    ```

    ## New specification

    #{String.trim(spec)}
    """
  end

  @doc """
  Units still missing for `seed` (0 or 1): a variation with a base sibling and no
  `adapt_` dir, unless the CURRENT (base-solution, variation-harness) sha pair has
  a `green_not_mintable` verdict in the ledger. The RED measurement itself is
  gate-expensive and runs in `run/2`, ledgered — this stays cheap disk inspection
  plus a ledger lookup (the `GenTask.Work` registry contract).
  """
  @spec missing_units(Catalog.Seed.t(), Config.t()) :: non_neg_integer()
  def missing_units(%Catalog.Seed{base?: true}, _cfg), do: 0
  def missing_units(%Catalog.Seed{skip?: true}, _cfg), do: 0

  def missing_units(%Catalog.Seed{} = seed, cfg) do
    var_dir = Path.join(cfg.tasks_dir, seed.task_id)
    base = base_dir(cfg, seed.num)

    cond do
      File.dir?(Path.join(cfg.tasks_dir, adapt_id(seed.task_id))) -> 0
      base == nil -> 0
      not mintable_inputs?(base, var_dir) -> 0
      cached_verdict(cfg, current_key(base, var_dir)) == {:ok, :green_not_mintable} -> 0
      true -> 1
    end
  end

  # Everything the mint reads must exist: the base gold, and the variation's
  # spec, gold and harness (a harness-less variation has no gate to inherit).
  defp mintable_inputs?(base_dir, var_dir) do
    File.regular?(Path.join(base_dir, "solution.ex")) and
      File.regular?(Path.join(var_dir, "prompt.md")) and
      File.regular?(Path.join(var_dir, "solution.ex")) and
      File.regular?(Path.join(var_dir, "test_harness.exs"))
  end

  # ------------------------------------------------------------------
  # The RED gate (docs/13 §2.1) — ledger-cached, sha-keyed
  # ------------------------------------------------------------------

  # Verdict for (base gold vs variation harness), reusing the ledger row when the
  # CURRENT shas match; otherwise measures (one eval subprocess) and appends.
  @doc false
  @spec red_gate(Config.t(), String.t(), String.t()) ::
          :green_not_mintable | :red_tests | :red_compile | :red_crash
  def red_gate(%Config{} = cfg, base_dir, var_dir) do
    key = current_key(base_dir, var_dir)

    case cached_verdict(cfg, key) do
      {:ok, verdict} ->
        verdict

      :none ->
        verdict = measure(cfg, base_dir, var_dir)
        append_ledger(cfg, Map.put(key, :verdict, verdict))
        verdict
    end
  end

  defp measure(cfg, base_dir, var_dir) do
    case Evaluator.grade(var_dir, cfg, Path.join(base_dir, "solution.ex")) do
      {:ok, json} ->
        cond do
          Evaluator.green?({:ok, json}) -> :green_not_mintable
          json["compiled"] != true -> :red_compile
          true -> :red_tests
        end

      :timeout_or_crash ->
        :red_crash
    end
  end

  defp current_key(base_dir, var_dir) do
    %{
      variation: Path.basename(var_dir),
      base: Path.basename(base_dir),
      base_solution_sha: CycleLog.content_sha(File.read!(Path.join(base_dir, "solution.ex"))),
      variation_harness_sha:
        CycleLog.content_sha(File.read!(Path.join(var_dir, "test_harness.exs")))
    }
  end

  # Latest ledger row matching the key's variation AND both content shas (a row
  # measured on other content is invalid for this content — CONTEXT.md rule 7).
  defp cached_verdict(cfg, key) do
    case File.read(Path.join(cfg.logs_dir, @ledger)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(:none, fn line, acc ->
          case Jason.decode(line) do
            {:ok, row} ->
              if row["variation"] == key.variation and
                   row["base_solution_sha"] == key.base_solution_sha and
                   row["variation_harness_sha"] == key.variation_harness_sha,
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

  defp verdict_atom("green_not_mintable"), do: :green_not_mintable
  defp verdict_atom("red_tests"), do: :red_tests
  defp verdict_atom("red_compile"), do: :red_compile
  defp verdict_atom("red_crash"), do: :red_crash
  defp verdict_atom(other), do: raise(ArgumentError, "unknown redgate verdict #{inspect(other)}")

  defp append_ledger(cfg, row) do
    File.mkdir_p!(cfg.logs_dir)

    File.write!(
      Path.join(cfg.logs_dir, @ledger),
      Jason.encode!(Map.put(row, :ts, DateTime.utc_now() |> DateTime.to_iso8601())) <> "\n",
      [:append]
    )
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  @doc "The `adapt_` dir name for a variation `task_id` (drops the `_01` like `wt_`)."
  @spec adapt_id(String.t()) :: String.t()
  def adapt_id(task_id), do: "adapt_" <> String.replace_suffix(task_id, "_01", "")

  @doc "The family base dir (`<a>_001_*_01`) for task number `num`, or nil."
  @spec base_dir(Config.t(), pos_integer()) :: String.t() | nil
  def base_dir(%Config{} = cfg, num) do
    "#{cfg.tasks_dir}/#{Catalog.pad3(num)}_001_*_01"
    |> Path.wildcard()
    |> Enum.find(&File.dir?/1)
  end

  defp skipped?({:ok, json}), do: Map.has_key?(json, "skipped")
  defp skipped?(_), do: false

  defp outcome(adapt_id, seed, status, opts) do
    stats =
      Keyword.get(opts, :stats, %{
        compiled: false,
        tests_passed: 0,
        tests_failed: 0,
        tests_total: 0
      })

    Cycle.outcome(
      id: adapt_id,
      kind: :adapt,
      num: seed.num,
      name: "adaptation-pair",
      status: status,
      attempts: 1,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      # No mutant EVER runs for an adapt mint — coverage is inherited from the
      # variation `_01` (which passed the full gate suite); the honest label is
      # "inherited", as with `wt_` (docs/12 §5.1 item 5).
      mutant_failed: false,
      mutation: if(status == :accepted, do: "inherited", else: nil),
      reason: Keyword.get(opts, :reason)
    )
  end
end
