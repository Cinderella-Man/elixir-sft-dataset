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

  alias GenTask.{Config, Cycle, CycleLog, Evaluator, GateLog, Mutation}

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
  slots the minter cannot fill leaves the topup "pending" forever (found
  live 2026-07-12: 326 phantom pending units; describe-grouped harnesses are
  even the §5.3.1 recommendation, so the gap would only have grown).
  """
  @spec mintable_candidates(map(), Config.t()) :: [map()]
  def mintable_candidates(seed, %Config{} = cfg) do
    harness = seed.files["test_harness.exs"]
    covered = covered_quals(seed, cfg)

    rejected =
      CycleLog.rejected_tfim_targets(cfg, prefix(seed), CycleLog.content_sha(harness), gate_sha())

    harness
    |> carvable_blocks()
    |> Enum.reject(&MapSet.member?(covered, qual(&1)))
    # Negative cache: blocks that already failed the gates against THIS harness
    # content are permanent rejects (deterministic gates) — do not re-gate them
    # on every topup pass. Keyed by the QUALIFIED name (top-level quals equal
    # the bare name, so pre-describe ledger entries still match).
    |> Enum.reject(&MapSet.member?(rejected, qual(&1)))
    # Drop any block whose carved source does not parse (heredoc `  end` boundary,
    # etc.) so a truncated/invalid gold is never promoted.
    |> Enum.filter(&parses?(block_src(harness, &1)))
  end

  @doc """
  The registry's honest missing-unit count for `:test_fim` (see
  `mintable_candidates/2`): remaining `tfim_max_per_task` slots, capped by what
  is actually carvable from the seed's CURRENT harness on disk. An unreadable
  harness counts 0 — a broken dir must not hold the topup open.
  """
  @spec missing_units(
          %{:task_id => String.t(), :dir => String.t(), optional(any()) => any()},
          Config.t()
        ) ::
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

        files = %{
          "prompt.md" => prompt_md(module_src, skeleton, kind_of(harness, cand)),
          "solution.ex" => gold
        }

        # The perfect gate enforces ≤98 columns on the FRAGMENT; a line legal in
        # the parent harness (analysis does not measure harnesses) can overflow
        # once carved — describe-nesting adds 4 columns of indent (072_004's
        # test head, found by the pre-push sweep 2026-07-12). Deterministic for
        # this harness content, so the reject is ledgered like the other classes.
        over_98 = gold |> String.split("\n") |> Enum.count(&(String.length(&1) > 98))

        if over_98 > 0 do
          record_rejected(seed, cand, cfg)

          GateLog.fail(
            cfg,
            tfim_id,
            :tfim,
            :carvable,
            "carved block has #{over_98} line(s) over 98 columns (perfect-gate rule)"
          )

          {outcome(tfim_id, seed, qual(cand), :rejected,
             reason: "carved block has #{over_98} line(s) over 98 columns (perfect-gate rule)"
           ), false}
        else
          GateLog.pass(
            cfg,
            tfim_id,
            :tfim,
            :carvable,
            "top-level block #{qual(cand)} carved; skeleton + isolated harness built"
          )

          gate_candidate(seed, module_src, iso_harness, tfim_id, cand, files, cfg)
        end
      rescue
        e ->
          Logger.error("tfim #{tfim_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__))
          {outcome(tfim_id, seed, qual(cand), :error, reason: Exception.message(e)), false}
      end

    CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
    {outcome, promoted?}
  end

  # Stage the parent module beside the tfim candidate so the eval's `:test_fim` shape
  # resolves the parent, then run the two gates.
  defp gate_candidate(seed, module_src, iso_harness, tfim_id, cand, files, cfg) do
    stage_root = Path.join(cfg.staging_dir, tfim_id <> "_stage")
    parent_id = prefix(seed) <> "_01"

    # Tier-B/repo parents need their manifest beside the solution or the eval
    # misdetects tier A (docs/10 §5.13).
    parent_files =
      %{"solution.ex" => module_src}
      |> Map.merge(Map.take(seed.files, ["manifest.exs"]))

    Evaluator.stage!(Path.join(stage_root, parent_id), parent_files)
    tfim_dir = Path.join(stage_root, tfim_id)
    Evaluator.stage!(tfim_dir, files)

    recon = Evaluator.grade(tfim_dir, cfg)

    cond do
      not Evaluator.green?(recon) ->
        record_rejected(seed, cand, cfg)

        GateLog.fail(
          cfg,
          tfim_id,
          :tfim,
          :reconstruction,
          "reconstruct not green: " <> Cycle.reason_for(recon)
        )

        {outcome(tfim_id, seed, qual(cand), :rejected,
           reason: "reconstruct not green: " <> Cycle.reason_for(recon)
         ), false}

      # The reconstructed harness must compile warning-free (docs/12 §5.1 item 1);
      # deterministic, so cache the rejection like the other two reject classes.
      Evaluator.compile_warnings(recon) > 0 ->
        record_rejected(seed, cand, cfg)

        GateLog.fail(
          cfg,
          tfim_id,
          :tfim,
          :reconstruction,
          "reconstructed harness compiles with #{Evaluator.compile_warnings(recon)} warning(s)"
        )

        {outcome(tfim_id, seed, qual(cand), :rejected,
           reason:
             "reconstructed harness compiles with #{Evaluator.compile_warnings(recon)} warning(s)"
         ), false}

      true ->
        stats = Cycle.grade_stats(recon)

        GateLog.pass(
          cfg,
          tfim_id,
          :tfim,
          :reconstruction,
          "gold block re-inserted grades green (#{stats.tests_passed}/#{stats.tests_total}), " <>
            "0 warnings"
        )

        GateLog.applying(
          cfg,
          tfim_id,
          :tfim,
          :isolation_kill,
          if(bundle?(module_src),
            do: "bundle parent — static AST assertion check on the gold block",
            else: "raise-mutating the module vs the isolated target block"
          )
        )

        if gate_ok?(
             module_src,
             files["solution.ex"],
             iso_harness,
             Path.join(stage_root, "iso"),
             cfg
           ) do
          # Honest mutation label (docs/12 §5.1 item 5): a single-file target passed the
          # isolation raise-mutant gate (a real kill); a bundle target passed only the
          # static assertion check (`asserting_block?/1`) — no mutant ran.
          mode = if bundle?(module_src), do: "static_only", else: "isolation"

          GateLog.pass(
            cfg,
            tfim_id,
            :tfim,
            :isolation_kill,
            if(mode == "isolation",
              do: "isolated block killed >=1 raise-mutant of the module",
              else: "gold block carries a real assertion call (static check; no mutant ran)"
            )
          )

          _ = Cycle.promote(cfg, tfim_id, files, :tfim)
          {outcome(tfim_id, seed, qual(cand), :accepted, stats: stats, mutation: mode), true}
        else
          record_rejected(seed, cand, cfg)

          GateLog.fail(
            cfg,
            tfim_id,
            :tfim,
            :isolation_kill,
            "vacuous test block (no mutant killed / not independent)"
          )

          {outcome(tfim_id, seed, qual(cand), :rejected,
             reason: "vacuous test block (no mutant killed / not independent)"
           ), false}
        end
    end
  end

  # Both reject classes are deterministic for fixed content (fixed eval seed,
  # immutable tasks): remember them keyed by the parent-harness hash so later
  # topup passes skip the block instead of re-running the gates.
  defp record_rejected(seed, cand, cfg) do
    sha = CycleLog.content_sha(seed.files["test_harness.exs"])
    CycleLog.record_tfim_rejected(cfg, prefix(seed), qual(cand), sha, gate_sha())
  end

  # The verdict chain for a tfim reject spans the carver/isolation logic here,
  # the mutation kill, and the grading itself — a repair to ANY of them
  # re-opens this module's old rejections (T1.7; the 074_x and 102_001 lesson).
  defp gate_sha,
    do: CycleLog.gate_sha([__MODULE__, GenTask.Mutation, GenTask.Evaluator])

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
  # Harness carving (top-level `test "…"` blocks + describe-nested ones)
  # ------------------------------------------------------------------

  # Line spans of every block whose opener matches `opener_re`, ending at the first
  # line equal to `end_line`, optionally restricted to the `{lo, hi}` line range.
  # NOTE: this is line-based, not AST based; a block whose carved source does not
  # PARSE (e.g. a heredoc line that is literally the end line) is filtered out by
  # `parses?/1` before it can become a target.
  defp block_spans(harness, opener_re, end_line, range \\ nil) do
    lines = String.split(harness, "\n")
    n = length(lines)
    {lo, hi} = range || {0, n - 1}

    for {line, s} <- Enum.with_index(lines),
        s >= lo and s <= hi,
        Regex.match?(opener_re, line) do
      e =
        Enum.reduce_while((s + 1)..hi//1, nil, fn j, _ ->
          if Enum.at(lines, j) == end_line, do: {:halt, j}, else: {:cont, nil}
        end)

      %{name: block_name(line), s: s, e: e}
    end
    |> Enum.reject(&is_nil(&1.e))
  end

  @doc "Top-level `test \"…\"` blocks in `harness` as `%{name, s, e, describe: nil}`."
  @spec test_blocks(String.t()) :: [
          %{name: String.t(), s: non_neg_integer(), e: non_neg_integer(), describe: nil}
        ]
  def test_blocks(harness) do
    harness
    |> block_spans(~r/^  test\s+"/, "  end")
    |> Enum.reject(&is_nil(&1.name))
    |> Enum.map(&Map.put(&1, :describe, nil))
  end

  @doc "Top-level `describe \"…\"` blocks in `harness` as `%{name, s, e}`."
  @spec describe_blocks(String.t()) :: [
          %{name: String.t(), s: non_neg_integer(), e: non_neg_integer()}
        ]
  def describe_blocks(harness) do
    harness |> block_spans(~r/^  describe\s+"/, "  end") |> Enum.reject(&is_nil(&1.name))
  end

  @doc """
  Every carvable `test` block: top-level plus describe-nested (4-space indent),
  in source order. Nested entries carry their enclosing describe under
  `:describe` — §5.3.1 RECOMMENDS describe grouping, so a top-level-only carver
  minted zero tfim units from 32 harnesses / 426 nested tests (decision 4,
  2026-07-12).
  """
  @spec carvable_blocks(String.t()) :: [map()]
  def carvable_blocks(harness) do
    # `property` blocks (StreamData/ExUnitProperties) carve exactly like `test`
    # blocks: same skeleton stub, same splice, same isolation gate — and teach
    # property-based testing, which no other unit shape exercises (docs/13).
    top_props =
      harness
      |> block_spans(~r/^  property\s+"/, "  end")
      |> Enum.reject(&is_nil(&1.name))
      |> Enum.map(&Map.put(&1, :describe, nil))

    nested =
      for d <- describe_blocks(harness),
          t <- block_spans(harness, ~r/^    (test|property)\s+"/, "    end", {d.s + 1, d.e - 1}),
          not is_nil(t.name),
          do: Map.put(t, :describe, Map.take(d, [:name, :s, :e]))

    Enum.sort_by(test_blocks(harness) ++ top_props ++ nested, & &1.s)
  end

  @doc """
  ExUnit-style qualified test name: `"describe-name test-name"` for a nested
  block, the bare name otherwise. The covered/rejected bookkeeping keys on this —
  two describes may legally hold same-named tests.
  """
  @spec qual(map()) :: String.t()
  def qual(%{describe: %{name: dname}, name: name}), do: dname <> " " <> name
  def qual(%{name: name}), do: name

  # True if `src` is syntactically valid Elixir. Guards against a line-scan that carved a
  # block across a heredoc boundary (unterminated string → parse error → skip target).
  defp parses?(src), do: match?({:ok, _}, Code.string_to_quoted(src))

  @doc false
  def kind_of(harness, %{s: s}) do
    line = harness |> String.split("\n") |> Enum.at(s) |> to_string()
    if Regex.match?(~r/^\s*property\s+"/, line), do: "property", else: "test"
  end

  defp block_name(line) do
    case Regex.run(~r/^\s*(?:test|property|describe)\s+"((?:[^"\\]|\\.)*)"/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp block_src(harness, %{s: s, e: e}) do
    harness |> String.split("\n") |> Enum.slice(s..e) |> Enum.join("\n")
  end

  # The harness with the target block's BODY replaced by `# TODO` (name line kept).
  # Indent-generic: the stub takes the opener's own indentation, so a describe-nested
  # target (4-space) stubs as deeply as it sits — byte-identical to the old fixed
  # 2-space form for top-level targets.
  # Public (@doc false): `scripts/resync_tfim_embeds.exs` rebuilds prompt embeds from
  # the CURRENT parent harness after a harness edit (docs/10 R10 cascade).
  @doc false
  def skeletonize(harness, %{s: s, e: e}) do
    lines = String.split(harness, "\n")
    opener = Enum.at(lines, s)
    [_, ws] = Regex.run(~r/^(\s*)/, opener)
    stub = [opener, ws <> "  # TODO", ws <> "end"]
    (Enum.slice(lines, 0, s) ++ stub ++ Enum.slice(lines, (e + 1)..-1//1)) |> Enum.join("\n")
  end

  # The harness reduced to the target block + all non-test content (setup/helpers), with
  # every OTHER test-bearing block removed. Dropping sibling `describe` blocks is
  # essential: otherwise their nested tests would still kill mutants and the kill would
  # be mis-attributed to the target, letting a vacuous target pass the isolation gate.
  #
  # A top-level target drops every other top-level `test`/`describe`/`property` block.
  # A describe-nested target keeps its OWN describe (with its describe-scoped `setup`
  # and helpers) but drops the sibling tests inside it, plus every other top-level
  # test-bearing block.
  @doc false
  def isolate_for_test(harness, target), do: isolate(harness, target)

  defp isolate(harness, %{describe: nil} = target) do
    drop =
      harness
      |> block_spans(~r/^  (test|describe|property)\b/, "  end")
      |> Enum.reject(&(&1.s == target.s))
      |> Enum.flat_map(&Enum.to_list(&1.s..&1.e))
      |> MapSet.new()

    drop_lines(harness, drop)
  end

  defp isolate(harness, %{describe: d} = target) do
    top_drop =
      harness
      |> block_spans(~r/^  (test|describe|property)\b/, "  end")
      |> Enum.reject(&(&1.s == d.s))
      |> Enum.flat_map(&Enum.to_list(&1.s..&1.e))

    sibling_drop =
      harness
      |> block_spans(~r/^    (test|property)\b/, "    end", {d.s + 1, d.e - 1})
      |> Enum.reject(&(&1.s == target.s))
      |> Enum.flat_map(&Enum.to_list(&1.s..&1.e))

    drop_lines(harness, MapSet.new(top_drop ++ sibling_drop))
  end

  defp drop_lines(harness, drop) do
    harness
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reject(fn {_l, i} -> MapSet.member?(drop, i) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.join("\n")
  end

  @doc """
  The tfim `prompt.md`: the module fence + the harness skeleton fence (with the
  TODO). `kind` is `"test"` (default — byte-identical to every shipped prompt)
  or `"property"` for property-block units.
  """
  @spec prompt_md(String.t(), String.t(), String.t()) :: String.t()
  def prompt_md(module_src, skeleton, kind \\ "test") do
    """
    # Fill in the middle: implement the blanked #{kind}

    Below is a module and its ExUnit test harness with the body of ONE `#{kind}` removed
    (marked `# TODO`). The #{kind}'s name states what it must verify. Implement just that one
    #{kind} so the harness passes for a correct implementation of the module.

    ## Module under test

    ```elixir
    #{String.trim_trailing(module_src)}
    ```

    ## Test harness — implement the `# TODO` #{kind}

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

  # Qualified test names already turned into a tfim subtask (skip on a top-up run).
  # The gold holds only the bare test block, so the describe context is read from
  # the child's own prompt skeleton (which describe contains the `# TODO`).
  defp covered_quals(seed, cfg) do
    seed
    |> existing_dirs(cfg)
    |> Enum.map(fn d ->
      with {:ok, gold} <- File.read(Path.join(d, "solution.ex")),
           name when is_binary(name) <-
             gold |> String.split("\n") |> Enum.find_value(&block_name/1),
           {:ok, prompt} <- File.read(Path.join(d, "prompt.md")) do
        qual_from_prompt(prompt, name)
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  The qualified name of the stubbed test in a tfim `prompt.md`: `name` prefixed
  with the describe block enclosing the skeleton's `# TODO`, or bare `name` for a
  top-level stub. `scripts/resync_tfim_embeds.exs` uses it to locate the gold
  block in the CURRENT parent harness unambiguously.
  """
  @spec qual_from_prompt(String.t(), String.t()) :: String.t()
  def qual_from_prompt(prompt_md, name) do
    skeleton = EvalTask.Fim.extract_skeleton(prompt_md)
    lines = String.split(skeleton, "\n")
    todo = Enum.find_index(lines, &String.match?(&1, ~r/#\s*TODO/))
    d = todo && Enum.find(describe_blocks(skeleton), &(&1.s < todo and todo < &1.e))
    if d, do: d.name <> " " <> name, else: name
  rescue
    _ -> name
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
