# derive_family.exs — derive EVERY registered deterministic shape for chosen
# roots, in one command (Kamil 2026-07-19: "one generation on a brand-new task
# must produce the whole family").
#
#   mix run scripts/derive_family.exs -- 043_001*            # one family
#   mix run scripts/derive_family.exs -- --dry-run "0*"      # plan only
#
# This is the scoped MANUAL convenience over exactly the machinery the
# generation loop itself runs: `GenTask.Work`'s registry supplies what is owed
# (wt/tfim/bugfix/adapt/dedoc/sfim/tdd/specfim — anything registered
# `:derived`), each runner applies its own gates and reject ledgers, and the
# whole thing is idempotent (a re-run only produces what is missing). The
# loop path is `GEN_ONLY=topup scripts/run_detached.sh logs/topup.log mix
# run scripts/generate.exs`; a brand-new accepted root owes ALL of these
# automatically through the same registry.

defmodule DeriveFamily do
  @moduledoc false

  alias GenTask.{Catalog, Config, Work}

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, globs, _} = OptionParser.parse(argv, strict: [dry_run: :boolean])

    if globs == [] do
      IO.puts("usage: mix run scripts/derive_family.exs -- [--dry-run] <task glob>[,...]")
      System.halt(2)
    end

    cfg = Config.new([])

    seeds =
      Catalog.topup_seeds(cfg)
      |> Enum.filter(fn seed -> Enum.any?(globs, &match_glob?(seed.task_id, &1)) end)

    IO.puts("derive_family: #{length(seeds)} seed(s) match #{inspect(globs)}")

    for seed <- seeds do
      IO.puts("=== #{seed.task_id}")

      # Runners take the SAME files-bearing seed map the loop's CLI builds
      # (`fun(seed_map, cfg)` per the Work registry contract) — the bare
      # Catalog.Seed satisfies only the `missing` callbacks. And mirror the
      # loop's vacuous gate: wt_/tfim_ promote the harness (or its blocks) as
      # gold completions, so a harness that cannot kill a raise-mutant must
      # never derive (docs/10 R3).
      seed_map = seed_map(seed)

      vacuous? =
        seed_map != nil and GenTask.CLI.vacuous_seed?(cfg, seed, seed_map.files)

      for work <- Work.derived(cfg) do
        missing = work.missing.(seed, cfg)

        cond do
          missing == 0 ->
            IO.puts("  #{work.key}: complete")

          opts[:dry_run] ->
            IO.puts("  #{work.key}: #{missing} unit(s) OWED [dry-run]")

          seed_map == nil ->
            IO.puts("  #{work.key}: SKIPPED — #{seed.dir} is missing part of the triplet")

          vacuous? ->
            IO.puts(
              "  #{work.key}: SKIPPED — vacuous seed harness " <>
                "(fix test_harness.exs; see logs/seed_verdicts.jsonl)"
            )

          true ->
            IO.puts("  #{work.key}: #{missing} unit(s) owed — running...")
            {mod, fun} = work.runner

            for outcome <- apply(mod, fun, [seed_map, cfg]) do
              IO.puts("    → #{outcome.status} #{outcome.reason || ""}")
            end
        end
      end
    end
  end

  # The CLI's read_triplet/put_manifest/slug_of are private; rebuild the same
  # seed map here (manifest staged alongside — its absence changes nothing).
  defp seed_map(seed) do
    files =
      for f <- ["prompt.md", "test_harness.exs", "solution.ex"],
          path = Path.join(seed.dir, f),
          File.regular?(path),
          into: %{},
          do: {f, File.read!(path)}

    manifest = Path.join(seed.dir, "manifest.exs")

    files =
      if File.regular?(manifest),
        do: Map.put(files, "manifest.exs", File.read!(manifest)),
        else: files

    if map_size(files) >= 3 do
      slug =
        seed.task_id
        |> String.split("_")
        |> Enum.drop(2)
        |> Enum.drop(-1)
        |> Enum.join("_")

      %{
        num: seed.num,
        slug: slug,
        b: seed.b,
        task_id: seed.task_id,
        dir: seed.dir,
        files: files
      }
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end
end

unless System.get_env("SCRIPTS_NO_AUTORUN"), do: DeriveFamily.main(System.argv())
