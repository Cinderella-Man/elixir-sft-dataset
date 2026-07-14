defmodule GenTask.Variations do
  @moduledoc """
  The variation generator (see `docs/04-task-generation-loop.md` §9).

  Runs only for an accepted base `_01`. One `claude -p` call emits three
  path-prefixed triplets (`v1/…`, `v2/…`, `v3/…`) plus a `vN/idea.md` catalog entry
  each; the catalog is read **fresh** for distinctness. Each variation is then run
  through the shared `GenTask.Cycle` independently — a partial success is fine — and
  every accepted variation is promoted to `tasks/NNN_00{n+1}_slug_01/` with its
  `### Task N - Vn - Name` entry inserted into `tasks.md` (idempotent, insert-only).

  `run/2` returns a list of outcome maps; each accepted one carries a `:seed` the
  caller feeds to `GenTask.Fim`.
  """

  require Logger

  alias GenTask.{Catalog, Config, Cycle, CycleLog, Mutation, Prompts, Reply}

  @variation_header ~r/^###\s+Task\s+\d+\s+-\s+V\d+\s+-\s+(.+?)\s*$/

  @doc """
  Generate the variations `base` still lacks and cycle/promote each.

  Only the **free** slots (of V1/V2/V3 → `_002`/`_003`/`_004`) are filled, so a base
  that already has one or two variations is topped up rather than skipped; a base with
  all three yields `[]`. The generation call requests exactly the missing count and is
  told the names of any existing variations so the new ones stay distinct.
  """
  @spec run(GenTask.Base.seed(), Config.t()) :: [map()]
  def run(base, %Config{} = cfg) do
    {free_slots, existing_names} = variation_gaps(base, cfg)
    taken0 = taken_public_fn_sets(base, cfg)

    case free_slots do
      [] ->
        []

      slots ->
        case gen_variations(base, cfg, length(slots), existing_names, taken0) do
          {:ok, files, valid_ns} ->
            # Salvage: only the reply groups that passed the contract are built; a
            # malformed vN forfeits its slot (topped up on a later run) instead of
            # discarding the sibling groups from the same expensive call.
            #
            # The distinctness gate (docs/12 §5.1 item 4) needs the set of public-function
            # sets already "taken" — the base's plus every on-disk sibling's — and grows it
            # as each new variation is accepted, so `map_reduce` threads that accumulator.
            {outs, _taken} =
              slots
              |> Enum.with_index(1)
              |> Enum.filter(fn {_slot, i} -> i in valid_ns end)
              |> Enum.map_reduce(taken0, fn {slot, i}, taken ->
                out = build_variation(i, slot, files, base, cfg, taken)
                {out, add_taken(taken, out)}
              end)

            outs

          {:error, out} ->
            [out]
        end
    end
  end

  # Grow the taken-set list when a variation was accepted with a non-empty public-function
  # set (so a later sibling in the same call can't duplicate it either).
  defp add_taken(taken, %{status: :accepted, seed: %{files: files}}) do
    case public_fn_set(files["solution.ex"]) do
      set -> if MapSet.size(set) > 0, do: [set | taken], else: taken
    end
  end

  defp add_taken(taken, _out), do: taken

  # A variation duplicates a taken set when its co-authored solution's public-function
  # set is non-empty and equal to any of them. Empty sets never collide (bundle / no
  # public defs: nothing to compare). Public (@doc false) so the gate decision is
  # unit-testable without a generation call.
  @doc false
  @spec duplicate_public_fn_set?(String.t() | nil, [MapSet.t()]) :: boolean()
  def duplicate_public_fn_set?(solution_src, taken) do
    set = public_fn_set(solution_src)
    MapSet.size(set) > 0 and Enum.any?(taken, &(&1 == set))
  end

  # The public-function sets a new variation must NOT duplicate: the base's, plus every
  # already-promoted sibling variation's (read fresh from disk). Empty sets (bundles /
  # modules with no public defs — `public_functions/1` returns []) are dropped: there is
  # nothing to compare, and every such solution would otherwise collide on the empty set.
  # Public (@doc false) for the same testability reason as `duplicate_public_fn_set?/2`.
  @doc false
  @spec taken_public_fn_sets(map(), Config.t()) :: [MapSet.t()]
  def taken_public_fn_sets(base, %Config{tasks_dir: tasks_dir}) do
    base_set = public_fn_set(base.files["solution.ex"])
    a = Catalog.pad3(base.num)

    sibling_sets =
      for b <- 2..4,
          dir <- Path.wildcard("#{tasks_dir}/#{a}_#{Catalog.pad3(b)}_*_01"),
          File.dir?(dir),
          sol = Path.join(dir, "solution.ex"),
          File.regular?(sol),
          set = public_fn_set(File.read!(sol)),
          MapSet.size(set) > 0,
          do: set

    Enum.reject([base_set | sibling_sets], &(MapSet.size(&1) == 0))
  end

  defp public_fn_set(nil), do: MapSet.new()
  defp public_fn_set(src), do: src |> Mutation.public_functions() |> MapSet.new()

  defp fn_set_str(set),
    do: set |> Enum.map(fn {n, a} -> "#{n}/#{a}" end) |> Enum.sort() |> Enum.join(", ")

  defp not_distinct_outcome(vtask_id, num, vname, var_set) do
    Cycle.outcome(
      id: vtask_id,
      kind: :variation,
      num: num,
      name: vname,
      status: :rejected,
      attempts: 0,
      reason:
        "not distinct: same public-function set as the base or an accepted sibling " <>
          "(#{fn_set_str(var_set)})"
    )
  end

  # Which of the V1/V2/V3 slots (b = 2/3/4) are still free, and the display names of
  # the variations that already exist (for the distinctness hint).
  defp variation_gaps(base, %Config{tasks_dir: tasks_dir}) do
    a = Catalog.pad3(base.num)

    occupied =
      for b <- 2..4,
          dir <- Path.wildcard("#{tasks_dir}/#{a}_#{Catalog.pad3(b)}_*_01"),
          File.dir?(dir),
          into: %{},
          do: {b, dir_display_name(dir)}

    free = Enum.reject(2..4, &Map.has_key?(occupied, &1))
    {free, Map.values(occupied)}
  end

  # "110_002_histogram_based_..._01" -> "histogram based ..."
  defp dir_display_name(dir) do
    dir
    |> Path.basename()
    |> String.split("_")
    |> Enum.drop(2)
    |> Enum.drop(-1)
    |> Enum.join(" ")
  end

  # ------------------------------------------------------------------
  # The shared N-in-one generation call (its own log file)
  # ------------------------------------------------------------------

  defp gen_variations(base, cfg, count, existing_names, taken) do
    gen_id = "#{Catalog.pad3(base.num)}_variations"
    handle = CycleLog.open(cfg, gen_id)
    Logger.info("VARIATIONS gen for #{base.task_id} (#{count} slot(s))")

    result =
      try do
        tasks_md = File.read!(cfg.tasks_md)

        {system, user} =
          Prompts.variations(
            %{num: base.num, name: base.name},
            base.files,
            tasks_md,
            count,
            existing_names,
            Enum.map(taken, &fn_set_str/1)
          )

        case Cycle.opus(cfg, base.task_id, "variations", system, user) do
          {:ok, text, _meta} ->
            files = Reply.parse(text)

            case Reply.valid_variation_slots(files, count) do
              {[], errors} ->
                msg = Enum.join(errors, "; ")
                Logger.error("variations (#{base.task_id}): contract violation: #{msg}")
                {:error, gen_error(gen_id, base, msg)}

              {valid_ns, errors} ->
                if errors != [] do
                  Logger.warning(
                    "variations (#{base.task_id}): salvaged #{length(valid_ns)}/#{count} " <>
                      "group(s); dropped: #{Enum.join(errors, "; ")}"
                  )
                end

                {:ok, files, valid_ns}
            end

          {:error, reason} ->
            {:error, gen_error(gen_id, base, inspect(reason))}
        end
      rescue
        e ->
          Logger.error("variations gen crashed: " <> Exception.format(:error, e, __STACKTRACE__))
          {:error, gen_error(gen_id, base, Exception.message(e))}
      end

    CycleLog.close(handle, if(match?({:ok, _, _}, result), do: :ok, else: :error))
    result
  end

  defp gen_error(gen_id, base, reason) do
    Cycle.outcome(
      id: gen_id,
      kind: :variation,
      num: base.num,
      name: base.name,
      status: :error,
      reason: reason
    )
  end

  # ------------------------------------------------------------------
  # Per-variation cycle + promotion (each in its own log file)
  # ------------------------------------------------------------------

  # `i` is the 1-based index within THIS generation call (which file block: v1, v2…);
  # `slot` is the target b-index on disk (2/3/4), which may differ when topping up.
  # The catalog label is `V{slot-1}` (slot 2 → V1).
  defp build_variation(i, slot, files, base, cfg, taken) do
    prefix = "v#{i}/"
    vnum = slot - 1
    {vname, vdesc} = parse_idea(files[prefix <> "idea.md"], base.name, vnum)
    vslug = Catalog.slug(vname)
    b = slot
    vtask_id = "#{Catalog.pad3(base.num)}_#{Catalog.pad3(b)}_#{vslug}_01"

    # Distinctness gate (docs/12 §5.1 item 4): a variation whose co-authored solution has
    # the SAME public-function set as the base or an already-accepted sibling is rejected
    # here — BEFORE the blind solve + grading cycle — so the LLM cost is never spent.
    # Skipped when the set is empty (bundle / no public defs: nothing to compare).
    if duplicate_public_fn_set?(files[prefix <> "solution.ex"], taken) do
      var_set = public_fn_set(files[prefix <> "solution.ex"])

      Logger.info(
        "VARIATION #{vtask_id}: rejected pre-cycle — not distinct (#{fn_set_str(var_set)})"
      )

      not_distinct_outcome(vtask_id, base.num, vname, var_set)
    else
      build_variation_cycle(prefix, files, base, cfg, {vtask_id, vname, vdesc, vnum, vslug, b})
    end
  end

  # The staged blind-solve + shared-cycle path for a distinct variation (extracted so the
  # distinctness gate above can early-return without opening a per-cycle log).
  defp build_variation_cycle(prefix, files, base, cfg, {vtask_id, vname, vdesc, vnum, vslug, b}) do
    handle = CycleLog.open(cfg, vtask_id)
    Logger.info("VARIATION #{vtask_id}: #{vname}")

    outcome =
      try do
        # The variations call CO-AUTHORS prompt+harness+solution in one reply, so
        # its solution can encode knowledge of the tests — an under-specified
        # prompt would sail through because the same mind wrote both sides
        # (docs/10 §1.2/R4b). Discard the co-authored solution and re-solve BLIND
        # from the variation prompt alone (mirrors Base Step B); the cycle then
        # grades the blind solution. GEN_SKIP_VARIATION_BLIND=1 restores the old
        # (cheaper, unscreened) behavior.
        solution =
          if cfg.skip_variation_blind do
            files[prefix <> "solution.ex"]
          else
            case blind_solution(vtask_id, files[prefix <> "prompt.md"], cfg) do
              {:ok, sol} -> sol
              {:error, reason} -> throw({:blind_solve_failed, reason})
            end
          end

        triplet = %{
          "prompt.md" => files[prefix <> "prompt.md"],
          "test_harness.exs" => files[prefix <> "test_harness.exs"],
          "solution.ex" => solution
        }

        ctx = %{
          dir: Path.join(cfg.staging_dir, vtask_id),
          mutant_dir: Path.join(cfg.staging_dir, vtask_id <> "_mut"),
          id: vtask_id
        }

        result = Cycle.run(triplet, ctx, cfg)
        stats = Cycle.grade_stats(result.grade)

        if result.status == :accepted do
          _ = Cycle.promote(cfg, vtask_id, result.files)
          _ = Catalog.insert_variation!(cfg, base.num, "V#{vnum}", vname, vdesc)

          seed = %{
            num: base.num,
            name: vname,
            slug: vslug,
            b: b,
            task_id: vtask_id,
            files: result.files
          }

          variation_outcome(vtask_id, base.num, vname, :accepted, result, stats, seed, nil)
        else
          variation_outcome(
            vtask_id,
            base.num,
            vname,
            :rejected,
            result,
            stats,
            nil,
            result.reason || Cycle.reason_for(result.grade)
          )
        end
      rescue
        e ->
          Logger.error(
            "variation #{vtask_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__)
          )

          Cycle.outcome(
            id: vtask_id,
            kind: :variation,
            num: base.num,
            name: vname,
            status: :error,
            reason: Exception.message(e)
          )
      catch
        {:blind_solve_failed, reason} ->
          Logger.error("variation #{vtask_id}: blind solve failed: #{inspect(reason)}")

          Cycle.outcome(
            id: vtask_id,
            kind: :variation,
            num: base.num,
            name: vname,
            status: :error,
            reason: "blind solve failed: #{inspect(reason)}"
          )
      end

    CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
    outcome
  end

  # The blind Step-B solve for one variation: the solver sees the variation's
  # prompt.md ONLY (never the harness), exactly like Base Step B. Returns
  # `{:ok, solution_source}` or `{:error, reason}`. Public (@doc false) so the seam
  # is unit-testable with a fake transport.
  @doc false
  @spec blind_solution(String.t(), String.t(), Config.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def blind_solution(vtask_id, prompt_md, %Config{} = cfg, step \\ "variation_blind_solve") do
    {system, user} = Prompts.base_solve(prompt_md)

    case Cycle.generate(
           cfg,
           vtask_id,
           step,
           system,
           user,
           &Reply.validate_answer/1
         ) do
      {:ok, answer} -> {:ok, answer["solution.ex"]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp variation_outcome(id, num, name, status, result, stats, seed, reason) do
    Cycle.outcome(
      id: id,
      kind: :variation,
      num: num,
      name: name,
      status: status,
      attempts: result.attempts,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      mutant_failed: result.mutant_failed,
      mutation: result.mutation,
      reason: reason,
      seed: seed
    )
  end

  # ------------------------------------------------------------------
  # idea.md → {name, description}
  # ------------------------------------------------------------------

  defp parse_idea(nil, base_name, n), do: {"#{base_name} — Variation #{n}", ""}

  defp parse_idea(idea_md, base_name, n) do
    lines = String.split(idea_md, "\n")
    {_blanks, rest} = Enum.split_while(lines, &(String.trim(&1) == ""))

    {name, body} =
      case rest do
        [header | tail] ->
          case Regex.run(@variation_header, header) do
            [_, nm] -> {String.trim(nm), Enum.join(tail, "\n")}
            _ -> {"#{base_name} — Variation #{n}", idea_md}
          end

        [] ->
          {"#{base_name} — Variation #{n}", idea_md}
      end

    desc = String.trim(body)
    desc = if desc == "", do: String.trim(idea_md), else: desc
    {name, desc}
  end
end
