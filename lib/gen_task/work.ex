defmodule GenTask.Work do
  @moduledoc """
  **The registry of every kind of derivative work the pipeline performs on a task
  set** — the single place that answers "what should exist for each `_01`, does it
  exist yet, and how is it produced?".

  Everything that plans or performs backfill consults this module, so the whole
  pipeline stays consistent and *idempotent*: run it as many times as you like and
  only the missing pieces are produced.

    * `GenTask.Catalog.seed/2` derives its `needs_*` flags from `missing/3`
    * `GenTask.CLI.run_backfill_item/4` executes the `:derived`-stage entries
      generically (a new deterministic work type needs NO cli change)
    * `scripts/work_status.exs` prints the live work-type × corpus matrix

  ## Adding a new work type

  Add one entry to `all/0` with:

    * `key` — atom id (also the `needs_…?` vocabulary)
    * `desc` — one line for status output
    * `llm?` — whether producing a unit consumes `claude` calls
    * `stage` — when the executor runs it:
        - `:expand`    — creates NEW sibling `_01` seeds (variations); runs first
        - `:per_seed`  — runs on each `_01` with its own driver (fim)
        - `:derived`   — simple per-seed derivation `run.(seed_map, cfg)` returning
          outcome maps; executed generically for the seed AND any freshly-expanded
          seeds (wtest, tfim, and most future kinds: de-doc, inverse, …)
    * `skip?` — reads the work type's `GEN_SKIP_*` flag from the config
    * `missing` — `(seed, cfg) -> non_neg_integer` units still to produce (0 = done)
    * `runner` — for `:derived`: `{module, fun}` called as `fun(seed_map, cfg)`

  `missing/2` MUST be pure disk/config inspection (cheap, re-runnable); anything
  gate-expensive belongs in the runner, guarded by its own negative cache
  (see `tfim_rejected.jsonl` / `seed_verdicts.jsonl`).
  """

  alias GenTask.{Catalog, Config}

  @type stage :: :expand | :per_seed | :derived
  @type entry :: %{
          key: atom(),
          desc: String.t(),
          llm?: boolean(),
          stage: stage(),
          skip?: (Config.t() -> boolean()),
          missing: (Catalog.Seed.t(), Config.t() -> non_neg_integer()),
          runner: {module(), atom()} | nil
        }

  @doc "Every registered work type, in execution order."
  @spec all() :: [entry()]
  def all do
    [
      %{
        key: :variations,
        desc: "3 distinct problem variations per base idea (b=002..004)",
        llm?: true,
        stage: :expand,
        skip?: & &1.skip_variations,
        missing: &missing_variations/2,
        runner: nil
      },
      %{
        key: :fim,
        desc: "code fill-in-the-middle subtasks per _01 (…_02+)",
        llm?: true,
        stage: :per_seed,
        skip?: & &1.skip_fim,
        missing: &missing_fim/2,
        runner: nil
      },
      %{
        key: :write_test,
        desc: "one write-tests derivative per _01 (wt_…)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_write_test,
        missing: &missing_write_test/2,
        runner: {GenTask.WriteTest, :run}
      },
      %{
        key: :test_fim,
        desc: "test fill-in-the-middle derivatives per _01 (tfim_…_0d)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_test_fim,
        missing: &missing_test_fim/2,
        runner: {GenTask.TestFim, :run}
      }
      # Future work types slot in here, e.g.:
      # %{key: :dedoc, desc: "docs-stripped 'add specs and docs' pair per _01",
      #   llm?: false, stage: :derived, skip?: & &1.skip_dedoc,
      #   missing: &missing_dedoc/2, runner: {GenTask.Dedoc, :run}}
    ]
  end

  @doc "The registry entry for `key` (raises on unknown key)."
  @spec fetch!(atom()) :: entry()
  def fetch!(key) do
    Enum.find(all(), &(&1.key == key)) ||
      raise ArgumentError, "unknown work type #{inspect(key)}"
  end

  @doc "Units of `key` still missing for `seed` (0 when complete or not applicable)."
  @spec missing(atom(), Catalog.Seed.t(), Config.t()) :: non_neg_integer()
  def missing(key, seed, cfg), do: fetch!(key).missing.(seed, cfg)

  @doc "All work still pending for `seed`, as `%{key => missing_units}` (only > 0)."
  @spec pending(Catalog.Seed.t(), Config.t()) :: %{atom() => pos_integer()}
  def pending(seed, cfg) do
    for w <- all(), n = w.missing.(seed, cfg), n > 0, into: %{}, do: {w.key, n}
  end

  @doc "The `:derived`-stage entries, minus any skipped by `cfg` — what the executor runs generically."
  @spec derived(Config.t()) :: [entry()]
  def derived(%Config{} = cfg) do
    for w <- all(), w.stage == :derived, not w.skip?.(cfg), do: w
  end

  @doc """
  Corpus-wide status per work type, computed live from disk: for each entry —
  seeds it applies to, seeds complete, seeds pending, and total missing units.
  """
  @spec summary(Config.t()) :: [map()]
  def summary(%Config{} = cfg) do
    seeds = Catalog.all_seeds(cfg)

    for w <- all() do
      per_seed = Enum.map(seeds, &w.missing.(&1, cfg))

      applicable =
        Enum.count(Enum.zip(seeds, per_seed), fn {s, n} -> n > 0 or complete?(w, s, cfg) end)

      pending = Enum.count(per_seed, &(&1 > 0))

      %{
        key: w.key,
        desc: w.desc,
        llm?: w.llm?,
        stage: w.stage,
        skipped?: w.skip?.(cfg),
        applicable: applicable,
        complete: applicable - pending,
        pending_seeds: pending,
        missing_units: Enum.sum(per_seed)
      }
    end
  end

  @doc """
  Seeds whose CURRENT harness content carries a cached VACUOUS self-check verdict
  (`logs/seed_verdicts.jsonl`) **and** still have `wt_`/`tfim_` units missing — i.e.
  derivation the backfill executor is withholding (docs/10 R3). Read-only; keyed by
  content hash, so a fixed harness drops off this list on the next run.
  """
  @spec vacuous_blocked(Config.t()) :: [
          %{seed: Catalog.Seed.t(), pending: %{atom() => pos_integer()}}
        ]
  def vacuous_blocked(%Config{} = cfg) do
    gated = for w <- all(), w.stage == :derived, do: w

    for seed <- Catalog.all_seeds(cfg),
        not seed.skip?,
        pending = for(w <- gated, n = w.missing.(seed, cfg), n > 0, into: %{}, do: {w.key, n}),
        pending != %{},
        cached_vacuous?(cfg, seed) do
      %{seed: seed, pending: pending}
    end
  end

  defp cached_vacuous?(cfg, seed) do
    sol = File.read(Path.join(seed.dir, "solution.ex"))
    har = File.read(Path.join(seed.dir, "test_harness.exs"))

    with {:ok, sol_body} <- sol,
         {:ok, har_body} <- har,
         sha = GenTask.CycleLog.content_sha(sol_body <> har_body),
         {:ok, verdict} <- GenTask.CycleLog.cached_seed_verdict(cfg, seed.task_id, sha) do
      verdict["vacuous"] == true
    else
      _ -> false
    end
  end

  # A seed counts as "applicable and complete" when the work type could apply to it
  # (not structurally excluded) and nothing is missing. Structural exclusions:
  # variations apply only to bases; fim/wtest/tfim never apply to gradable-skip seeds.
  defp complete?(%{key: :variations}, seed, _cfg), do: seed.base?
  defp complete?(_entry, seed, _cfg), do: not seed.skip?

  # ---------------------------------------------------------------------------
  # Per-type missing/2 — the ONE place these rules live
  # ---------------------------------------------------------------------------

  @variation_slots 3

  defp missing_variations(%Catalog.Seed{base?: false}, _cfg), do: 0

  defp missing_variations(%Catalog.Seed{} = seed, cfg) do
    max(@variation_slots - Catalog.count_variations(cfg.tasks_dir, a(seed)), 0)
  end

  # FIM/wtest/tfim all grade against the parent harness; a gradable-skip
  # (Postgres-tier) parent can only ever grade `skipped`, so none can be minted
  # green (docs/06 §6, docs/09 §1) — FIM would additionally burn LLM repair calls.
  defp missing_fim(%Catalog.Seed{skip?: true}, _cfg), do: 0

  # Delegated to the generator so the registry counts only units the selector can
  # actually target (parent function pool minus covered/permanently-rejected —
  # see Fim.missing_units/2). `fim_max - count_fim` overcounts: a one-function
  # parent caps at one child and would stay "pending" forever.
  defp missing_fim(%Catalog.Seed{} = seed, cfg) do
    GenTask.Fim.missing_units(seed, cfg)
  end

  defp missing_write_test(%Catalog.Seed{skip?: true}, _cfg), do: 0

  defp missing_write_test(%Catalog.Seed{} = seed, cfg) do
    wt_dir = "#{cfg.tasks_dir}/wt_#{String.replace_suffix(seed.task_id, "_01", "")}"
    if File.dir?(wt_dir), do: 0, else: 1
  end

  defp missing_test_fim(%Catalog.Seed{skip?: true}, _cfg), do: 0

  # Delegated to the minter so the registry counts only units the executor can
  # actually produce (carvable top-level blocks, minus covered/rejected/unparsable
  # — see TestFim.mintable_candidates/2). `tfim_max - count_tfim` overcounts:
  # describe-grouped harnesses carve to fewer (often zero) blocks and would stay
  # "pending" forever, making the Phase 2 exit criterion (0 pending) unreachable.
  defp missing_test_fim(%Catalog.Seed{} = seed, cfg) do
    GenTask.TestFim.missing_units(seed, cfg)
  end

  defp a(%Catalog.Seed{num: num}), do: Catalog.pad3(num)
end
