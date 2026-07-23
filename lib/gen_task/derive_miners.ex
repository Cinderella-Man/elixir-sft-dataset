defmodule GenTask.DeriveMiners do
  @moduledoc """
  Work-registry runners for the deterministic standalone miners — sfim
  (code-FIM carve), tdd (tests-as-spec inversion), specfim (@spec carve) —
  so ONE generation run derives the complete family for a brand-new root
  (Kamil, 2026-07-19).

  The SCRIPT stays the single implementation of each miner (the F24
  single-source lesson): this module loads it once under
  `SCRIPTS_NO_AUTORUN=1` and drives it through its own `--only` CLI, so the
  loop and the manual path share every gate, ledger, and reject class
  byte-for-byte.

  Documented limitation: the miners operate on the repo-root `tasks/` +
  `logs/`. A Config pointing elsewhere (sandboxed tests, worktrees) is
  SKIPPED with an explicit outcome — never silently minted into the wrong
  corpus.
  """

  alias GenTask.{Config, Cycle}
  require Logger

  # Module names as strings, concat-ed at runtime: the script modules exist
  # only after Code.require_file, so a compile-time literal would (correctly)
  # trip --warnings-as-errors.
  @scripts %{
    sfim: {"scripts/mint_sfim.exs", "MintSfim"},
    tdd: {"scripts/mint_tdd.exs", "MintTdd"},
    specfim: {"scripts/mint_specfim.exs", "MintSpecfim"},
    bundlefim: {"scripts/mint_bundlefim.exs", "MintBundlefim"}
  }

  @doc false
  def sfim_run(seed, cfg), do: run(:sfim, seed, cfg)
  @doc false
  def tdd_run(seed, cfg), do: run(:tdd, seed, cfg)
  @doc false
  def specfim_run(seed, cfg), do: run(:specfim, seed, cfg)
  @doc false
  def bundlefim_run(seed, cfg), do: run(:bundlefim, seed, cfg)

  defp run(kind, seed, %Config{} = cfg) do
    id = "#{kind}:#{seed.task_id}"

    cond do
      # The miner scripts have their own CLIs and write for real — they know
      # nothing of GEN_DRY_RUN. Guard here or a "dry" topup mints into tasks/
      # (found live 2026-07-23: sfim carved 109_001_14/_15 under GEN_DRY_RUN=1).
      cfg.dry_run ->
        [outcome(id, kind, seed, :skipped, "#{kind} miner skipped — dry-run")]

      Path.expand(cfg.tasks_dir) != Path.expand("tasks") ->
        [
          outcome(
            id,
            kind,
            seed,
            :skipped,
            "#{kind} miner is repo-root-only (tasks_dir=#{cfg.tasks_dir})"
          )
        ]

      true ->
        mod = load!(kind)
        before_n = family_units(kind, seed)
        apply(mod, :main, [["--only", seed.task_id]])
        after_n = family_units(kind, seed)

        [outcome(id, kind, seed, :accepted, "#{after_n - before_n} new unit(s), #{after_n} total")]
    end
  rescue
    e ->
      Logger.error("#{kind} derive crashed: " <> Exception.format(:error, e, __STACKTRACE__))
      [outcome("#{kind}:#{seed.task_id}", kind, seed, :error, Exception.message(e))]
  end

  defp load!(kind) do
    {script, mod_name} = Map.fetch!(@scripts, kind)
    mod = Module.concat([mod_name])

    unless Code.ensure_loaded?(mod) do
      prev = System.get_env("SCRIPTS_NO_AUTORUN")
      System.put_env("SCRIPTS_NO_AUTORUN", "1")

      try do
        Code.require_file(script)
      after
        if prev,
          do: System.put_env("SCRIPTS_NO_AUTORUN", prev),
          else: System.delete_env("SCRIPTS_NO_AUTORUN")
      end
    end

    mod
  end

  @doc "Live unit count for the seed's family under the given work kind."
  @spec family_units(:sfim | :tdd | :specfim, %{:task_id => String.t(), optional(any()) => any()}) ::
          non_neg_integer()
  def family_units(kind, seed) do
    family = String.replace_suffix(seed.task_id, "_01", "")

    case kind do
      :tdd ->
        if File.dir?("tasks/tdd_#{family}"), do: 1, else: 0

      :specfim ->
        Path.wildcard("tasks/specfim_#{family}_*") |> Enum.count(&File.dir?/1)

      kind when kind in [:sfim, :bundlefim] ->
        Path.wildcard("tasks/#{family}_*")
        |> Enum.count(fn d ->
          File.dir?(d) and
            case d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse() do
              {n, ""} -> n >= 2
              _ -> false
            end
        end)
    end
  end

  defp outcome(id, kind, seed, status, reason) do
    Cycle.outcome(
      id: id,
      kind: kind,
      name: seed.task_id,
      status: status,
      reason: reason,
      seed: seed.task_id
    )
  end
end
