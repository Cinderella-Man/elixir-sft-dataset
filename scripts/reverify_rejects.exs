# reverify_rejects.exs — audit the REJECT ledgers against the current gates.
#
# WHY (docs/12 §5.1 item 12, the 074_x lesson): "a permanent-reject ledger is
# only as sound as the gate that wrote it — when a gate is repaired, audit its
# ledger." Reject rows are permanent verdicts that silently remove units from
# `work_status`; a row written by a since-fixed gate blocks mintable data
# forever. Suspicion trigger for this tool (2026-07-13): all 15 CURRENT
# 102_001 tfim rejects were written 2026-07-11 05:42 — BEFORE the 07-12
# bundle-staging fixes (manifest travels with the staged parent; bundle
# reconstruction) — and 102_001 is a bundle/repo parent, i.e. exactly the
# class those fixes exist for.
#
# What it does — re-derives each ledgered verdict from disk through the SAME
# staging + grading the real gates use (no reimplementation of grading):
#
#   tfim_rejected.jsonl   — every row whose harness_sha matches the CURRENT
#                           parent harness (stale rows are inert by design: a
#                           changed harness re-opens its candidates). Re-runs
#                           the mint gate chain: ≤98-col rule → reconstruct
#                           green → zero warnings → isolation kill (bundles:
#                           static assert check).
#   bugfix_rejected.jsonl — deterministic sample (--bugfix-sample N, default
#                           25, fixed RNG seed) of rows whose solution+harness
#                           key matches disk. Re-stages the parent and grades
#                           the labeled mutant; the verdict is sound iff the
#                           harness does NOT kill it.
#   fim_rejected.jsonl    — 1 row, kept deliberately (docs/12 §5.1.12); listed
#                           in the report, nothing to re-run.
#
# Verdicts written to the ledger:
#   reject_confirmed — the current gate still rejects (reason recorded)
#   REJECT_UNSOUND   — every gate now PASSES: the ledger row blocks a mintable
#                      unit. Remedy = purge the row (by prefix+name+sha) and
#                      let the next backfill re-gate it for real.
#   stale            — content key no longer matches disk (inert, skipped)
#   target_gone / label_gone — the carver/mutator no longer produces this
#                      candidate (enumerator changed; a finding in itself)
#   parent_not_green — the parent fails its own harness here (corpus rot or
#                      environment — investigate before trusting any verdict)
#
# Ledger: logs/reverify_rejects.jsonl, keyed by (kind, prefix, name, key sha) —
# a re-run skips rows already re-verified for the same content. Zero LLM,
# CPU-only, sequential, safe to kill at any point.
#
# Usage:
#   mix run scripts/reverify_rejects.exs                      # run what's still to do
#   mix run scripts/reverify_rejects.exs -- --bugfix-sample 50
#   mix run scripts/reverify_rejects.exs -- --report

alias GenTask.{Config, CycleLog, Evaluator, Mutation, TestFim}

defmodule ReverifyRejects do
  @moduledoc false

  @tfim_ledger "logs/tfim_rejected.jsonl"
  @bugfix_ledger "logs/bugfix_rejected.jsonl"
  @fim_ledger "logs/fim_rejected.jsonl"
  @out "logs/reverify_rejects.jsonl"
  @rng_seed {20_260_713, 7, 13}

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [report: :boolean, bugfix_sample: :integer])

    if opts[:report], do: report(), else: run(opts)
  end

  defp run(opts) do
    cfg = Config.new([])
    done = done_keys()

    tfim = tfim_todo(done)
    bugfix = bugfix_todo(done, opts[:bugfix_sample] || 25)

    IO.puts(
      "reverify: #{length(tfim)} tfim row(s) + #{length(bugfix)} bugfix row(s) to re-run " <>
        "(ledger #{@out}; already done are skipped)\n"
    )

    Enum.each(tfim, fn row ->
      verdict = verify_tfim(cfg, row)
      append(Map.merge(row_key(:tfim, row), verdict))
      IO.puts("  tfim   #{verdict.verdict}  #{row["prefix"]}  #{row["name"]}")
    end)

    Enum.each(bugfix, fn row ->
      verdict = verify_bugfix(cfg, row)
      append(Map.merge(row_key(:bugfix, row), verdict))
      IO.puts("  bugfix #{verdict.verdict}  #{row["prefix"]}  #{row["label"]}")
    end)

    report()
  end

  # ── populations ────────────────────────────────────────────────────────────

  defp tfim_todo(done) do
    @tfim_ledger
    |> rows()
    |> Enum.uniq_by(&{&1["prefix"], &1["name"], &1["harness_sha"]})
    |> Enum.reject(&MapSet.member?(done, key_of(:tfim, &1)))
  end

  # Deterministic sample: fixed RNG seed over the sorted CURRENT rows, so a
  # re-run draws the same set and the ledger-resume actually converges.
  defp bugfix_todo(done, n) do
    current =
      @bugfix_ledger
      |> rows()
      |> Enum.uniq_by(&{&1["prefix"], &1["label"], &1["sha"]})
      |> Enum.filter(fn row ->
        case parent_files(row["prefix"]) do
          {:ok, files} -> bugfix_key(files) == row["sha"]
          _ -> false
        end
      end)
      |> Enum.sort_by(&{&1["prefix"], &1["label"]})

    :rand.seed(:exsss, @rng_seed)

    current
    |> Enum.take_random(n)
    |> Enum.reject(&MapSet.member?(done, key_of(:bugfix, &1)))
  end

  # ── tfim: replicate TestFim.build_candidate/gate_candidate exactly ─────────

  defp verify_tfim(cfg, row) do
    prefix = row["prefix"]

    with {:ok, files} <- parent_files(prefix),
         harness = files["test_harness.exs"],
         true <- CycleLog.content_sha(harness) == row["harness_sha"] || :stale,
         %{} = cand <-
           TestFim.carvable_blocks(harness)
           |> Enum.find(&(TestFim.qual(&1) == row["name"])) || :target_gone do
      module_src = files["solution.ex"]
      gold = block_src(harness, cand)
      over_98 = gold |> String.split("\n") |> Enum.count(&(String.length(&1) > 98))

      if over_98 > 0 do
        %{verdict: :reject_confirmed, reason: "#{over_98} gold line(s) over 98 columns"}
      else
        gate_tfim(cfg, prefix, files, harness, module_src, cand, gold)
      end
    else
      :stale -> %{verdict: :stale, reason: "harness changed since the reject"}
      :target_gone -> %{verdict: :target_gone, reason: "carver no longer yields this block"}
      {:error, why} -> %{verdict: :error, reason: why}
    end
  end

  defp gate_tfim(cfg, prefix, files, harness, module_src, cand, gold) do
    skeleton = TestFim.skeletonize(harness, cand)
    iso_harness = TestFim.isolate_for_test(harness, cand)
    prompt = TestFim.prompt_md(module_src, skeleton, TestFim.kind_of(harness, cand))

    root = Path.join(cfg.staging_dir, "reverify_tfim_#{prefix}")

    parent_stage =
      %{"solution.ex" => module_src}
      |> merge_manifest(files)

    Evaluator.stage!(Path.join(root, "#{prefix}_01"), parent_stage)

    tfim_dir =
      Evaluator.stage!(Path.join(root, "tfim_#{prefix}_90"), %{
        "prompt.md" => prompt,
        "solution.ex" => gold
      })

    recon = Evaluator.grade(tfim_dir, cfg)

    cond do
      not Evaluator.green?(recon) ->
        %{verdict: :reject_confirmed, reason: "reconstruct not green"}

      Evaluator.compile_warnings(recon) > 0 ->
        %{
          verdict: :reject_confirmed,
          reason: "reconstruct has #{Evaluator.compile_warnings(recon)} compile warning(s)"
        }

      not gate_ok?(cfg, root, module_src, gold, iso_harness) ->
        %{verdict: :reject_confirmed, reason: "vacuous block (no isolation kill)"}

      true ->
        %{verdict: :REJECT_UNSOUND, reason: "every gate passes now — mintable unit blocked"}
    end
  end

  defp gate_ok?(cfg, root, module_src, gold, iso_harness) do
    if String.contains?(module_src, "<file path=") do
      TestFim.asserting_block?(gold)
    else
      Mutation.gate_isolation(Path.join(root, "iso"), module_src, iso_harness, cfg) == :killed
    end
  end

  # ── bugfix: replicate Bugfix.gate exactly ───────────────────────────────────

  defp verify_bugfix(cfg, row) do
    prefix = row["prefix"]

    with {:ok, files} <- parent_files(prefix),
         true <- bugfix_key(files) == row["sha"] || :stale,
         {_label, mutated} when not is_nil(mutated) <-
           files["solution.ex"]
           |> Mutation.semantic_mutants_textual()
           |> Enum.find(fn {l, _} -> l == row["label"] end) || :label_gone do
      dir =
        Evaluator.stage!(
          Path.join(cfg.staging_dir, "reverify_bugfix_#{prefix}"),
          %{
            "prompt.md" => "reverify staging",
            "solution.ex" => files["solution.ex"],
            "test_harness.exs" => files["test_harness.exs"]
          }
          |> merge_manifest(files)
        )

      ref = Evaluator.grade(dir, cfg)

      if Evaluator.green?(ref) do
        mutant_path = Path.join(cfg.staging_dir, "reverify_bugfix_#{prefix}_mutant.ex")
        File.write!(mutant_path, mutated)
        bad = Evaluator.grade(dir, cfg, mutant_path)

        if Evaluator.killed_by_tests?(bad),
          do: %{verdict: :REJECT_UNSOUND, reason: "harness kills this mutant now — mintable"},
          else: %{verdict: :reject_confirmed, reason: "mutant still survives / breaks compile"}
      else
        %{verdict: :parent_not_green, reason: "reference fails its own staged harness HERE"}
      end
    else
      :stale -> %{verdict: :stale, reason: "solution/harness changed since the reject"}
      :label_gone -> %{verdict: :label_gone, reason: "mutator no longer yields this label"}
      {:error, why} -> %{verdict: :error, reason: why}
    end
  end

  # ── shared ──────────────────────────────────────────────────────────────────

  defp parent_files(prefix) do
    dir = Path.join("tasks", "#{prefix}_01")

    if File.dir?(dir) do
      files =
        for name <- ["solution.ex", "test_harness.exs", "manifest.exs"],
            path = Path.join(dir, name),
            File.regular?(path),
            into: %{},
            do: {name, File.read!(path)}

      {:ok, files}
    else
      {:error, "no parent dir #{dir}"}
    end
  end

  defp merge_manifest(stage_files, parent_files) do
    case parent_files["manifest.exs"] do
      nil -> stage_files
      m -> Map.put(stage_files, "manifest.exs", m)
    end
  end

  defp bugfix_key(files) do
    CycleLog.content_sha(
      files["solution.ex"] <> "\n@@\n" <> (files["test_harness.exs"] || "")
    )
  end

  defp block_src(harness, %{s: s, e: e}) do
    harness |> String.split("\n") |> Enum.slice(s..e) |> Enum.join("\n")
  end

  defp row_key(:tfim, row),
    do: %{kind: "tfim", prefix: row["prefix"], name: row["name"], key: row["harness_sha"]}

  defp row_key(:bugfix, row),
    do: %{kind: "bugfix", prefix: row["prefix"], name: row["label"], key: row["sha"]}

  defp key_of(:tfim, row), do: {"tfim", row["prefix"], row["name"], row["harness_sha"]}
  defp key_of(:bugfix, row), do: {"bugfix", row["prefix"], row["label"], row["sha"]}

  defp done_keys do
    @out
    |> rows()
    |> Enum.map(&{&1["kind"], &1["prefix"], &1["name"], &1["key"]})
    |> MapSet.new()
  end

  defp rows(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case JSON.decode(line) do
            {:ok, row} -> [row]
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  defp append(row) do
    File.write!(
      @out,
      JSON.encode!(Map.put(row, :ts, DateTime.utc_now() |> DateTime.to_iso8601())) <> "\n",
      [:append]
    )
  end

  defp report do
    verified = rows(@out)

    IO.puts("\n=== REVERIFY REJECTS (#{length(verified)} row(s) in #{@out}) ===")

    verified
    |> Enum.group_by(&{&1["kind"], &1["verdict"]})
    |> Enum.sort()
    |> Enum.each(fn {{kind, verdict}, rs} ->
      IO.puts("  #{String.pad_trailing(kind, 7)} #{String.pad_trailing(verdict, 17)} #{length(rs)}")
    end)

    unsound = Enum.filter(verified, &(&1["verdict"] == "REJECT_UNSOUND"))

    if unsound != [] do
      IO.puts("\n  UNSOUND rows (purge + re-run backfill to mint):")
      Enum.each(unsound, &IO.puts("    #{&1["kind"]}  #{&1["prefix"]}  #{&1["name"]}"))
    end

    fim = rows(@fim_ledger)

    if fim != [] do
      IO.puts("\n  fim_rejected.jsonl (kept deliberately, not re-run):")
      Enum.each(fim, &IO.puts("    #{&1["prefix"]}  #{&1["target"]}"))
    end
  end
end

ReverifyRejects.main(System.argv())
