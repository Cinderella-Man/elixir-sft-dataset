# fuzz_survivors.exs — is a surviving semantic mutant OBSERVABLE at all?
#
# The verification layer behind every at-ceiling claim (docs/14 rule 11):
# `classify_survivors` is a line heuristic and it has already mislabeled a
# family once (077_001: 15 AVL-bookkeeping survivors read as "observable", and
# docs/14 called it "the hardest real gap" — public-API fuzzing proved every
# one behaviorally IDENTICAL to the reference). Before spending strengthen
# calls or hand effort on a below-floor family, run this.
#
# What it does per family: loads the LATEST semantic ledger row (sha-checked
# against disk), regenerates each surviving mutant textually, compiles the
# reference and the renamed mutant side by side, and compares them over
# thousands of deterministic adversarial operation sequences produced by that
# family's DRIVER. IDENTICAL across the sweep = unobservable in practice
# (ceiling member); DIVERGES = killable, and the witness case is printed.
#
# HONESTY RULE: argument generation cannot be family-generic (a GenServer's
# API is not an interval tree's). Each family needs a small DRIVER registered
# in @drivers below — ~20 lines mapping ops onto the module's public API. A
# family without a driver exits with instructions, NEVER a vacuous pass.
#
#   mix run scripts/fuzz_survivors.exs -- --only "077_001*"
#
# Zero LLM. Results print to stdout; treat a full-IDENTICAL result as the
# evidence to record an at-ceiling verdict in STATUS/docs.

alias GenTask.Mutation

defmodule FuzzSurvivors do
  @moduledoc false

  @measured "logs/semantic_mutants.jsonl"

  # ── DRIVER REGISTRY ──────────────────────────────────────────────────────────
  # A driver returns a deterministic list of {setup_ops, probe_calls} case
  # groups; run/2 executes them against a module and returns a comparable term.
  # Add one per family you need to fuzz; 077_001 is the worked example.

  @drivers %{
    "077_001" => :interval_tree
  }

  defp driver_cases(:interval_tree) do
    :rand.seed(:exsss, {77, 1, 20_260_713})

    gen = fn ->
      s = :rand.uniform(60) - 30
      {s, s + Enum.random([0, 0, 1, 1, 2, 3, 5, 8, 13])}
    end

    for n <- [1, 2, 3, 5, 8, 20, 60, 150], order <- [:random, :sorted, :reversed, :equal_heavy] do
      ivs =
        case order do
          :equal_heavy ->
            base = gen.()
            for _ <- 1..n, do: if(:rand.uniform(2) == 1, do: base, else: gen.())

          _ ->
            for _ <- 1..n, do: gen.()
        end

      ivs =
        case order do
          :sorted -> Enum.sort(ivs)
          :reversed -> ivs |> Enum.sort() |> Enum.reverse()
          _ -> ivs
        end

      queries =
        Enum.flat_map(ivs, fn {s, f} ->
          [{s, f}, {f, f + 3}, {s - 3, s}, {f + 1, f + 4}, {s - 4, s - 1}, {s, s}]
        end) ++ for(_ <- 1..30, do: gen.())

      points = Enum.flat_map(ivs, fn {s, f} -> [s, f, s - 1, f + 1, div(s + f, 2)] end)
      {ivs, queries, points}
    end
  end

  defp driver_run(:interval_tree, mod, cases) do
    Enum.map(cases, fn {ivs, queries, points} ->
      tree = Enum.reduce(ivs, mod.new(), &mod.insert(&2, &1))
      ov = Enum.map(queries, &(mod.overlapping(tree, &1) |> Enum.sort()))
      en = Enum.map(points, &(mod.enclosing(tree, &1) |> Enum.sort()))
      {ov, en}
    end)
  end

  # ── generic machinery ────────────────────────────────────────────────────────

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [only: :string])

    unless opts[:only] do
      IO.puts("usage: mix run scripts/fuzz_survivors.exs -- --only \"<family>*\"")
      System.halt(2)
    end

    dir =
      Path.wildcard("tasks/[0-9]*_01")
      |> Enum.find(&String.contains?(Path.basename(&1), String.trim_trailing(opts[:only], "*")))

    unless dir do
      IO.puts("no root task matches #{opts[:only]}")
      System.halt(2)
    end

    family = Path.basename(dir)
    key = family |> String.split("_") |> Enum.take(2) |> Enum.join("_")

    driver = @drivers[key]

    unless driver do
      IO.puts("""
      No fuzz driver registered for family #{key}.

      Add one to @drivers in scripts/fuzz_survivors.exs: a ~20-line pair of
      functions (driver_cases/1 building deterministic adversarial inputs,
      driver_run/3 mapping them onto the module's PUBLIC API — nothing else).
      A missing driver must never pass silently, so this is exit 1.
      """)

      System.halt(1)
    end

    fuzz(dir, family, driver)
  end

  defp fuzz(dir, family, driver) do
    src = File.read!(Path.join(dir, "solution.ex"))

    row = latest_row(family)

    unless row do
      IO.puts("no semantic ledger row for #{family} — run validate --semantic-mutants first")
      System.halt(2)
    end

    survivors = row["survivors"] || []
    muts = Mutation.semantic_mutants_textual(src) |> Map.new()
    [{ref_mod, _} | _] = Code.compile_string(src)
    cases = driver_cases(driver)
    ref_out = driver_run(driver, ref_mod, cases)

    [_, mod_name] = Regex.run(~r/defmodule\s+([\w.]+)/, src)

    results =
      for label <- survivors do
        result =
          case Map.fetch(muts, label) do
            :error ->
              :label_gone

            {:ok, mutated} ->
              renamed =
                String.replace(
                  mutated,
                  "defmodule #{mod_name}",
                  "defmodule #{mod_name}.FuzzMutant",
                  global: false
                )

              try do
                Code.compiler_options(ignore_module_conflict: true)
                [{mut_mod, _} | _] = Code.compile_string(renamed)
                out = driver_run(driver, mut_mod, cases)
                :code.purge(mut_mod)
                :code.delete(mut_mod)
                if out == ref_out, do: :identical, else: :diverges
              rescue
                e -> {:crash, Exception.message(e)}
              end
          end

        IO.puts("  #{String.pad_trailing(label, 24)} #{format(result)}")
        result
      end

    identical = Enum.count(results, &(&1 == :identical))

    IO.puts("""

    #{family}: #{identical}/#{length(results)} survivor(s) behaviorally IDENTICAL over \
    #{length(cases)} adversarial case groups.
    #{if identical == length(results), do: "ALL UNOBSERVABLE — record the family as AT CEILING.", else: "Divergent/crashing mutants are KILLABLE through the public API — real gap."}
    """)
  end

  defp format(:identical), do: "IDENTICAL"
  defp format(:diverges), do: "DIVERGES (killable!)"
  defp format(:label_gone), do: "label gone (mutator changed)"
  defp format({:crash, msg}), do: "CRASH: #{String.slice(msg, 0, 80)} (killable via crash)"

  defp latest_row(family) do
    case File.read(@measured) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case JSON.decode(line) do
            {:ok, %{"task" => t} = row} -> if t == family, do: [row], else: []
            _ -> []
          end
        end)
        |> Enum.max_by(& &1["ts"], fn -> nil end)

      _ ->
        nil
    end
  end
end

FuzzSurvivors.main(System.argv())
