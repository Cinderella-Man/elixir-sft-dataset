# Mint verified STYLE-repair SFT tasks from captured generation-loop attempts
# (TD.4, docs/13 §2.4 — the class `mint_repairs.exs` deliberately skips).
#
#   mix run scripts/mint_style_repairs.exs [--dry-run] [--limit N] [--logs <dir>] [--out <tasks_dir>]
#
# Source: the same attempt chains as mint_repairs (logs/attempts/<id>/attempt_NN).
# The classic repair miner requires the broken side to grade NON-GREEN — which
# excludes exactly the green-but-house-style-rejected attempts. Those teach a
# skill nothing else in the corpus does: "bring this WORKING code to house
# style" — real model-written code, real style findings, and a verified fix.
#
# A chain qualifies when its LAST attempt is `accepted` and an earlier attempt
# was rejected with a `repair_report` starting "house style:". Each such
# attempt N mints ONE task:
#
#   tasks/style_<id>_<NN>/
#     prompt.md          # original request + the working-but-rejected module + the style report
#     solution.ex        # the ACCEPTED attempt's module (the verified style fix)
#     test_harness.exs   # the accepted attempt's harness (grades as shape :style)
#
# VERIFICATION before promotion (all local evals, no LLM — the pair only
# teaches if the style delta is real and behavior-neutral):
#   1. the fix grades GREEN against the accepted harness AND its house-style
#      shortfall is EMPTY (`Evaluator.quality_shortfall/2`);
#   2. the broken module ALSO grades GREEN against the same harness (behavior
#      already correct — that is the point) but its shortfall is NON-EMPTY.
# Unmintable candidates are ledgered in logs/style_rejected.jsonl keyed by
# content sha (rule 2/7: a re-run never re-evaluates a known-dead candidate).
# Re-runnable: an existing style_ dir is skipped (add-only, like the loop).

alias GenTask.{CycleLog, Evaluator}

defmodule MintStyleRepairs do
  @moduledoc false

  @reject_ledger "logs/style_rejected.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [dry_run: :boolean, limit: :integer, logs: :string, out: :string]
      )

    logs = opts[:logs] || "logs"
    out = opts[:out] || "tasks"
    dry? = opts[:dry_run] || false

    dead = dead_keys()

    # The style rejects live mostly in the ARCHIVED chains (§3.2 snapshots) —
    # the live attempts dir gets rotated/consumed. All sources are scanned;
    # identical chain ids across snapshots dedupe via the target-dir :exists
    # skip (each pair is independently re-verified regardless of source).
    candidates =
      Path.wildcard(Path.join(logs, "attempts{,_archive_*}/*"))
      |> Enum.sort()
      |> Enum.map(&load_chain/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn {id, final, style_rejects} ->
        for broken <- style_rejects, do: {id, broken, final}
      end)

    candidates = if opts[:limit], do: Enum.take(candidates, opts[:limit]), else: candidates

    IO.puts("style-reject candidates (green-but-house-style chains): #{length(candidates)}")

    results =
      Enum.map(candidates, fn cand ->
        outcome = mint_one(cand, out, dry?, dead)
        if outcome == :minted, do: IO.puts("  minted #{target_name(cand)}")
        outcome
      end)

    IO.puts("minted: #{inspect(Enum.frequencies(results))}")

    if not dry? and Enum.any?(results, &(&1 == :minted)) do
      IO.puts("""
      New style_ dirs are FROZEN captured evidence (like repair_): no resync gate.
      Validate + commit:
        elixir scripts/validate.exs --only "style_*"
      """)
    end
  end

  # {id, accepted_final, [green style-rejected attempts]} | nil
  defp load_chain(dir) do
    attempts =
      Path.wildcard(Path.join(dir, "attempt_*"))
      |> Enum.sort()
      |> Enum.map(&load_attempt/1)
      |> Enum.reject(&is_nil/1)

    final = Enum.find(Enum.reverse(attempts), &(&1.meta["status"] == "accepted"))

    style_rejects =
      Enum.filter(attempts, fn a ->
        # Two report phrasings across loop eras: "The solution is green but
        # does not meet the house style: …" and "The files graded green but
        # fall short of the house style / harness standard: …". Behavioral,
        # mutation and compile reports never mention the phrase.
        a.meta["status"] in ["rejected", "rejected_final"] and
          is_binary(a.meta["repair_report"]) and
          String.contains?(a.meta["repair_report"], "house style") and
          is_binary(a.files["solution.ex"]) and is_binary(a.files["prompt.md"])
      end)

    if final != nil and is_binary(final.files["solution.ex"]) and
         is_binary(final.files["test_harness.exs"]) and style_rejects != [] do
      {Path.basename(dir), final, style_rejects}
    end
  end

  defp load_attempt(dir) do
    with {:ok, meta_body} <- File.read(Path.join(dir, "meta.json")),
         {:ok, meta} <- Jason.decode(meta_body) do
      files =
        Path.wildcard(Path.join([dir, "files", "*"]))
        |> Map.new(fn f -> {Path.basename(f), File.read!(f)} end)

      %{meta: meta, files: files}
    else
      _ -> nil
    end
  end

  defp target_name({id, broken, _final}) do
    n = String.pad_leading(to_string(broken.meta["attempt"]), 2, "0")
    "style_#{id}_#{n}"
  end

  defp mint_one({id, broken, final} = cand, out, dry?, dead) do
    target = Path.join(out, target_name(cand))
    key = cand_key(broken, final)

    cond do
      File.dir?(target) ->
        :exists

      MapSet.member?(dead, key) ->
        :known_dead

      true ->
        case verify(id, broken, final) do
          :ok ->
            if dry? do
              :would_mint
            else
              write_dir!(target, id, broken, final)
              :minted
            end

          {:dead, why} ->
            record_dead(key, target_name(cand), why)
            :unverified
        end
    end
  end

  defp write_dir!(target, id, broken, final) do
    File.mkdir_p!(target)
    File.write!(Path.join(target, "prompt.md"), style_prompt(id, broken))
    File.write!(Path.join(target, "solution.ex"), canonical(final.files["solution.ex"]))
    File.write!(Path.join(target, "test_harness.exs"), canonical(final.files["test_harness.exs"]))

    case parent_manifest(id) do
      nil -> :ok
      m -> File.write!(Path.join(target, "manifest.exs"), m)
    end
  end

  # The pair teaches iff the style delta is real and behavior-neutral: BOTH
  # sides green vs the accepted harness; fix style-clean; broken style-dirty.
  defp verify(id, broken, final) do
    stage = Path.join(System.tmp_dir!(), "mint_style_#{System.unique_integer([:positive])}")

    try do
      dir = Path.join(stage, "verify")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "test_harness.exs"), final.files["test_harness.exs"])
      File.write!(Path.join(dir, "prompt.md"), broken.files["prompt.md"] || "verify")

      case parent_manifest(id) do
        nil -> :ok
        m -> File.write!(Path.join(dir, "manifest.exs"), m)
      end

      File.write!(Path.join(dir, "solution.ex"), final.files["solution.ex"])
      fix = grade(dir, "solution.ex")

      File.write!(Path.join(dir, "broken.ex"), broken.files["solution.ex"])
      bad = grade(dir, "broken.ex")

      fix_shortfall = shortfall(fix, final.files, final.files["solution.ex"])
      bad_shortfall = shortfall(bad, final.files, broken.files["solution.ex"])

      cond do
        not green?(fix) -> {:dead, "fix not green vs the accepted harness"}
        not green?(bad) -> {:dead, "broken side not green (classic repair class, not style)"}
        fix_shortfall != nil -> {:dead, "fix still style-dirty: #{fix_shortfall}"}
        bad_shortfall == nil -> {:dead, "broken side already style-clean — pair teaches nothing"}
        true -> :ok
      end
    after
      File.rm_rf!(stage)
    end
  end

  defp shortfall(json, base_files, solution) do
    Evaluator.quality_shortfall(
      json,
      base_files
      |> Map.take(["prompt.md", "test_harness.exs"])
      |> Map.put("solution.ex", solution)
    )
  end

  defp style_prompt(id, broken) do
    original = broken.files["prompt.md"] || "(original request unavailable)"

    """
    # Bring this working module up to house style

    I asked for the following:

    #{original}

    Here is my implementation. It compiles and passes every test — the behavior
    is correct — but it was rejected by the style review:

    ```elixir
    #{broken.files["solution.ex"]}
    ```

    The style review said:

    ```
    #{broken.meta["repair_report"]}
    ```

    Fix every finding in the review WITHOUT changing any behavior: the module
    must keep passing exactly the tests it passes now. Give me the complete
    corrected module in a single file.
    <!-- minted from logs/attempts/#{id}/attempt_#{broken.meta["attempt"]} -->
    """
  end

  # ── shared plumbing (mint_repairs conventions) ──────────────────────────────

  defp parent_manifest(nil), do: nil

  defp parent_manifest(id) do
    candidates = [Path.join("tasks", id) | Path.wildcard("tasks/#{String.slice(id, 0, 7)}*_01")]

    candidates
    |> Enum.map(&Path.join(&1, "manifest.exs"))
    |> Enum.find(&File.regular?/1)
    |> case do
      nil -> nil
      path -> File.read!(path)
    end
  end

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

  defp green?(json) do
    json["compiled"] == true and (json["tests_passed"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and (json["tests_errors"] || 0) == 0
  end

  defp ensure_nl(body), do: String.trim_trailing(body, "\n") <> "\n"

  # Captured attempt files are written verbatim; MINTED corpus files must be
  # formatter-canonical (the corpus format gate bit on the first full mint —
  # 2026-07-19). The PROMPT's embedded broken module stays verbatim (frozen
  # captured evidence, not format-gated); only the on-disk gold + harness are
  # canonicalized. Whitespace-only, so the pre-write verification stands.
  defp canonical(body) do
    body |> Code.format_string!() |> IO.iodata_to_binary() |> ensure_nl()
  rescue
    _ -> ensure_nl(body)
  end

  # ── dead-candidate ledger (rules 2 + 7) ─────────────────────────────────────

  defp cand_key(broken, final) do
    CycleLog.content_sha(
      (broken.files["solution.ex"] || "") <>
        (final.files["solution.ex"] || "") <>
        (final.files["test_harness.exs"] || "")
    )
  end

  defp dead_keys do
    case File.read(@reject_ledger) do
      {:ok, body} ->
        for line <- String.split(body, "\n", trim: true),
            {:ok, row} <- [Jason.decode(line)],
            into: MapSet.new(),
            do: row["key"]

      _ ->
        MapSet.new()
    end
  end

  defp record_dead(key, name, why) do
    File.mkdir_p!(Path.dirname(@reject_ledger))

    File.write!(
      @reject_ledger,
      Jason.encode!(%{
        key: key,
        candidate: name,
        why: why,
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      }) <> "\n",
      [:append]
    )
  end
end

MintStyleRepairs.main(System.argv())
