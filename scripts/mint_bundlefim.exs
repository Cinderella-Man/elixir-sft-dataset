# mint_bundlefim.exs — file-level bundle-FIM units (docs/13 §2.8; Kamil
# unparked 2026-07-19).
#
#   mix run scripts/mint_bundlefim.exs [--dry-run] [--limit N] [--only "glob"]
#
# For every FILE of every multi-file bundle `_01` root, mint `<family>_0N/`
# (:fim shape): prompt.md = `GenTask.BundleFimTemplate` over the parent spec +
# the marker-stripped bundle with that file's entire content blanked to
# `# TODO`; solution.ex = the file's VERBATIM content. Deterministic, no LLM.
# `Runner.run_fim_bundle`/`reconstruct_bundle` already grade whole-file
# candidates against the parent harness — zero new eval surface.
#
# Per-unit gates:
#   1. the file body parses standalone (F24 class) and is non-trivial;
#   2. byte round-trip: hole→body reproduces the stripped parent exactly;
#   3. the staged unit grades PERFECT via the real :fim evaluator;
#   4. the gutted candidate (every def body → raise via EvalTask.Fim.mutate)
#      must make the parent harness FAIL; a non-compiling mutant proves
#      nothing and rejects (mutation-gate semantics).
# Rejects sha-ledgered in logs/bundlefim_rejected.jsonl; covered files (a
# live child naming the same path in its heading) skip.

alias GenTask.{BundleFimTemplate, CycleLog}
alias EvalTask.Bundle

defmodule MintBundlefim do
  @moduledoc false

  @reject_ledger "logs/bundlefim_rejected.jsonl"

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

    IO.puts("bundlefim candidates (uncarved bundle files): #{length(candidates)}")

    results =
      if dry? do
        Enum.map(candidates, fn _ -> :would_attempt end)
      else
        Enum.map(candidates, &mint_one/1)
      end

    IO.puts("bundlefim: #{inspect(Enum.frequencies(results))}")

    if not dry? and Enum.any?(results, &(&1 == :minted)) do
      IO.puts("""
      New bundle-FIM dirs minted. Validate + commit:
        elixir scripts/validate.exs --fim --only "<family globs>"
      """)
    end
  end

  defp root_candidates(root_dir, dead) do
    base = Path.basename(root_dir)
    family = String.replace_suffix(base, "_01", "")
    sol_path = Path.join(root_dir, "solution.ex")

    with true <- File.regular?(sol_path),
         true <- File.regular?(Path.join(root_dir, "test_harness.exs")),
         src = File.read!(sol_path),
         true <- Bundle.bundle?(src) do
      covered = covered_paths(family)
      sol_sha = CycleLog.content_sha(src)
      files = Bundle.parse(src)

      files
      |> Enum.reject(fn {path, _} -> MapSet.member?(covered, path) end)
      |> Enum.reject(fn {path, _} -> MapSet.member?(dead, dead_key(sol_sha, path)) end)
      |> Enum.map(fn {path, body} ->
        %{
          root: root_dir,
          family: family,
          src: src,
          sha: sol_sha,
          path: path,
          body: body,
          files: files
        }
      end)
    else
      _ -> []
    end
  end

  # Files already carved by a live child — matched by the path in the
  # template's own heading line.
  defp covered_paths(family) do
    Path.wildcard("tasks/#{family}_*")
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
  end

  defp mint_one(cand) do
    # Skeleton by parse-join, NOT textual replace (F26 sibling class: a parent
    # bundle gluing two <file> blocks glued the hole against the next
    # defmodule, which the format gate reflows). One blank line between parts
    # is formatter-stable; reconstruct_bundle matches per-file bodies, so the
    # seam normalization never affects grading; check_embeds rule (d) already
    # tolerates blank-line bundle seams.
    skeleton =
      cand.files
      |> Enum.map_join("\n\n", fn {p, b} -> if p == cand.path, do: "# TODO", else: b end)

    joined = Enum.map_join(cand.files, "\n\n", fn {_, b} -> b end)

    cond do
      # Gate 1: the file must parse standalone and be non-trivial.
      match?({:error, _}, Code.string_to_quoted(cand.body)) ->
        record_dead(cand, "file body does not parse standalone")
        :uncarvable

      length(String.split(cand.body, "\n")) < 4 ->
        record_dead(cand, "file body too trivial to teach (< 4 lines)")
        :uncarvable

      # Gate 2: the body must appear exactly once across the joined bodies —
      # hole→body substitution must be unambiguous.
      length(String.split(joined, cand.body)) != 2 ->
        record_dead(cand, "file body not uniquely locatable in the joined bundle")
        :uncarvable

      # F26 gate: the skeleton must be formatter-canonical.
      not canonical?(skeleton) ->
        record_dead(cand, "carve: skeleton not formatter-canonical (F26 class)")
        :uncarvable

      true ->
        stage_and_gate(cand, skeleton)
    end
  end

  defp canonical?(src) do
    formatted = src |> Code.format_string!() |> IO.iodata_to_binary()
    String.trim_trailing(formatted, "\n") == String.trim_trailing(src, "\n")
  rescue
    _ -> false
  end

  defp stage_and_gate(cand, skeleton) do
    spec = File.read!(Path.join(cand.root, "prompt.md"))
    n = next_index(cand.family)
    dir = "tasks/#{cand.family}_#{String.pad_leading(to_string(n), 2, "0")}"

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "prompt.md"), BundleFimTemplate.prompt(cand.path, spec, skeleton))
    File.write!(Path.join(dir, "solution.ex"), String.trim_trailing(cand.body, "\n"))

    real = grade(dir, "solution.ex")

    cond do
      not perfect?(real) ->
        File.rm_rf!(dir)
        record_dead(cand, "not perfect via :fim evaluator: #{summary(real)}")
        :rejected

      true ->
        gutted = EvalTask.Fim.mutate(cand.body)
        File.write!(Path.join(dir, "gutted.ex"), gutted)
        mut = grade(dir, "gutted.ex")
        File.rm!(Path.join(dir, "gutted.ex"))

        cond do
          mut["compiled"] != true ->
            File.rm_rf!(dir)
            record_dead(cand, "gutted candidate does not compile — vacuity unprovable")
            :gut_uncompilable

          (mut["tests_failed"] || 0) + (mut["tests_errors"] || 0) > 0 ->
            IO.puts("  minted #{Path.basename(dir)} (#{cand.path})")
            :minted

          true ->
            File.rm_rf!(dir)
            record_dead(cand, "vacuous: gutted file still green (harness never exercises it)")
            :vacuous
        end
    end
  end

  defp next_index(family) do
    Path.wildcard("tasks/#{family}_*")
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

  defp dead_key(sha, path), do: "#{sha}:#{path}"

  defp record_dead(cand, why) do
    row = %{
      root: cand.root,
      key: dead_key(cand.sha, cand.path),
      path: cand.path,
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
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: MintBundlefim.main(System.argv())
