# Mint verified repair-pair SFT tasks from captured generation-loop attempts.
#
#   mix run scripts/mint_repairs.exs [--dry-run] [--logs <dir>] [--out <tasks_dir>]
#
# Source: logs/attempts/<id>/attempt_NN/{files/,grade.json,meta.json} — written by
# GenTask.Cycle / GenTask.Fim on every graded attempt (docs/08 §4). For every id whose
# LAST attempt is `accepted` and which has ≥1 earlier `rejected` attempt, each rejected
# attempt N is minted as ONE repair task:
#
#   tasks/repair_<id>_<NN>/
#     prompt.md          # original request + the broken attempt-N code + its failure report
#     solution.ex        # the ACCEPTED attempt's solution.ex (the verified fix)
#     test_harness.exs   # the accepted attempt's harness (grades as shape :single)
#
# Every minted dir is verified before promotion: the fix must grade green AND the
# broken code must grade non-green against the SAME harness (otherwise the pair
# teaches nothing) — both grades run through the real evaluator. Deterministic, no
# LLM. Re-runnable: an existing repair_ dir is skipped (add-only, like the loop).
#
# FIM-cycle attempts (candidate = prompt.md + solution.ex, no harness) are skipped in
# v1 — their reconstruction context makes the pair harder to frame; see docs/09.

defmodule MintRepairs do
  @moduledoc false

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [dry_run: :boolean, logs: :string, out: :string]
      )

    logs = opts[:logs] || "logs"
    out = opts[:out] || "tasks"
    dry? = opts[:dry_run] || false

    chains =
      Path.wildcard(Path.join(logs, "attempts/*"))
      |> Enum.sort()
      |> Enum.map(&load_chain/1)
      |> Enum.reject(&is_nil/1)

    IO.puts("attempt chains found: #{length(chains)}")

    mintable =
      for %{id: id, attempts: attempts} <- chains,
          {final, rejected} = split_chain(attempts),
          final != nil,
          # a repair pair needs the full triplet on both sides — FIM candidates
          # (no test_harness.exs) are out of scope for v1
          Map.has_key?(final.files, "test_harness.exs"),
          broken <- rejected,
          Map.has_key?(broken.files, "solution.ex"),
          do: {id, broken, final}

    IO.puts("mintable (rejected → accepted) pairs: #{length(mintable)}")

    results = Enum.map(mintable, &mint_one(&1, out, dry?))
    freq = Enum.frequencies(results)
    IO.puts("minted: #{inspect(freq)}")
    if dry?, do: IO.puts("(dry run — nothing written)")
  end

  defp load_chain(dir) do
    attempts =
      Path.wildcard(Path.join(dir, "attempt_*"))
      |> Enum.sort()
      |> Enum.map(&load_attempt/1)
      |> Enum.reject(&is_nil/1)

    if attempts == [], do: nil, else: %{id: Path.basename(dir), attempts: attempts}
  end

  defp load_attempt(dir) do
    with {:ok, meta_raw} <- File.read(Path.join(dir, "meta.json")),
         {:ok, meta} <- Jason.decode(meta_raw),
         {:ok, grade_raw} <- File.read(Path.join(dir, "grade.json")),
         {:ok, grade} <- Jason.decode(grade_raw) do
      files =
        for f <- File.ls!(Path.join(dir, "files")), into: %{} do
          {f, File.read!(Path.join([dir, "files", f]))}
        end

      %{meta: meta, grade: grade, files: files}
    else
      _ -> nil
    end
  end

  # {accepted_attempt | nil, [rejected attempts that have a repair_report]}
  defp split_chain(attempts) do
    final = Enum.find(attempts, &(&1.meta["status"] == "accepted"))

    rejected =
      Enum.filter(attempts, fn a ->
        a.meta["status"] in ["rejected", "rejected_final"] and is_binary(a.meta["repair_report"])
      end)

    {final, rejected}
  end

  defp mint_one({id, broken, final}, out, dry?) do
    n = String.pad_leading(to_string(broken.meta["attempt"]), 2, "0")
    target = Path.join(out, "repair_#{id}_#{n}")

    cond do
      File.dir?(target) ->
        :exists

      not verified?(broken, final) ->
        :unverified

      dry? ->
        :would_mint

      true ->
        File.mkdir_p!(target)
        File.write!(Path.join(target, "prompt.md"), repair_prompt(id, broken))
        File.write!(Path.join(target, "solution.ex"), final.files["solution.ex"])
        File.write!(Path.join(target, "test_harness.exs"), final.files["test_harness.exs"])
        :minted
    end
  end

  # The pair only teaches if, against the ACCEPTED harness, the fix is green and the
  # broken code is not. Both sides are re-graded through the real evaluator (the
  # captured grades were against the attempt's OWN harness, which the repair may have
  # changed).
  defp verified?(broken, final) do
    stage = Path.join(System.tmp_dir!(), "mint_repair_#{System.unique_integer([:positive])}")

    try do
      dir = Path.join(stage, "verify")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "test_harness.exs"), final.files["test_harness.exs"])
      File.write!(Path.join(dir, "prompt.md"), "verify")

      File.write!(Path.join(dir, "solution.ex"), final.files["solution.ex"])
      fix = grade(dir, "solution.ex")

      File.write!(Path.join(dir, "broken.ex"), broken.files["solution.ex"])
      bad = grade(dir, "broken.ex")

      green?(fix) and not green?(bad)
    after
      File.rm_rf!(stage)
    end
  end

  defp grade(dir, sol) do
    {out, _} =
      System.cmd("elixir", [Path.join(File.cwd!(), "scripts/eval_task.exs"), dir, sol],
        stderr_to_stdout: true
      )

    out
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find("{}", &String.starts_with?(&1, "{"))
    |> Jason.decode!()
  end

  defp green?(json) do
    json["compiled"] == true and (json["tests_passed"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and (json["tests_errors"] || 0) == 0
  end

  defp repair_prompt(id, broken) do
    original = broken.files["prompt.md"] || "(original request unavailable)"

    """
    # Fix the failing module

    I asked for the following:

    #{original}

    Here is my current implementation, but it is failing tests:

    ```elixir
    #{broken.files["solution.ex"]}
    ```

    The failure report:

    ```
    #{broken.meta["repair_report"]}
    ```

    Find the bug and give me the corrected complete module in a single file.
    <!-- minted from logs/attempts/#{id}/attempt_#{broken.meta["attempt"]} -->
    """
  end
end

MintRepairs.main(System.argv())
