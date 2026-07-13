# classify_survivors.exs — is a below-floor family DEFECTIVE, or at its CEILING?
#
# The semantic-mutant kill rate has a per-family ceiling (docs/13 §1.5.1): some
# mutants change nothing a caller can observe — an ETS `read_concurrency` flag, a
# recency counter's start value or step size, a private state field's layout. No
# legitimate public-API test can kill them; only a `:sys.get_state` reach-in
# could, and the S9 lint (rightly) forbids that. A family whose survivors are all
# internals is therefore AT ITS CEILING, not defective — and "fixing" it would
# mean shipping exactly the internals-pinning tests the lint exists to reject.
#
# This classifies each below-floor family's surviving mutants:
#
#   observable   — the mutation changes something a caller can see (a return
#                  value, an error, an ordering, a validation) => REAL GAP, the
#                  harness can and should pin it
#   internals    — the mutation is invisible through the public API => CEILING
#
# The verdict is advisory (a line-level heuristic), but it agrees with the gates:
# every family it calls AT CEILING is one whose strengthening attempt reached for
# :sys.get_state or ETS internals — because that was the only way to kill what
# was left.
#
#   mix run scripts/classify_survivors.exs                 # every below-floor family
#   mix run scripts/classify_survivors.exs -- --only "041_*"

defmodule ClassifySurvivors do
  @moduledoc false

  @measured "logs/semantic_mutants.jsonl"
  @floor 0.5

  # Mutation sites that cannot change observable behavior: ETS table options and
  # names, counter seeds/steps, private bookkeeping, logging.
  @internal ~r/read_concurrency|write_concurrency|:ordered_set|:set\b|:public|:private|
               :protected|counter|_table|table_name|seed|Logger|inspect|monitor|:name\]/x

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [only: :string])

    @measured
    |> latest_rows()
    |> Enum.filter(fn {task, row} ->
      row["killed"] / row["total"] < @floor and match_only?(task, opts[:only])
    end)
    |> Enum.sort_by(fn {_t, r} -> r["killed"] / r["total"] end)
    |> Enum.each(&report/1)
  end

  defp report({task, row}) do
    src = File.read!(Path.join(["tasks", task, "solution.ex"])) |> String.split("\n")
    survivors = row["survivors"] || []

    {internals, observable} =
      Enum.split_with(survivors, fn s ->
        line =
          case Regex.run(~r/^L(\d+)/, s) do
            [_, n] -> Enum.at(src, String.to_integer(n) - 1, "")
            _ -> ""
          end

        Regex.match?(@internal, line) or Regex.match?(@internal, s)
      end)

    rate = row["killed"] / row["total"]
    ceiling = (row["killed"] + length(internals)) / row["total"]

    verdict =
      cond do
        ceiling >= @floor and rate < @floor -> "AT CEILING (internals-only survivors)"
        true -> "REAL GAP (observable survivors the harness could pin)"
      end

    IO.puts("""

    #{task}
      kill rate #{fmt(rate)}   ceiling ≈ #{fmt(ceiling)}   → #{verdict}
      survivors: #{length(internals)} internals / #{length(observable)} observable\
    """)

    for s <- Enum.take(observable, 4), do: IO.puts("        observable: #{s}")
    for s <- Enum.take(internals, 3), do: IO.puts("        internals:  #{s}")
  end

  defp latest_rows(path) do
    path
    |> File.stream!()
    |> Enum.reduce(%{}, fn line, acc ->
      with {:ok, %{"task" => t, "total" => tot} = row} <- JSON.decode(line),
           true <- tot > 0,
           false <- String.starts_with?(t, "wt_"),
           true <- File.dir?(Path.join("tasks", t)) do
        prev = acc[t]
        if prev && prev["ts"] >= row["ts"], do: acc, else: Map.put(acc, t, row)
      else
        _ -> acc
      end
    end)
  end

  defp fmt(f), do: :erlang.float_to_binary(f, decimals: 2)

  defp match_only?(_t, nil), do: true

  defp match_only?(t, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, t)
    end)
  end
end

ClassifySurvivors.main(System.argv())
