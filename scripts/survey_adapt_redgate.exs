# survey_adapt_redgate.exs — RED-gate measurement for adaptation pairs (docs/13 §2.1).
#
# An adaptation pair = the BASE task's verified gold + a sibling VARIATION's
# prompt, framed as "modify this existing module to the new spec"; gold = the
# variation's verified solution; gate = the variation's existing harness. The
# critique's mint condition: only mint where the base gold grades RED under the
# variation harness — deterministic proof that the delta is real work (a base
# gold that already passes taught nothing).
#
# This tool ONLY measures (zero LLM, CPU evals): for every family NNN, grade
# the base (NNN_001_*_01) gold against each sibling variation's harness and
# ledger the verdict. The mint itself is a later registry entry (:adapt).
#
# Ledger: logs/adapt_redgate.jsonl keyed by (variation dir, base-solution sha,
# variation-harness sha) — resumable, re-run skips measured pairs.
#
#   mix run scripts/survey_adapt_redgate.exs             # measure what's missing
#   mix run scripts/survey_adapt_redgate.exs -- --report

alias GenTask.{Config, CycleLog, Evaluator}

defmodule SurveyAdaptRedgate do
  @moduledoc false

  @ledger "logs/adapt_redgate.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [report: :boolean])

    if opts[:report], do: report(), else: run()
  end

  defp run do
    cfg = Config.new([])
    done = done_keys()
    pairs = pairs()

    todo = Enum.reject(pairs, fn p -> MapSet.member?(done, key(p)) end)
    IO.puts("adapt RED-gate: #{length(pairs)} pair(s) total, #{length(todo)} to measure\n")

    Enum.each(todo, fn %{base: base, variation: var} = p ->
      base_sol = Path.join(base, "solution.ex")

      verdict =
        case Evaluator.grade(var, cfg, base_sol) do
          {:ok, json} ->
            cond do
              Evaluator.green?(json) -> :green_not_mintable
              json["compiled"] != true -> :red_compile
              true -> :red_tests
            end

          :timeout_or_crash ->
            :red_crash
        end

      append(Map.merge(key_map(p), %{verdict: verdict}))
      IO.puts("  #{verdict}  #{Path.basename(var)}  (base: #{Path.basename(base)})")
    end)

    report()
  end

  # Families group as NNN_: base = NNN_001_*_01, variations = NNN_00v_*_01 (v>=2).
  defp pairs do
    roots =
      Path.wildcard("tasks/[0-9]*_01")
      |> Enum.filter(&Regex.match?(~r/^tasks\/\d+_\d{3}_[a-z0-9_]+_01$/, &1))

    by_family =
      Enum.group_by(roots, fn dir ->
        [_, fam] = Regex.run(~r/^tasks\/(\d+)_\d{3}_/, dir)
        fam
      end)

    for {_fam, dirs} <- by_family,
        base = Enum.find(dirs, &Regex.match?(~r/_001_[a-z0-9_]+_01$/, &1)),
        base != nil,
        var <- Enum.sort(dirs),
        var != base,
        do: %{base: base, variation: var}
  end

  defp key(p), do: {Path.basename(p.variation), base_sha(p), harness_sha(p)}

  defp key_map(p) do
    %{
      variation: Path.basename(p.variation),
      base: Path.basename(p.base),
      base_solution_sha: base_sha(p),
      variation_harness_sha: harness_sha(p)
    }
  end

  defp base_sha(p), do: CycleLog.content_sha(File.read!(Path.join(p.base, "solution.ex")))

  defp harness_sha(p),
    do: CycleLog.content_sha(File.read!(Path.join(p.variation, "test_harness.exs")))

  defp done_keys do
    case File.read(@ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case JSON.decode(line) do
            {:ok, r} -> [{r["variation"], r["base_solution_sha"], r["variation_harness_sha"]}]
            _ -> []
          end
        end)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp append(row) do
    File.mkdir_p!("logs")

    File.write!(
      @ledger,
      JSON.encode!(Map.put(row, :ts, DateTime.utc_now() |> DateTime.to_iso8601())) <> "\n",
      [:append]
    )
  end

  defp report do
    rows =
      case File.read(@ledger) do
        {:ok, body} ->
          body |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

        _ ->
          []
      end

    counts = Enum.frequencies_by(rows, & &1["verdict"])
    mintable = Enum.count(rows, &String.starts_with?(&1["verdict"], "red"))

    IO.puts("""

    === ADAPT RED-GATE (#{length(rows)} measured pair(s), #{@ledger}) ===
      #{inspect(counts)}
      mintable (RED under variation harness): #{mintable}
    """)
  end
end

SurveyAdaptRedgate.main(System.argv())
