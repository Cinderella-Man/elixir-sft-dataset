# mint_specfim.exs — spec-FIM units (docs/13 §2.8; Kamil unparked 2026-07-19).
#
#   mix run scripts/mint_specfim.exs [--dry-run] [--limit N] [--only "glob"]
#
# For every `@spec` attribute of every eligible single-module `_01` root, mint
# `specfim_<family>_NN/` (NN from 02 — the _01 suffix belongs to parents):
# prompt.md = `GenTask.SpecFimTemplate` over the skeleton (the parent module
# with that one attribute replaced by the `# TODO: @spec` marker at its
# indent), solution.ex = the attribute's VERBATIM source span. Deterministic,
# no LLM. Shape `:spec_fim` grades by normalized AST equality
# (EvalTask.Runner.run_spec_fim); spec TRUTH is the parent dialyzer gate's
# standing verdict over identical bytes.
#
# Per-unit gates (a bad carve rejects, never ships):
#   1. the carved span parses as exactly ONE `@spec` attribute (F24 class);
#   2. name/arity unique among the root's spec attributes (ambiguous → reject);
#   3. byte round-trip: marker line swapped back for the span reproduces the
#      parent EXACTLY;
#   4. the staged unit grades PERFECT via the real evaluator;
#   5. grader non-vacuity: a deterministically MUTATED spec (return type
#      replaced) must score 0 against the unit — proving the equality check
#      can fail.
# Rejects sha-ledgered in logs/specfim_rejected.jsonl; existing dirs skip.

alias GenTask.{CycleLog, SpecFimTemplate}

defmodule MintSpecfim do
  @moduledoc false

  @reject_ledger "logs/specfim_rejected.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [dry_run: :boolean, limit: :integer, only: :string])

    dry? = opts[:dry_run] || false
    dead = dead_keys()

    candidates =
      Path.wildcard("tasks/*_01")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn dir ->
        base = Path.basename(dir)

        match?({_, ""}, Integer.parse(hd(String.split(base, "_")))) and
          (opts[:only] == nil or matches_only?(base, opts[:only]))
      end)
      |> Enum.sort()
      |> Enum.flat_map(&root_candidates(&1, dead))

    candidates = if opts[:limit], do: Enum.take(candidates, opts[:limit]), else: candidates

    IO.puts("specfim candidates (uncarved @spec sites): #{length(candidates)}")

    results =
      if dry? do
        Enum.map(candidates, fn _ -> :would_attempt end)
      else
        Enum.map(candidates, &mint_one/1)
      end

    IO.puts("specfim: #{inspect(Enum.frequencies(results))}")

    if not dry? and Enum.any?(results, &(&1 == :minted)) do
      IO.puts("""
      New specfim_ dirs minted. Validate + commit:
        elixir scripts/validate.exs --only "specfim_*"
      """)
    end
  end

  # ── candidate enumeration ───────────────────────────────────────────────────

  defp root_candidates(root_dir, dead) do
    base = Path.basename(root_dir)
    family = String.replace_suffix(base, "_01", "")
    sol_path = Path.join(root_dir, "solution.ex")
    manifest = Path.join(root_dir, "manifest.exs")

    with true <- File.regular?(sol_path),
         true <- File.regular?(Path.join(root_dir, "test_harness.exs")),
         src = File.read!(sol_path),
         false <- EvalTask.Bundle.bundle?(src),
         false <- File.regular?(manifest) and File.read!(manifest) =~ ~r/db:\s*:postgres/ do
      sol_sha = CycleLog.content_sha(src)
      covered = covered_sites(family)

      src
      |> spec_sites()
      |> Enum.reject(fn site -> MapSet.member?(covered, site.id) end)
      |> Enum.reject(fn site -> MapSet.member?(dead, dead_key(sol_sha, site_key(site))) end)
      |> Enum.map(fn site ->
        %{root: root_dir, family: family, src: src, sha: sol_sha, site: site}
      end)
    else
      _ -> []
    end
  end

  # The carve lives in GenTask.SpecFim — ONE implementation shared with the
  # drift gate (resync_specfim_embeds.exs).
  defp spec_sites(src), do: GenTask.SpecFim.spec_sites(src)

  # Sites already carved by a live specfim_ child of this family — matched by
  # the "name/arity" id embedded in the child's prompt heading.
  defp covered_sites(family) do
    Path.wildcard("tasks/specfim_#{family}_*")
    |> Enum.filter(&File.dir?/1)
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
  end

  # ── minting one site ────────────────────────────────────────────────────────

  defp mint_one(%{site: %{id: {:invalid, why}} = site} = cand) do
    record_dead(cand, "site: " <> why, site_key(site))
    :uncarvable
  end

  defp mint_one(cand) do
    site = cand.site

    # Gate 3: byte round-trip — the marker swapped back for the span must
    # reproduce the parent exactly.
    if not GenTask.SpecFim.round_trip?(cand.src, site) do
      record_dead(cand, "carve: round-trip mismatch", site_key(cand.site))
      :uncarvable
    else
      [name, arity] = String.split(site.id, "/")

      stage_and_gate(
        cand,
        GenTask.SpecFim.skeleton(cand.src, site),
        name,
        String.to_integer(arity)
      )
    end
  end

  defp stage_and_gate(cand, skeleton, name, arity) do
    n = next_index(cand.family)
    dir = "tasks/specfim_#{cand.family}_#{String.pad_leading(to_string(n), 2, "0")}"

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "prompt.md"), SpecFimTemplate.prompt(name, arity, skeleton))
    File.write!(Path.join(dir, "solution.ex"), String.trim_trailing(cand.site.span, "\n"))

    real = grade(dir, "solution.ex")

    cond do
      not perfect?(real) ->
        File.rm_rf!(dir)
        record_dead(cand, "not perfect via :spec_fim evaluator: #{summary(real)}", cand.site.id)
        :rejected

      true ->
        # Gate 5: the grader must be able to FAIL — a return-type-mutated spec
        # scores 0 or the unit is vacuous by construction.
        mutant = mutate_spec(cand.site.span)
        File.write!(Path.join(dir, "mutant.ex"), mutant)
        mut = grade(dir, "mutant.ex")
        File.rm!(Path.join(dir, "mutant.ex"))

        if (mut["tests_failed"] || 0) > 0 do
          IO.puts("  minted #{Path.basename(dir)} (#{cand.site.id})")
          :minted
        else
          File.rm_rf!(dir)
          record_dead(cand, "vacuous: mutated spec still scores perfect", cand.site.id)
          :vacuous
        end
    end
  end

  # Deterministic spec mutant: the return type becomes a fresh atom no real
  # spec uses — normalized-AST equality with the gold must fail.
  @doc false
  def mutate_spec(span) do
    Regex.replace(~r/(::(?!.*::).*)$/s, span, ":: :spec_fim_mutant")
  end

  defp next_index(family) do
    Path.wildcard("tasks/specfim_#{family}_*")
    |> Enum.map(fn d ->
      case d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse() do
        {n, ""} -> n
        _ -> 1
      end
    end)
    |> Enum.max(fn -> 1 end)
    |> Kernel.+(1)
  end

  # ── plumbing (mint_sfim pattern) ────────────────────────────────────────────

  defp grade(dir, sol) do
    eval = Path.join(File.cwd!(), "scripts/eval_task.exs")
    timeout_s = System.get_env("EVAL_TIMEOUT_S", "240")

    {out, _} =
      System.cmd("timeout", ["--signal=KILL", timeout_s, "elixir", eval, dir, sol],
        stderr_to_stdout: true
      )

    line =
      out
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find("{}", &String.starts_with?(&1, "{"))

    case Jason.decode(line) do
      {:ok, json} -> json
      {:error, _} -> %{}
    end
  end

  defp perfect?(json) do
    json["compiled"] == true and (json["tests_passed"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and (json["tests_errors"] || 0) == 0 and
      get_in(json, ["score", "overall"]) == 1.0
  end

  defp summary(json) do
    "compiled=#{json["compiled"]} passed=#{json["tests_passed"]}/#{json["tests_total"]} " <>
      "overall=#{get_in(json, ["score", "overall"])}"
  end

  defp site_key(%{id: {:invalid, _}, lo: lo}), do: "invalid@#{lo}"
  defp site_key(%{id: id}), do: id

  defp dead_key(sha, site_id), do: "#{sha}:#{site_id}"

  defp record_dead(cand, why, site_id) do
    row = %{
      root: cand.root,
      key: dead_key(cand.sha, site_id),
      site: inspect(site_id),
      why: why,
      ts: DateTime.utc_now()
    }

    File.write!(@reject_ledger, Jason.encode!(row) <> "\n", [:append])
  end

  defp dead_keys do
    case File.read(@reject_ledger) do
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

  defp matches_only?(base, only) do
    only
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      re = glob |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/^#{re}$/, base)
    end)
  end
end

# Loadable from lib (GenTask.DeriveMiners) with SCRIPTS_NO_AUTORUN=1 — the
# script stays the single implementation of this miner.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: MintSpecfim.main(System.argv())
