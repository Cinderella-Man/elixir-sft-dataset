# check_screen_freshness.exs — the S6 blind verdict must match the CURRENT harness.
#
# WHY (STATUS T1.2, found live 2026-07-13): `logs/screen_blind.jsonl` is keyed
# by PROMPT sha, but blind solvability is a property of the (prompt, harness)
# PAIR — the solve is graded against the harness. Editing a harness silently
# invalidates the ledger row: after 013_001's harness was hand-strengthened the
# ledger still said "screened", and only session knowledge triggered the manual
# re-screen. This gate makes that knowledge structural.
#
# A root's blind evidence is FRESH when any of these holds:
#   1. its latest screen row (for the CURRENT prompt sha) records
#      `harness_sha` equal to the harness on disk (rows since 2026-07-13);
#   2. `logs/strengthen_harnesses.jsonl` has a SUCCESS row whose
#      `harness_sha_after` equals the harness on disk — the strengthener's
#      blind gate ran a prompt-only solve against exactly that harness;
#   3. (legacy rows without `harness_sha`) the harness file's last git commit
#      is not newer than the screen row's timestamp.
#
# Anything else with a screen row is STALE → exit 1 (the gate): re-screen with
#   mix run scripts/screen_blind_solve.exs --only "<fam>*" --rescreen
# Roots with NO row for their current prompt sha are reported as UNSCREENED
# (that is S6 coverage, a different question — report-only here).
#
#   mix run scripts/check_screen_freshness.exs               # the gate
#   mix run scripts/check_screen_freshness.exs -- --self-test # prove non-vacuous

alias GenTask.CycleLog

defmodule CheckScreenFreshness do
  @moduledoc false

  @screen "logs/screen_blind.jsonl"
  @strengthen "logs/strengthen_harnesses.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [self_test: :boolean])

    roots = roots()
    screen = screen_by_prompt_sha()
    strengthened = strengthen_success_shas()

    verdicts =
      Map.new(roots, fn root ->
        {root.name, verdict(root, screen, strengthened)}
      end)

    if opts[:self_test], do: self_test(roots, screen, strengthened)

    counts = Enum.frequencies_by(verdicts, fn {_, {v, _}} -> v end)
    stale = for {name, {:stale, why}} <- verdicts, do: {name, why}
    unscreened = for {name, {:unscreened, _}} <- verdicts, do: name

    IO.puts(
      "screen freshness over #{map_size(verdicts)} root(s): " <>
        (counts |> Enum.sort() |> Enum.map_join(", ", fn {v, n} -> "#{v}=#{n}" end))
    )

    Enum.each(stale, fn {name, why} -> IO.puts("  STALE      #{name} — #{why}") end)
    Enum.each(unscreened, &IO.puts("  unscreened #{&1}"))

    if stale == [] do
      IO.puts("screen freshness: OK ✓ (unscreened is S6 coverage, not staleness)")
    else
      IO.puts("""

      #{length(stale)} root(s) carry blind verdicts for an OLDER harness. Re-screen:
        mix run scripts/screen_blind_solve.exs --only "<name>" --rescreen
      Never delete the old rows — append-only; the latest row wins.
      """)

      System.halt(1)
    end
  end

  defp verdict(root, screen, strengthened) do
    case Map.get(screen, root.prompt_sha) do
      nil ->
        {:unscreened, nil}

      row ->
        cond do
          row["harness_sha"] == root.harness_sha ->
            {:fresh, nil}

          MapSet.member?(strengthened, root.harness_sha) ->
            {:fresh_via_strengthen, nil}

          is_binary(row["harness_sha"]) ->
            {:stale, "screened against harness #{String.slice(row["harness_sha"], 0, 8)}, " <>
               "disk has #{String.slice(root.harness_sha, 0, 8)}"}

          harness_commit_iso(root.dir) <= row["ts"] ->
            {:fresh_legacy, nil}

          true ->
            {:stale, "legacy row #{String.slice(row["ts"] || "", 0, 19)} predates the " <>
               "harness commit #{String.slice(harness_commit_iso(root.dir), 0, 19)}"}
        end
    end
  end

  # ── inputs ──────────────────────────────────────────────────────────────────

  defp roots do
    EvalTask.Discovery.all()
    |> Enum.filter(&(&1.shape in [:single, :multifile] and &1.found))
    # repair_ prompts are frozen captured evidence (docs/13 §1.5) — a blind
    # solve against them is meaningless, so they are not screenable roots.
    |> Enum.reject(&String.starts_with?(&1.name, "repair_"))
    |> Enum.map(fn task ->
      %{
        name: task.name,
        dir: task.dir,
        prompt_sha: file_sha!(task.dir, "prompt.md"),
        harness_sha: file_sha!(task.dir, "test_harness.exs")
      }
    end)
  end

  defp file_sha!(dir, name), do: CycleLog.content_sha(File.read!(Path.join(dir, name)))

  # Last row per prompt sha wins (append-only ledger, re-screens overwrite).
  defp screen_by_prompt_sha do
    rows(@screen)
    |> Enum.reduce(%{}, fn
      %{"sha" => sha} = row, acc -> Map.put(acc, sha, row)
      _, acc -> acc
    end)
  end

  defp strengthen_success_shas do
    rows(@strengthen)
    |> Enum.filter(&(&1["verdict"] in ["applied", "applied_wt_divergent"]))
    |> Enum.map(& &1["harness_sha_after"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp harness_commit_iso(dir) do
    {out, 0} =
      System.cmd("git", ["log", "-1", "--format=%cI", "--", Path.join(dir, "test_harness.exs")])

    # Normalize to UTC ISO so it compares lexicographically with ledger ts.
    case out |> String.trim() |> DateTime.from_iso8601() do
      {:ok, dt, _} -> dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()
      # never committed (brand-new dir) — treat as newest possible → stale until screened
      _ -> "9999"
    end
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

  # Prove the gate is not vacuous: a fresh root re-checked with a perturbed
  # harness sha MUST come back stale.
  defp self_test(roots, screen, strengthened) do
    fresh =
      Enum.find(roots, fn root ->
        match?({:fresh, _}, verdict(root, screen, strengthened))
      end)

    case fresh do
      nil ->
        IO.puts("self-test SKIPPED: no sha-stamped fresh row exists yet")

      root ->
        planted = %{root | harness_sha: CycleLog.content_sha("self-test perturbation")}

        case verdict(planted, screen, strengthened) do
          {:stale, _} ->
            IO.puts("self-test OK ✓ (perturbed harness sha on #{root.name} detected as stale)")

          other ->
            IO.puts("self-test FAILED: expected :stale, got #{inspect(other)}")
            System.halt(1)
        end
    end
  end
end

CheckScreenFreshness.main(System.argv())
