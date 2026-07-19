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

      for work <- Work.derived(cfg) do
        missing = work.missing.(seed, cfg)

        cond do
          missing == 0 ->
            IO.puts("  #{work.key}: complete")

          opts[:dry_run] ->
            IO.puts("  #{work.key}: #{missing} unit(s) OWED [dry-run]")

          true ->
            IO.puts("  #{work.key}: #{missing} unit(s) owed — running...")
            {mod, fun} = work.runner

            for outcome <- apply(mod, fun, [seed, cfg]) do
              IO.puts("    → #{outcome.status} #{outcome.reason || ""}")
            end
        end
      end
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end
end

unless System.get_env("SCRIPTS_NO_AUTORUN"), do: DeriveFamily.main(System.argv())
