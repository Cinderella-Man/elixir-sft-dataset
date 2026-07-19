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
      },
      %{
        key: :bugfix,
        desc: "verified bug→fix repair pairs from killed semantic mutants (bugfix_…_NN)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_bugfix,
        missing: &missing_bugfix/2,
        runner: {GenTask.Bugfix, :run}
      },
      %{
        key: :adapt,
        desc: "brownfield adaptation pair per variation: base gold → variation spec (adapt_…)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_adapt,
        missing: &missing_adapt/2,
        runner: {GenTask.Adapt, :run}
      },
      %{
        key: :dedoc,
        desc: "docs-stripped 'add specs and docs' pair per _01 (dedoc_…)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_dedoc,
        missing: &missing_dedoc/2,
        runner: {GenTask.Dedoc, :run}
      },
      %{
        key: :sfim,
        desc: "deterministic code-FIM carve of every uncovered function per _01 (…_0N)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_sfim,
        missing: &missing_sfim/2,
        runner: {GenTask.DeriveMiners, :sfim_run}
      },
      %{
        key: :tdd,
        desc: "one tests-as-spec inversion per _01 (tdd_…)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_tdd,
        missing: &missing_tdd/2,
        runner: {GenTask.DeriveMiners, :tdd_run}
      },
      %{
        key: :specfim,
        desc: "one @spec-writing unit per typespec site per _01 (specfim_…_NN)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_specfim,
        missing: &missing_specfim/2,
        runner: {GenTask.DeriveMiners, :specfim_run}
      },
      %{
        key: :bundlefim,
        desc: "one write-this-file unit per bundle file of multi-file _01s (…_0N)",
        llm?: false,
        stage: :derived,
        skip?: & &1.skip_bundlefim,
        missing: &missing_bundlefim/2,
        runner: {GenTask.DeriveMiners, :bundlefim_run}
      }
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
  # variations apply only to bases; adapt only to variations; fim/wtest/tfim never
  # apply to gradable-skip seeds.
  defp complete?(%{key: :variations}, seed, _cfg), do: seed.base?
  defp complete?(%{key: :adapt}, seed, _cfg), do: not seed.base? and not seed.skip?
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

  defp missing_bugfix(%Catalog.Seed{skip?: true}, _cfg), do: 0

  # Delegated to the miner (docs/12 §5.1.10 honesty rule): counts only mutants
  # the miner can still legally attempt (diverse pool minus covered minus
  # ledger-rejected); bundle parents count 0 in v1.
  defp missing_bugfix(%Catalog.Seed{} = seed, cfg) do
    GenTask.Bugfix.missing_units(seed, cfg)
  end

  # Delegated to the minter (same honesty rule): a variation counts 1 only while
  # mintable — base seeds, gradable-skips, existing adapt_ dirs, and variations
  # whose CURRENT sha pair carries a `green_not_mintable` RED-gate verdict all
  # count 0 (the gate-expensive RED measurement itself lives in the runner).
  defp missing_adapt(%Catalog.Seed{} = seed, cfg) do
    GenTask.Adapt.missing_units(seed, cfg)
  end

  defp missing_dedoc(%Catalog.Seed{} = seed, cfg) do
    GenTask.Dedoc.missing_units(seed, cfg)
  end

  # ── deterministic miner counts (sfim / tdd / specfim, 2026-07-19) ───────────
  # Cheap disk-only planning proxies; the RUNNER's own census (the miner
  # script's, with its full gate + reject-ledger context) stays authoritative.

  defp missing_sfim(%Catalog.Seed{skip?: true}, _cfg), do: 0

  defp missing_sfim(%Catalog.Seed{} = seed, cfg) do
    root = Path.join(cfg.tasks_dir, seed.task_id)
    family = String.replace_suffix(seed.task_id, "_01", "")
    sol = Path.join(root, "solution.ex")

    with true <- File.regular?(sol),
         true <- File.regular?(Path.join(root, "test_harness.exs")),
         src = File.read!(sol),
         false <- EvalTask.Bundle.bundle?(src) do
      covered =
        Path.wildcard("#{cfg.tasks_dir}/#{family}_*")
        |> Enum.filter(fn d ->
          File.dir?(d) and
            match?(
              {n, ""} when n >= 2,
              d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse()
            )
        end)
        |> Enum.flat_map(fn d ->
          case File.read(Path.join(d, "solution.ex")) do
            {:ok, body} -> fn_names(body)
            _ -> []
          end
        end)
        |> MapSet.new()

      sha = GenTask.CycleLog.content_sha(src)
      dead = ledger_keys(cfg, "sfim_rejected.jsonl")

      src
      |> fn_names()
      |> Enum.reject(&MapSet.member?(covered, &1))
      |> Enum.reject(&MapSet.member?(dead, "#{sha}:#{&1}"))
      |> length()
    else
      _ -> 0
    end
  end

  defp missing_tdd(%Catalog.Seed{skip?: true}, _cfg), do: 0

  defp missing_tdd(%Catalog.Seed{} = seed, cfg) do
    root = Path.join(cfg.tasks_dir, seed.task_id)
    family = String.replace_suffix(seed.task_id, "_01", "")
    sol = Path.join(root, "solution.ex")
    harness = Path.join(root, "test_harness.exs")
    manifest = Path.join(root, "manifest.exs")

    with true <- File.regular?(sol),
         true <- File.regular?(harness),
         false <- File.dir?("#{cfg.tasks_dir}/tdd_#{family}"),
         src = File.read!(sol),
         false <- EvalTask.Bundle.bundle?(src),
         false <- File.regular?(manifest) and File.read!(manifest) =~ ~r/db:\s*:postgres/,
         sha = GenTask.CycleLog.content_sha(src <> File.read!(harness)),
         false <- MapSet.member?(ledger_keys(cfg, "tdd_rejected.jsonl"), sha) do
      1
    else
      _ -> 0
    end
  end

  defp missing_specfim(%Catalog.Seed{skip?: true}, _cfg), do: 0

  defp missing_specfim(%Catalog.Seed{} = seed, cfg) do
    root = Path.join(cfg.tasks_dir, seed.task_id)
    family = String.replace_suffix(seed.task_id, "_01", "")
    sol = Path.join(root, "solution.ex")
    manifest = Path.join(root, "manifest.exs")

    with true <- File.regular?(sol),
         true <- File.regular?(Path.join(root, "test_harness.exs")),
         src = File.read!(sol),
         false <- EvalTask.Bundle.bundle?(src),
         false <- File.regular?(manifest) and File.read!(manifest) =~ ~r/db:\s*:postgres/ do
      covered =
        Path.wildcard("#{cfg.tasks_dir}/specfim_#{family}_*")
        |> Enum.flat_map(fn d ->
          case File.read(Path.join(d, "prompt.md")) do
            {:ok, p} ->
              case Regex.run(~r/the `@spec` for\n?`([a-z_0-9?!]+\/\d+)` has been removed/, p) do
                [_, id] -> [id]
                _ -> []
              end

            _ ->
              []
          end
        end)
        |> MapSet.new()

      sha = GenTask.CycleLog.content_sha(src)
      dead = ledger_keys(cfg, "specfim_rejected.jsonl")

      GenTask.SpecFim.spec_sites(src)
      |> Enum.reject(&match?({:invalid, _}, &1.id))
      |> Enum.reject(&MapSet.member?(covered, &1.id))
      |> Enum.reject(&MapSet.member?(dead, "#{sha}:#{&1.id}"))
      |> length()
    else
      _ -> 0
    end
  end

  defp missing_bundlefim(%Catalog.Seed{skip?: true}, _cfg), do: 0

  defp missing_bundlefim(%Catalog.Seed{} = seed, cfg) do
    root = Path.join(cfg.tasks_dir, seed.task_id)
    family = String.replace_suffix(seed.task_id, "_01", "")
    sol = Path.join(root, "solution.ex")

    with true <- File.regular?(sol),
         true <- File.regular?(Path.join(root, "test_harness.exs")),
         src = File.read!(sol),
         true <- EvalTask.Bundle.bundle?(src) do
      covered =
        Path.wildcard("#{cfg.tasks_dir}/#{family}_*")
        |> Enum.filter(fn d ->
          File.dir?(d) and
            match?(
              {n, ""} when n >= 2,
              d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse()
            )
        end)
        |> Enum.flat_map(fn d ->
          case File.read(Path.join(d, "prompt.md")) do
            {:ok, p} ->
              case Regex.run(~r/## The bundle with `([^`\n]+)` missing/, p) do
                [_, path] -> [path]
                _ -> []
              end

            _ ->
              []
          end
        end)
        |> MapSet.new()

      sha = GenTask.CycleLog.content_sha(src)
      dead = ledger_keys(cfg, "bundlefim_rejected.jsonl")

      EvalTask.Bundle.parse(src)
      |> Enum.reject(fn {path, _} -> MapSet.member?(covered, path) end)
      |> Enum.reject(fn {path, _} -> MapSet.member?(dead, "#{sha}:#{path}") end)
      |> length()
    else
      _ -> 0
    end
  end

  defp fn_names(src) do
    case Code.string_to_quoted(src) do
      {:ok, ast} ->
        {_ast, acc} =
          Macro.prewalk(ast, [], fn
            {op, _m, [head | _]} = node, acc when op in [:def, :defp] ->
              case head_name(head) do
                nil -> {node, acc}
                n -> {node, [n | acc]}
              end

            node, acc ->
              {node, acc}
          end)

        acc |> Enum.reverse() |> Enum.uniq()

      _ ->
        []
    end
  end

  defp head_name({:when, _, [inner | _]}), do: head_name(inner)
  defp head_name({name, _, _}) when is_atom(name), do: to_string(name)
  defp head_name(_), do: nil

  defp ledger_keys(cfg, file) do
    case File.read(Path.join(cfg.logs_dir, file)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, %{"key" => k}} -> [k]
            _ -> []
          end
        end)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp a(%Catalog.Seed{num: num}), do: Catalog.pad3(num)
end
