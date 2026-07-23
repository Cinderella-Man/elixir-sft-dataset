defmodule GenTask.WriteTest do
  @moduledoc """
  The write-tests-for-module (`wtest`) generator (see `docs/06-dataset-multiplication.md`).

  For an accepted `_01`, mints a `wt_<a>_<b>_<slug>/` task **deterministically** (no LLM):

    * `solution.ex`      — the reference module (copy of the parent `solution.ex`),
    * `test_harness.exs` — the GOLD completion (copy of the parent `test_harness.exs`),
    * `prompt.md`        — a "write a test harness for this module" statement embedding
                           the module + the parent spec.

  The wtest SFT example is `prompt.md → test_harness.exs`. Its coverage is inherited: the
  parent `_01` already passed the base per-function mutation gate, so the gold harness is
  known to be non-vacuous. Minting only confirms the harness still grades green against the
  module (skipping Postgres-tier parents, whose eval is `skipped`), then promotes.

  `run/2` returns `[]` (nothing to do) or a one-element list with the outcome map.
  """

  require Logger

  alias GenTask.{Config, Cycle, CycleLog, Evaluator, GateLog, Register}

  @type seed :: %{
          optional(:name) => String.t(),
          num: pos_integer(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Mint the `wt_` derivative for `seed`, unless it already exists or is skipped."
  @spec run(seed(), Config.t()) :: [map()]
  def run(_seed, %Config{skip_write_test: true}), do: []

  def run(seed, %Config{} = cfg) do
    wt_id = wt_id(seed)

    cond do
      File.dir?(Path.join(cfg.tasks_dir, wt_id)) ->
        []

      true ->
        handle = CycleLog.open(cfg, wt_id)

        outcome =
          try do
            mint(seed, wt_id, cfg)
          rescue
            e ->
              Logger.error(
                "wtest #{wt_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__)
              )

              outcome(wt_id, seed, :error, reason: Exception.message(e))
          end

        CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
        [outcome]
    end
  end

  defp mint(seed, wt_id, cfg) do
    files = build_files(seed, cfg)
    stage = Path.join(cfg.staging_dir, wt_id)
    Evaluator.stage!(stage, files)
    grade = Evaluator.grade(stage, cfg)
    stats = Cycle.grade_stats(grade)

    cond do
      skipped?(grade) ->
        GateLog.skip(
          cfg,
          wt_id,
          :wtest,
          :parent_gradable,
          "parent grades `skipped` (e.g. requires Postgres) — nothing can be verified here"
        )

        outcome(wt_id, seed, :skipped, reason: "parent grades `skipped` (e.g. requires Postgres)")

      # A minted gold harness must compile warning-free (docs/12 §5.1 item 1) — the
      # only zero-LLM raw-invariant that can regress on the copy (the module + harness
      # are inherited, so `@moduledoc`/`@spec` house-style is NOT re-checked here).
      Evaluator.green?(grade) and Evaluator.compile_warnings(grade) > 0 ->
        GateLog.pass(cfg, wt_id, :wtest, :parent_gradable, "parent grades on this machine")

        GateLog.pass(
          cfg,
          wt_id,
          :wtest,
          :green_vs_module,
          "#{stats.tests_passed}/#{stats.tests_total} tests passed"
        )

        GateLog.fail(
          cfg,
          wt_id,
          :wtest,
          :zero_warnings,
          "gold harness compiles with #{Evaluator.compile_warnings(grade)} warning(s)"
        )

        outcome(wt_id, seed, :rejected,
          reason:
            "gold harness compiles with #{Evaluator.compile_warnings(grade)} warning(s) vs the module"
        )

      Evaluator.green?(grade) ->
        GateLog.pass(cfg, wt_id, :wtest, :parent_gradable, "parent grades on this machine")

        GateLog.pass(
          cfg,
          wt_id,
          :wtest,
          :green_vs_module,
          "#{stats.tests_passed}/#{stats.tests_total} tests passed " <>
            "(coverage inherited: the parent _01 passed the per-function mutation gate)"
        )

        GateLog.pass(cfg, wt_id, :wtest, :zero_warnings, "0 compile warnings")
        _ = Cycle.promote(cfg, wt_id, files, :wtest)
        outcome(wt_id, seed, :accepted, stats: stats)

      true ->
        GateLog.pass(cfg, wt_id, :wtest, :parent_gradable, "parent grades on this machine")

        GateLog.fail(
          cfg,
          wt_id,
          :wtest,
          :green_vs_module,
          "gold harness is not green vs the module: " <> Cycle.reason_for(grade)
        )

        outcome(wt_id, seed, :rejected,
          reason: "gold harness is not green vs the module: " <> Cycle.reason_for(grade)
        )
    end
  end

  # The wt_ directory files. `manifest.exs` is copied through when the parent carries one
  # (multifile Tier-B tasks), so the staged/promoted dir grades identically to the parent.
  defp build_files(seed, cfg) do
    base = %{
      "solution.ex" => seed.files["solution.ex"],
      "test_harness.exs" => seed.files["test_harness.exs"],
      "prompt.md" => prompt_md(seed.files["solution.ex"], seed.files["prompt.md"], wt_id(seed))
    }

    manifest = Path.join([cfg.tasks_dir, seed.task_id, "manifest.exs"])

    if File.regular?(manifest),
      do: Map.put(base, "manifest.exs", File.read!(manifest)),
      else: base
  end

  @doc """
  The `prompt.md` for a wtest task: the standalone "write tests for this module"
  statement embedding the reference `module_src` and the parent `spec`.

  The register rotates by `unit_id` (`GenTask.Register`, docs/20). FROZEN
  across variants: the `## Original specification` and `## Module under test`
  headings (contract_text + lint backfill anchors), the fence layout, the
  literal requirement tokens, and the timer-vocabulary ban (the intro prose
  sits INSIDE contract_text scope).
  """
  @spec prompt_md(String.t(), String.t(), String.t()) :: String.t()
  def prompt_md(module_src, spec, unit_id) do
    render(Register.variant(unit_id), String.trim_trailing(module_src), String.trim(spec))
  end

  defp render(0, module_src, spec) do
    """
    # Write tests for this module

    Below is a completed Elixir module and the original specification it was built to
    satisfy. Write a comprehensive ExUnit test harness that verifies a correct
    implementation of this module.

    Requirements for the harness:
    - Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
    - Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
    - Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
    - Cover the full public API and the important edge cases described in the spec.
    - It must compile with ZERO warnings (prefix unused variables with `_`; match float
      zero as `+0.0`/`-0.0`).
    - Give me the complete harness in a single file.

    ## Original specification

    #{spec}

    ## Module under test

    ```elixir
    #{module_src}
    ```
    """
  end

  defp render(1, module_src, spec) do
    """
    # Cover this module with tests

    Here is a finished Elixir module together with the specification it was
    written against. Your job is the harness: write an ExUnit suite that would
    catch a wrong implementation of this module.

    What the harness must satisfy:
    - Name the test module `<Module>Test` and `use ExUnit.Case, async: false`.
    - Skip `ExUnit.start()` — the evaluator calls it.
    - Keep everything inline: fakes, clock Agents, helpers — the file must stand
      alone.
    - Work through the whole public API, including the edge cases the
      specification calls out.
    - Zero compile warnings (prefix unused variables with `_`; match float zero
      as `+0.0`/`-0.0`).
    - Deliver the complete harness as one file.

    ## Original specification

    #{spec}

    ## Module under test

    ```elixir
    #{module_src}
    ```
    """
  end

  defp render(2, module_src, spec) do
    """
    # Write the test harness

    Module and original specification below. Produce the ExUnit harness that
    verifies a correct implementation.

    Hard requirements:
    - Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
    - No `ExUnit.start()` (the evaluator owns startup).
    - Self-contained single file: inline any fakes, clock Agents, and helpers.
    - Full public API coverage plus the specification's edge cases.
    - Compiles with zero warnings (`_`-prefix unused variables; float zero
      matches as `+0.0`/`-0.0`).

    ## Original specification

    #{spec}

    ## Module under test

    ```elixir
    #{module_src}
    ```
    """
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp wt_id(seed), do: "wt_" <> prefix(seed)

  defp prefix(seed), do: String.replace_suffix(seed.task_id, "_01", "")

  defp skipped?({:ok, json}), do: Map.has_key?(json, "skipped")
  defp skipped?(_), do: false

  defp outcome(wt_id, seed, status, opts) do
    stats =
      Keyword.get(opts, :stats, %{
        compiled: false,
        tests_passed: 0,
        tests_failed: 0,
        tests_total: 0
      })

    Cycle.outcome(
      id: wt_id,
      kind: :wtest,
      num: seed.num,
      name: "write-tests",
      status: status,
      attempts: 1,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      # No mutant EVER runs for a wt_ mint — coverage is inherited from the parent `_01`
      # (which passed the per-function gate). Recording `mutant_failed: true` claimed a
      # kill that never happened (docs/12 §5.1 item 5); the honest label is "inherited".
      mutant_failed: false,
      mutation: if(status == :accepted, do: "inherited", else: nil),
      reason: Keyword.get(opts, :reason)
    )
  end
end
