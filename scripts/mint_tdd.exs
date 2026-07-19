# mint_tdd.exs — TDD-inverse dirs (docs/13 §2.8; Kamil unparked 2026-07-19).
#
#   mix run scripts/mint_tdd.exs [--dry-run] [--limit N] [--only "glob"]
#
# For every eligible single-module `_01` root, mint `tdd_<family>/` holding
# VERBATIM byte-copies of the parent gold (solution.ex) + harness
# (test_harness.exs) and a prompt built by `GenTask.TddTemplate` embedding the
# harness — tests-as-spec, the inverse of `wt_`. Deterministic, no LLM.
#
# Per-dir gate: the staged dir must grade PERFECT via the real evaluator
# (shape :tdd — the copied harness against the copied gold, overall 1.0 with
# zero warnings). Non-vacuity is the parent's own standing mutant record over
# the SAME bytes, and `validate --mutants` covers :tdd corpus-wide from now
# on. Rejects are sha-ledgered in logs/tdd_rejected.jsonl (a re-run never
# re-evaluates a dead root); existing tdd_ dirs skip. Skips: bundle roots
# (multi-file golds — the bundle-FIM shape owns those), Postgres-tier roots
# (manifest db: :postgres — not gradable unattended).

alias GenTask.CycleLog

defmodule MintTdd do
  @moduledoc false

  @reject_ledger "logs/tdd_rejected.jsonl"

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
      |> Enum.flat_map(&candidate(&1, dead))

    candidates = if opts[:limit], do: Enum.take(candidates, opts[:limit]), else: candidates

    IO.puts("tdd candidates (eligible roots without a tdd_ dir): #{length(candidates)}")

    results =
      if dry? do
        Enum.map(candidates, fn _ -> :would_attempt end)
      else
        Enum.map(candidates, &mint_one/1)
      end

    IO.puts("tdd: #{inspect(Enum.frequencies(results))}")

    if not dry? and Enum.any?(results, &(&1 == :minted)) do
      IO.puts("""
      New tdd_ dirs minted. Validate + commit:
        elixir scripts/validate.exs --only "tdd_*"
      """)
    end
  end

  defp candidate(root_dir, dead) do
    base = Path.basename(root_dir)
    family = String.replace_suffix(base, "_01", "")
    sol_path = Path.join(root_dir, "solution.ex")
    harness_path = Path.join(root_dir, "test_harness.exs")
    manifest = Path.join(root_dir, "manifest.exs")
    tdd_dir = "tasks/tdd_#{family}"

    with true <- File.regular?(sol_path),
         true <- File.regular?(harness_path),
         false <- File.dir?(tdd_dir),
         sol = File.read!(sol_path),
         false <- EvalTask.Bundle.bundle?(sol),
         false <- File.regular?(manifest) and File.read!(manifest) =~ ~r/db:\s*:postgres/,
         sha = CycleLog.content_sha(sol <> File.read!(harness_path)),
         false <- MapSet.member?(dead, sha) do
      [%{root: root_dir, family: family, dir: tdd_dir, sha: sha}]
    else
      _ -> []
    end
  end

  defp mint_one(cand) do
    harness = File.read!(Path.join(cand.root, "test_harness.exs"))

    File.mkdir_p!(cand.dir)
    File.write!(Path.join(cand.dir, "prompt.md"), GenTask.TddTemplate.prompt(harness))
    File.cp!(Path.join(cand.root, "solution.ex"), Path.join(cand.dir, "solution.ex"))
    File.cp!(Path.join(cand.root, "test_harness.exs"), Path.join(cand.dir, "test_harness.exs"))

    json = grade(cand.dir, "solution.ex")

    if perfect?(json) do
      IO.puts("  minted #{Path.basename(cand.dir)}")
      :minted
    else
      File.rm_rf!(cand.dir)
      record_dead(cand, "not perfect via evaluator: #{summary(json)}")
      :rejected
    end
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

  defp record_dead(cand, why) do
    row = %{root: cand.root, key: cand.sha, why: why, ts: DateTime.utc_now()}
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
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: MintTdd.main(System.argv())
