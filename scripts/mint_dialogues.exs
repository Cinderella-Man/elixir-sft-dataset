# Mint multi-turn repair-dialogue dirs from captured generation-loop attempts
# (TD.2, docs/13 §2.2; export contract docs/16 §5b).
#
#   mix run scripts/mint_dialogues.exs [--dry-run] [--limit N] [--logs <dir>] [--out <tasks_dir>]
#
# A chain qualifies when its LAST attempt is `accepted` and ≥1 earlier attempt
# is `rejected` with a captured `repair_report`. One chain mints ONE dir:
#
#   tasks/dialog_<id>/
#     prompt.md          # the original spec (turn 1)
#     attempt_NN.code    # each rejected attempt's module, VERBATIM (frozen
#     report_NN.txt      #   evidence; .code/.txt keep formatters + lints off)
#     solution.ex        # the ACCEPTED module (the gold — canonical)
#     test_harness.exs   # the accepted harness (canonical; dir grades :dialogue)
#
# VERIFICATION before promotion (no LLM): the accepted module re-grades GREEN
# with ZERO warnings against the accepted harness (mint_repairs discipline).
# KNOWN RESIDUAL (2026-07-19): a frozen harness can predate corpus-wide gates
# that scan tasks/ (the temp-path System.pid rule caught 2 at first landing —
# dropped + dead-ledgered); after minting, run scripts/lint_temp_paths.exs and
# drop any flagged dir the same way. Rejected attempts + reports are frozen
# captured evidence — embedded verbatim, never re-graded.
# Dead chains are ledgered in logs/dialogue_rejected.jsonl by content sha.
# Re-runnable: an existing dialog_ dir is skipped (add-only); duplicate chain
# ids across the §3.2 archive snapshots dedupe the same way.

alias GenTask.CycleLog

defmodule MintDialogues do
  @moduledoc false

  @reject_ledger "logs/dialogue_rejected.jsonl"

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

    chains =
      Path.wildcard(Path.join(logs, "attempts{,_archive_*}/*"))
      |> Enum.sort()
      |> Enum.map(&load_chain/1)
      |> Enum.reject(&is_nil/1)

    chains = if opts[:limit], do: Enum.take(chains, opts[:limit]), else: chains

    IO.puts("dialogue chains (accepted final + >=1 reported reject): #{length(chains)}")

    results =
      Enum.map(chains, fn chain ->
        outcome = mint_one(chain, out, dry?, dead)
        if outcome == :minted, do: IO.puts("  minted dialog_#{elem(chain, 0)}")
        outcome
      end)

    IO.puts("minted: #{inspect(Enum.frequencies(results))}")

    if not dry? and Enum.any?(results, &(&1 == :minted)) do
      IO.puts("""
      dialog_ dirs are FROZEN captured evidence: no resync gate. Validate + commit:
        elixir scripts/validate.exs --only "dialog_*"
        mix run scripts/export_dataset.exs -- --check
      """)
    end
  end

  # {id, final, [rejected-with-report attempts in order]} | nil
  defp load_chain(dir) do
    attempts =
      Path.wildcard(Path.join(dir, "attempt_*"))
      |> Enum.sort()
      |> Enum.map(&load_attempt/1)
      |> Enum.reject(&is_nil/1)

    final = Enum.find(Enum.reverse(attempts), &(&1.meta["status"] == "accepted"))

    rejects =
      Enum.filter(attempts, fn a ->
        a.meta["status"] in ["rejected", "rejected_final"] and
          is_binary(a.meta["repair_report"]) and String.trim(a.meta["repair_report"]) != "" and
          is_binary(a.files["solution.ex"])
      end)

    if final != nil and is_binary(final.files["solution.ex"]) and
         is_binary(final.files["test_harness.exs"]) and
         is_binary(final.files["prompt.md"]) and rejects != [] do
      {Path.basename(dir), final, rejects}
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

  defp mint_one({id, final, rejects}, out, dry?, dead) do
    target = Path.join(out, "dialog_" <> id)
    key = chain_key(final, rejects)

    cond do
      File.dir?(target) ->
        :exists

      MapSet.member?(dead, key) ->
        :known_dead

      not gold_green?(id, final) ->
        record_dead(key, id, "accepted module not green vs its harness on re-grade")
        :unverified

      dry? ->
        :would_mint

      true ->
        write_dir!(target, final, rejects)
        :minted
    end
  end

  defp write_dir!(target, final, rejects) do
    File.mkdir_p!(target)
    File.write!(Path.join(target, "prompt.md"), final.files["prompt.md"])
    File.write!(Path.join(target, "solution.ex"), canonical(final.files["solution.ex"]))
    File.write!(Path.join(target, "test_harness.exs"), canonical(final.files["test_harness.exs"]))

    rejects
    |> Enum.with_index()
    |> Enum.each(fn {a, i} ->
      n = String.pad_leading(to_string(i), 2, "0")
      File.write!(Path.join(target, "attempt_#{n}.code"), a.files["solution.ex"])
      File.write!(Path.join(target, "report_#{n}.txt"), a.meta["repair_report"])
    end)

    case final.files["manifest.exs"] do
      nil -> :ok
      m -> File.write!(Path.join(target, "manifest.exs"), m)
    end
  end

  defp gold_green?(id, final) do
    stage = Path.join(System.tmp_dir!(), "mint_dialog_#{System.unique_integer([:positive])}")

    try do
      dir = Path.join(stage, "verify")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "prompt.md"), final.files["prompt.md"])
      File.write!(Path.join(dir, "solution.ex"), final.files["solution.ex"])
      File.write!(Path.join(dir, "test_harness.exs"), final.files["test_harness.exs"])

      case parent_manifest(id) do
        nil -> :ok
        m -> File.write!(Path.join(dir, "manifest.exs"), m)
      end

      json = grade(dir, "solution.ex")

      # Green AND zero warnings: the gold must meet TODAY'S perfect-score bar
      # (3 old-era accepts compiled with 1 warning and validate hard-failed
      # them on the first full mint, 2026-07-19).
      json["compiled"] == true and (json["tests_passed"] || 0) > 0 and
        (json["tests_failed"] || 0) == 0 and (json["tests_errors"] || 0) == 0 and
        (json["compile_warnings"] || 1) == 0
    after
      File.rm_rf!(stage)
    end
  end

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

  defp canonical(body) do
    body
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\n")
    |> Kernel.<>("\n")
  rescue
    _ -> String.trim_trailing(body, "\n") <> "\n"
  end

  defp chain_key(final, rejects) do
    CycleLog.content_sha(
      Enum.map_join(rejects, "", &(&1.files["solution.ex"] || "")) <>
        (final.files["solution.ex"] || "") <> (final.files["test_harness.exs"] || "")
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

  defp record_dead(key, id, why) do
    File.mkdir_p!(Path.dirname(@reject_ledger))

    File.write!(
      @reject_ledger,
      Jason.encode!(%{
        key: key,
        chain: id,
        why: why,
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      }) <> "\n",
      [:append]
    )
  end
end

MintDialogues.main(System.argv())
