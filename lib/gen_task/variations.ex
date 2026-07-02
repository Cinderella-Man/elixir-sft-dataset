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

  alias GenTask.{Catalog, Config, Cycle, CycleLog, Prompts, Reply}

  @variation_header ~r/^###\s+Task\s+\d+\s+-\s+V\d+\s+-\s+(.+?)\s*$/

  @doc "Generate up to three variations of `base` and cycle/promote each."
  @spec run(GenTask.Base.seed(), Config.t()) :: [map()]
  def run(base, %Config{} = cfg) do
    case gen_variations(base, cfg) do
      {:ok, files} -> Enum.map(1..3, fn n -> build_variation(n, files, base, cfg) end)
      {:error, out} -> [out]
    end
  end

  # ------------------------------------------------------------------
  # The shared 3-in-one generation call (its own log file)
  # ------------------------------------------------------------------

  defp gen_variations(base, cfg) do
    gen_id = "#{Catalog.pad3(base.num)}_variations"
    handle = CycleLog.open(cfg, gen_id)
    Logger.info("VARIATIONS gen for #{base.task_id}")

    result =
      try do
        tasks_md = File.read!(cfg.tasks_md)

        {system, user} =
          Prompts.variations(%{num: base.num, name: base.name}, base.files, tasks_md)

        case Cycle.opus(cfg, base.task_id, "variations", system, user) do
          {:ok, text, _meta} ->
            files = Reply.parse(text)

            case Reply.validate_variations(files) do
              :ok ->
                {:ok, files}

              {:error, msg} ->
                Logger.error("variations (#{base.task_id}): contract violation: #{msg}")
                {:error, gen_error(gen_id, base, msg)}
            end

          {:error, reason} ->
            {:error, gen_error(gen_id, base, inspect(reason))}
        end
      rescue
        e ->
          Logger.error("variations gen crashed: " <> Exception.format(:error, e, __STACKTRACE__))
          {:error, gen_error(gen_id, base, Exception.message(e))}
      end

    CycleLog.close(handle, if(match?({:ok, _}, result), do: :ok, else: :error))
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

  defp build_variation(n, files, base, cfg) do
    prefix = "v#{n}/"
    {vname, vdesc} = parse_idea(files[prefix <> "idea.md"], base.name, n)
    vslug = Catalog.slug(vname)
    b = n + 1
    vtask_id = "#{Catalog.pad3(base.num)}_#{Catalog.pad3(b)}_#{vslug}_01"

    handle = CycleLog.open(cfg, vtask_id)
    Logger.info("VARIATION #{vtask_id}: #{vname}")

    outcome =
      try do
        triplet = %{
          "prompt.md" => files[prefix <> "prompt.md"],
          "test_harness.exs" => files[prefix <> "test_harness.exs"],
          "solution.ex" => files[prefix <> "solution.ex"]
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
          _ = Catalog.insert_variation!(cfg, base.num, "V#{n}", vname, vdesc)

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
            Cycle.reason_for(result.grade)
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
      end

    CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
    outcome
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
