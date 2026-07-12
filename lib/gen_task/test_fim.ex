defmodule GenTask.TestFim do
  @moduledoc """
  The fill-in-the-middle-over-tests (`tfim`) generator (see `docs/06-dataset-multiplication.md`).

  For an accepted `_01`, carves up to `cfg.tfim_max_per_task` `tfim_<a>_<b>_<slug>_0d/`
  subtasks **deterministically** (no LLM). Each blanks the body of ONE top-level
  `test "…"` block in the parent `test_harness.exs` (the test NAME line is kept — it is
  the spec) and asks a model to reimplement just that test.

    * `prompt.md`   — the reference module + the whole harness with one `test` body → `# TODO`,
    * `solution.ex` — the GOLD completion (that one `test` block).

  A block is a valid target only when (single-file) it passes the **isolation-kill** gate
  (run alone, green vs the module AND kills ≥1 raise-mutant), or (multifile, bundle module —
  mutation deferred) it reconstructs green and statically contains ≥1 assertion. Accepted
  candidates promote to `tasks/tfim_<a>_<b>_<slug>_0d/`.

  `run/2` returns a list of outcome maps (one per promoted / rejected candidate).
  """

  require Logger

  alias GenTask.{Config, Cycle, CycleLog, Evaluator, Mutation}

  @type seed :: %{
          optional(:name) => String.t(),
          num: pos_integer(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Carve tfim subtasks for `seed`, up to the top-up cap, skipping covered targets."
  @spec run(seed(), Config.t()) :: [map()]
  def run(_seed, %Config{skip_test_fim: true}), do: []

  def run(seed, %Config{} = cfg) do
    limit = cfg.tfim_max_per_task - existing_count(seed, cfg)
    module_src = seed.files["solution.ex"]
    harness = seed.files["test_harness.exs"]

    if limit <= 0,
      do: [],
      else: mint_loop(seed, module_src, harness, mintable_candidates(seed, cfg), limit, cfg)
  end

  @doc """
  The test blocks the minter could actually promote for this seed RIGHT NOW:
  carvable top-level `test` blocks, minus blocks already covered by an existing
  tfim dir, minus the deterministic negative cache for the current harness
  content, minus blocks whose carved source does not parse.

  `GenTask.Work` counts `min(remaining slots, length(this))` as the seed's
  missing tfim units — NOT `tfim_max - existing`: a harness whose tests all sit
  inside `describe` blocks has zero carvable top-level blocks, and counting
  slots the minter cannot fill leaves the backfill "pending" forever (found
  live 2026-07-12: 326 phantom pending units; describe-grouped harnesses are
  even the §5.3.1 recommendation, so the gap would only have grown).
  """
  @spec mintable_candidates(map(), Config.t()) :: [map()]
  def mintable_candidates(seed, %Config{} = cfg) do
    harness = seed.files["test_harness.exs"]
    covered = covered_names(seed, cfg)

    rejected = CycleLog.rejected_tfim_targets(cfg, prefix(seed), CycleLog.content_sha(harness))

    harness
    |> test_blocks()
    |> Enum.reject(&MapSet.member?(covered, &1.name))
    # Negative cache: blocks that already failed the gates against THIS harness
    # content are permanent rejects (deterministic gates) — do not re-gate them
    # on every backfill pass.
    |> Enum.reject(&MapSet.member?(rejected, &1.name))
    # Drop any block whose carved source does not parse (heredoc `  end` boundary,
    # etc.) so a truncated/invalid gold is never promoted.
    |> Enum.filter(&parses?(block_src(harness, &1)))
  end

  @doc """
  The registry's honest missing-unit count for `:test_fim` (see
  `mintable_candidates/2`): remaining `tfim_max_per_task` slots, capped by what
  is actually carvable from the seed's CURRENT harness on disk. An unreadable
  harness counts 0 — a broken dir must not hold the backfill open.
  """
  @spec missing_units(%{:task_id => String.t(), :dir => String.t(), optional(any()) => any()}, Config.t()) ::
          non_neg_integer()
  def missing_units(seed, %Config{} = cfg) do
    pseudo = %{task_id: seed.task_id, files: %{}}
    slots = cfg.tfim_max_per_task - existing_count(pseudo, cfg)

    with true <- slots > 0,
         {:ok, harness} <- File.read(Path.join(seed.dir, "test_harness.exs")) do
      pseudo = %{task_id: seed.task_id, files: %{"test_harness.exs" => harness}}
      min(slots, length(mintable_candidates(pseudo, cfg)))
    else
      _ -> 0
    end
  end

  # Walk candidate blocks, gating each; promote the viable ones (contiguous _0d slots)
  # until the top-up limit is reached.
  defp mint_loop(seed, module_src, harness, candidates, limit, cfg) do
    start_d = next_index(seed, cfg)

    {outs, _d, _left} =
      Enum.reduce(candidates, {[], start_d, limit}, fn cand, {acc, d, left} ->
        if left <= 0 do
          {acc, d, left}
        else
          {out, promoted?} = build_candidate(seed, module_src, harness, cand, d, cfg)

          {[out | acc], if(promoted?, do: d + 1, else: d),
           if(promoted?, do: left - 1, else: left)}
        end
      end)

    Enum.reverse(outs)
  end

  defp build_candidate(seed, module_src, harness, cand, d, cfg) do
    tfim_id = "tfim_#{prefix(seed)}_#{pad2(d)}"
    handle = CycleLog.open(cfg, tfim_id)

    {outcome, promoted?} =
      try do
        gold = block_src(harness, cand)
        skeleton = skeletonize(harness, cand)
        iso_harness = isolate(harness, cand)
        files = %{"prompt.md" => prompt_md(module_src, skeleton), "solution.ex" => gold}

        gate_candidate(seed, module_src, iso_harness, tfim_id, cand, files, cfg)
      rescue
        e ->
          Logger.error("tfim #{tfim_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__))
          {outcome(tfim_id, seed, cand.name, :error, reason: Exception.message(e)), false}
      end

    CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
    {outcome, promoted?}
  end

  # Stage the parent module beside the tfim candidate so the eval's `:test_fim` shape
  # resolves the parent, then run the two gates.
  defp gate_candidate(seed, module_src, iso_harness, tfim_id, cand, files, cfg) do
    stage_root = Path.join(cfg.staging_dir, tfim_id <> "_stage")
    parent_id = prefix(seed) <> "_01"
    Evaluator.stage!(Path.join(stage_root, parent_id), %{"solution.ex" => module_src})
    tfim_dir = Path.join(stage_root, tfim_id)
    Evaluator.stage!(tfim_dir, files)

    recon = Evaluator.grade(tfim_dir, cfg)

    cond do
      not Evaluator.green?(recon) ->
        record_rejected(seed, cand, cfg)

        {outcome(tfim_id, seed, cand.name, :rejected,
           reason: "reconstruct not green: " <> Cycle.reason_for(recon)
         ), false}

      # The reconstructed harness must compile warning-free (docs/12 §5.1 item 1);
      # deterministic, so cache the rejection like the other two reject classes.
      Evaluator.compile_warnings(recon) > 0 ->
        record_rejected(seed, cand, cfg)

        {outcome(tfim_id, seed, cand.name, :rejected,
           reason:
             "reconstructed harness compiles with #{Evaluator.compile_warnings(recon)} warning(s)"
         ), false}

      not gate_ok?(
        module_src,
        files["solution.ex"],
        iso_harness,
        Path.join(stage_root, "iso"),
        cfg
      ) ->
        record_rejected(seed, cand, cfg)

        {outcome(tfim_id, seed, cand.name, :rejected,
           reason: "vacuous test block (no mutant killed / not independent)"
         ), false}

      true ->
        _ = Cycle.promote(cfg, tfim_id, files)
        stats = Cycle.grade_stats(recon)
        # Honest mutation label (docs/12 §5.1 item 5): a single-file target passed the
        # isolation raise-mutant gate (a real kill); a bundle target passed only the
        # static assertion check (`asserting_block?/1`) — no mutant ran.
        mode = if bundle?(module_src), do: "static_only", else: "isolation"
        {outcome(tfim_id, seed, cand.name, :accepted, stats: stats, mutation: mode), true}
    end
  end

  # Both reject classes are deterministic for fixed content (fixed eval seed,
  # immutable tasks): remember them keyed by the parent-harness hash so later
  # backfill passes skip the block instead of re-running the gates.
  defp record_rejected(seed, cand, cfg) do
    sha = CycleLog.content_sha(seed.files["test_harness.exs"])
    CycleLog.record_tfim_rejected(cfg, prefix(seed), cand.name, sha)
  end

  # Single-file → isolation-kill; multifile (bundle) → static AST assertion check on
  # the GOLD BLOCK itself (mutation of a `<file>` bundle is deferred; checking the
  # whole isolated harness would pass on a setup/helper assert).
  defp gate_ok?(module_src, gold, iso_harness, iso_dir, cfg) do
    if bundle?(module_src) do
      asserting_block?(gold)
    else
      Mutation.gate_isolation(iso_dir, module_src, iso_harness, cfg) == :killed
    end
  end

  # Assertion macros that are behavioral by construction (they assert that something
  # HAPPENS — a message, an exception — so literal arguments are fine).
  @behavioral_asserts ~w(assert_receive refute_receive assert_raise assert_in_delta
                         catch_error catch_exit catch_throw)a

  # The old regex gate matched the WORD `assert` anywhere — inside a comment, a
  # string, or the vacuous `assert true` — so a contentless bundle gold could
  # promote. The AST check requires a real assertion CALL: either a behavioral
  # macro, or an `assert`/`refute` whose argument is a non-literal expression
  # (calls, match/comparison operators, variables — anything but a bare literal).
  # Conservative on parse failure: reject.
  @doc false
  @spec asserting_block?(String.t()) :: boolean()
  def asserting_block?(gold) do
    case Code.string_to_quoted(gold) do
      {:ok, ast} ->
        {_ast, found?} =
          Macro.prewalk(ast, false, fn
            {name, _m, [arg | _]} = node, acc when name in [:assert, :refute] ->
              {node, acc or is_tuple(arg)}

            {name, _m, args} = node, _acc
            when name in @behavioral_asserts and is_list(args) and args != [] ->
              {node, true}

            node, acc ->
              {node, acc}
          end)

        found?

      {:error, _} ->
        false
    end
  end

  defp bundle?(src), do: String.contains?(src, "<file path=")

  # ------------------------------------------------------------------
  # Harness carving (top-level `test "…"` blocks; describe-nested deferred)
  # ------------------------------------------------------------------

  # Line spans of every two-space-indent block whose opener matches `opener_re`, ending
  # at the first line equal to two-spaces-then-`end`. NOTE: this is line-based, not AST
  # based; a block whose carved source does not PARSE (e.g. a heredoc line that is
  # literally `  end`) is filtered out by `parses?/1` before it can become a target.
  defp block_spans(harness, opener_re) do
    lines = String.split(harness, "\n")
    n = length(lines)

    for {line, s} <- Enum.with_index(lines), Regex.match?(opener_re, line) do
      e =
        Enum.reduce_while((s + 1)..(n - 1)//1, nil, fn j, _ ->
          if Enum.at(lines, j) == "  end", do: {:halt, j}, else: {:cont, nil}
        end)

      %{name: test_name(line), s: s, e: e}
    end
    |> Enum.reject(&is_nil(&1.e))
  end

  @doc "Top-level `test \"…\"` blocks in `harness` as `%{name, s, e}` (start/end line idx)."
  @spec test_blocks(String.t()) :: [
          %{name: String.t(), s: non_neg_integer(), e: non_neg_integer()}
        ]
  def test_blocks(harness) do
    harness |> block_spans(~r/^  test\s+"/) |> Enum.reject(&is_nil(&1.name))
  end

  # True if `src` is syntactically valid Elixir. Guards against a line-scan that carved a
  # block across a heredoc boundary (unterminated string → parse error → skip target).
  defp parses?(src), do: match?({:ok, _}, Code.string_to_quoted(src))

  defp test_name(line) do
    case Regex.run(~r/^  test\s+"((?:[^"\\]|\\.)*)"/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp block_src(harness, %{s: s, e: e}) do
    harness |> String.split("\n") |> Enum.slice(s..e) |> Enum.join("\n")
  end

  # The harness with the target block's BODY replaced by `# TODO` (name line kept).
  # Public (@doc false): `scripts/resync_tfim_embeds.exs` rebuilds prompt embeds from
  # the CURRENT parent harness after a harness edit (docs/10 R10 cascade).
  @doc false
  def skeletonize(harness, %{s: s, e: e}) do
    lines = String.split(harness, "\n")
    stub = [Enum.at(lines, s), "    # TODO", "  end"]
    (Enum.slice(lines, 0, s) ++ stub ++ Enum.slice(lines, (e + 1)..-1//1)) |> Enum.join("\n")
  end

  # The harness reduced to the target block + all non-test content (setup/helpers), with
  # every OTHER test-bearing top-level block removed — `test`, `describe` (and its nested
  # tests), and `property`. Dropping `describe` blocks is essential: otherwise their
  # nested tests would still kill mutants and the kill would be mis-attributed to the
  # target, letting a vacuous target pass the isolation gate.
  defp isolate(harness, target) do
    lines = String.split(harness, "\n")

    drop =
      harness
      |> block_spans(~r/^  (test|describe|property)\b/)
      |> Enum.reject(&(&1.s == target.s))
      |> Enum.flat_map(&Enum.to_list(&1.s..&1.e))
      |> MapSet.new()

    lines
    |> Enum.with_index()
    |> Enum.reject(fn {_l, i} -> MapSet.member?(drop, i) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.join("\n")
  end

  @doc "The tfim `prompt.md`: the module fence + the harness skeleton fence (with the TODO)."
  @spec prompt_md(String.t(), String.t()) :: String.t()
  def prompt_md(module_src, skeleton) do
    """
    # Fill in the middle: implement the blanked test

    Below is a module and its ExUnit test harness with the body of ONE `test` removed
    (marked `# TODO`). The test's name states what it must verify. Implement just that one
    test so the harness passes for a correct implementation of the module.

    ## Module under test

    ```elixir
    #{String.trim_trailing(module_src)}
    ```

    ## Test harness — implement the `# TODO` test

    ```elixir
    #{String.trim_trailing(skeleton)}
    ```
    """
  end

  # ------------------------------------------------------------------
  # Top-up bookkeeping
  # ------------------------------------------------------------------

  defp existing_dirs(seed, cfg) do
    Path.join(cfg.tasks_dir, "tfim_#{prefix(seed)}_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
  end

  defp existing_count(seed, cfg), do: seed |> existing_dirs(cfg) |> length()

  # Test names already turned into a tfim subtask (skip on a top-up run).
  defp covered_names(seed, cfg) do
    seed
    |> existing_dirs(cfg)
    |> Enum.map(fn d ->
      case File.read(Path.join(d, "solution.ex")) do
        {:ok, src} -> src |> String.split("\n") |> Enum.find_value(&test_name/1)
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp next_index(seed, cfg) do
    existing =
      seed
      |> existing_dirs(cfg)
      |> Enum.map(&index_of(Path.basename(&1)))
      |> Enum.filter(&(is_integer(&1) and &1 >= 2))

    case existing do
      [] -> 2
      xs -> Enum.max(xs) + 1
    end
  end

  defp index_of(basename) do
    case basename |> String.split("_") |> List.last() |> Integer.parse() do
      {n, ""} -> n
      _ -> nil
    end
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp prefix(seed), do: String.replace_suffix(seed.task_id, "_01", "")
  defp pad2(d), do: String.pad_leading(to_string(d), 2, "0")

  defp outcome(tfim_id, seed, name, status, opts) do
    stats =
      Keyword.get(opts, :stats, %{
        compiled: false,
        tests_passed: 0,
        tests_failed: 0,
        tests_total: 0
      })

    mutation = Keyword.get(opts, :mutation)

    Cycle.outcome(
      id: tfim_id,
      kind: :tfim,
      num: seed.num,
      name: name,
      status: status,
      attempts: 1,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      # Only an "isolation" accept (single-file target) actually killed a raise-mutant;
      # a "static_only" bundle accept ran no mutant (docs/12 §5.1 item 5).
      mutant_failed: mutation == "isolation",
      mutation: mutation,
      reason: Keyword.get(opts, :reason)
    )
  end
end
