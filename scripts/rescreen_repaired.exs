# rescreen_repaired.exs — retroactive blind screen for REPAIRED accepts (docs/12 §5.2).
#
# A base/variation accepted after ≥1 repair attempt has an unverified blind
# property: the fix prompt saw the failure report (test names, missing-function
# errors), so "the solver went green" proves nothing about the prompt alone —
# 101_002 was accepted exactly this way and its harness asserted a function the
# prompt never mentioned (found by the 2026-07-12 spot check).
#
# This script only computes the suspect POPULATION and drives the existing
# screen (`scripts/screen_blind_solve.exs`) over it — one mechanism, one ledger
# (`logs/screen_blind.jsonl`, content-keyed by sha256(prompt.md), resume-free).
# A FAIL quarantines for triage (fix the prompt like 101_002, or judge the
# harness); nothing is auto-edited.
#
# Usage:
#   mix run scripts/rescreen_repaired.exs                # DRY: list the population + status
#   mix run scripts/rescreen_repaired.exs -- --go        # run the screen (PAID: ≤1 call/task)
#   mix run scripts/rescreen_repaired.exs -- --report    # per-task verdicts from the ledger
#
# Population = latest runs.jsonl record per task id, kind base|variation,
# outcome accepted, attempts > 1 (attempts is 1-based: 1 = first-grade accept,
# blind property intact), dir still present under tasks/. The population file is
# written to logs/rescreen_repaired_population.txt on every invocation.

defmodule RescreenRepaired do
  @moduledoc false

  @runs "logs/runs.jsonl"
  @population "logs/rescreen_repaired_population.txt"
  @screen_ledger "logs/screen_blind.jsonl"
  @triage_ledger "logs/screen_triage.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [go: :boolean, report: :boolean])

    suspects = population()
    File.write!(@population, Enum.join(suspects, "\n") <> "\n")

    IO.puts(
      "Repaired-accept population: #{length(suspects)} task(s) " <>
        "(written to #{@population})"
    )

    cond do
      opts[:report] -> report(suspects)
      opts[:go] -> go(suspects)
      true -> dry(suspects)
    end
  end

  # Latest accepted record per id wins: a task re-accepted cleanly after a fix
  # must not stay a suspect because an OLDER record had repairs.
  defp population do
    @runs
    |> File.stream!()
    |> Enum.reduce(%{}, fn line, acc ->
      case JSON.decode(line) do
        {:ok, %{"kind" => k, "outcome" => "accepted", "id" => id} = d}
        when k in ["base", "variation"] ->
          Map.put(acc, id, d)

        _ ->
          acc
      end
    end)
    |> Enum.filter(fn {id, d} ->
      (d["attempts"] || 1) > 1 and File.dir?(Path.join("tasks", id))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp dry(suspects) do
    {screened, unscreened} = split_by_ledger(suspects)

    IO.puts("""

    Already screened for the CURRENT prompt content: #{length(screened)}
    Still to screen: #{length(unscreened)}
    Estimated cost: ~#{length(unscreened)} solver call(s) (sequential; the
    transport rides usage-limit windows). Run with `-- --go`.
    """)

    Enum.each(unscreened, &IO.puts("  #{&1}"))
  end

  defp go([]), do: IO.puts("population is empty — nothing to screen")

  defp go(suspects) do
    # Exact task names are valid globs for the screen's --only filter. The
    # screen's own ledger already skips tasks whose current prompt is screened.
    only = Enum.join(suspects, ",")

    {_, status} =
      System.cmd("mix", ["run", "scripts/screen_blind_solve.exs", "--", "--only", only],
        into: IO.stream(:stdio, :line)
      )

    IO.puts("\nscreen exited with status #{status} — verdicts: `-- --report`")
    if status != 0, do: System.halt(status)
  end

  defp report(suspects) do
    verdicts = ledger_by_sha()
    triaged = triage_by_task_sha()

    rows =
      Enum.map(suspects, fn id ->
        sha = prompt_sha(id)
        {id, Map.get(verdicts, sha), Map.get(triaged, {id, sha})}
      end)

    green = Enum.filter(rows, fn {_, v, _} -> v && v["green"] == true end)
    red = Enum.filter(rows, fn {_, v, _} -> v && v["green"] == false end)
    err = Enum.filter(rows, fn {_, v, _} -> v && v["green"] == nil end)
    missing = Enum.filter(rows, fn {_, v, _} -> v == nil end)

    # A FAIL whose entailment triage ruled the prompt sufficient (solver error)
    # is resolved — the historical quarantine→triage flow (docs/10 R12).
    {red_triaged, red_open} = Enum.split_with(red, fn {_, _, t} -> t && t["entailed"] == true end)

    IO.puts("""

    === RETRO BLIND SCREEN (repaired accepts, #{length(rows)} suspects) ===
      PASS (prompt-sufficient):            #{length(green)}
      FAIL, triaged entailed (kept as-is): #{length(red_triaged)}
      FAIL, OPEN (needs triage):           #{length(red_open)}
      transport errors:                    #{length(err)}
      not yet screened:                    #{length(missing)}
    """)

    for {id, v, _} <- red_open do
      IO.puts("  FAIL(open) #{id}")
      if v["reason"], do: IO.puts("       #{String.slice(to_string(v["reason"]), 0, 160)}")
    end

    for {id, _, _} <- missing, do: IO.puts("  todo #{id}")
  end

  defp triage_by_task_sha do
    case File.read(@triage_ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case JSON.decode(line) do
            {:ok, %{"task" => t, "sha" => sha} = d} -> Map.put(acc, {t, sha}, d)
            _ -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp split_by_ledger(suspects) do
    verdicts = ledger_by_sha()

    Enum.split_with(suspects, fn id ->
      case Map.get(verdicts, prompt_sha(id)) do
        %{"green" => g} when is_boolean(g) -> true
        _ -> false
      end
    end)
  end

  # Last ledger row per prompt sha wins (a re-screen overwrites the verdict).
  defp ledger_by_sha do
    case File.read(@screen_ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case JSON.decode(line) do
            {:ok, %{"sha" => sha} = d} -> Map.put(acc, sha, d)
            _ -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp prompt_sha(id) do
    GenTask.CycleLog.content_sha(File.read!(Path.join(["tasks", id, "prompt.md"])))
  end
end

RescreenRepaired.main(System.argv())
