# Retro audit: did any repair chain SHRINK its test suite on the way to acceptance?
#
#   mix run scripts/audit_repairs.exs [--logs <dir>]
#
# Walks logs/attempts/<id>/attempt_NN/ (the same graded-attempt capture mint_repairs
# reads) and, for every chain whose LAST attempt is `accepted`, counts test/property
# blocks in the accepted attempt's test_harness.exs and in every earlier attempt's
# harness. A chain is FLAGGED if the final accepted harness has FEWER blocks than any
# earlier attempt in the same chain — i.e. the fix reached green by deleting tests
# rather than fixing code (the failure mode cycle.ex's live count_tests gate blocks
# going forward; this is the retro check over already-captured history).
#
# FIM-cycle chains have no test_harness.exs (candidate = prompt.md + solution.ex) and
# are skipped, exactly as mint_repairs skips them. Read-only: writes nothing.
#
# One-off audit tool — NOT wired into any pipeline; slated for deletion at the
# steady-state line (docs/12 §7.2).

defmodule AuditRepairs do
  @moduledoc false

  def main(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [logs: :string])
    logs = opts[:logs] || "logs"

    chains =
      Path.wildcard(Path.join(logs, "attempts/*"))
      |> Enum.sort()
      |> Enum.map(&load_chain/1)
      |> Enum.reject(&is_nil/1)

    IO.puts("attempt chains found: #{length(chains)}")

    audited =
      for %{id: id, attempts: attempts} <- chains,
          {final, _rejected} = split_chain(attempts),
          # need an accepted final that carries a harness (FIM chains have none)
          final != nil,
          harness = final.files["test_harness.exs"],
          is_binary(harness) and String.trim(harness) != "",
          # earlier attempts that also carry a harness to compare against
          earlier = harnessed_earlier(attempts, final),
          earlier != [],
          do: audit_chain(id, final, earlier)

    skipped = length(chains) - length(audited)
    changed = Enum.filter(audited, & &1.changed)
    added = Enum.filter(changed, &(&1.delta > 0))
    removed = Enum.filter(changed, &(&1.delta < 0))
    flagged = Enum.filter(audited, & &1.flag)

    IO.puts("skipped (no accepted-with-harness final, or no earlier harness): #{skipped}")
    IO.puts("multi-attempt chains audited: #{length(audited)}")

    IO.puts(
      "  changed block count: #{length(changed)} (added: #{length(added)}, removed: #{length(removed)})"
    )

    Enum.each(changed, fn c ->
      IO.puts("    #{c.id}: max-earlier #{c.max_earlier} -> final #{c.final} (#{sign(c.delta)})")
    end)

    IO.puts("FLAGGED (final has FEWER blocks than an earlier attempt): #{length(flagged)}")

    Enum.each(flagged, fn c ->
      IO.puts("  FLAG #{c.id}: earlier #{c.max_earlier} -> final #{c.final}")
    end)
  end

  # A chain shrank iff the accepted harness has fewer blocks than the richest earlier one.
  defp audit_chain(id, final, earlier) do
    final_count = count_tests(final.files["test_harness.exs"])
    max_earlier = earlier |> Enum.map(&count_tests(&1.files["test_harness.exs"])) |> Enum.max()
    delta = final_count - max_earlier

    %{
      id: id,
      final: final_count,
      max_earlier: max_earlier,
      delta: delta,
      changed: delta != 0,
      flag: final_count < max_earlier
    }
  end

  defp harnessed_earlier(attempts, final) do
    Enum.filter(attempts, fn a ->
      a != final and is_binary(a.files["test_harness.exs"]) and
        String.trim(a.files["test_harness.exs"]) != ""
    end)
  end

  defp sign(d) when d > 0, do: "+#{d}"
  defp sign(d), do: "#{d}"

  # ---- block counter (verbatim from lib/gen_task/cycle.ex count_tests) -------
  defp count_tests(harness), do: length(Regex.scan(~r/^\s*(?:test|property)\s+"/m, harness))

  # ---- chain loaders (mirrors scripts/mint_repairs.exs lines ~63-99) ---------
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

  defp split_chain(attempts) do
    final = Enum.find(attempts, &(&1.meta["status"] == "accepted"))

    rejected =
      Enum.filter(attempts, fn a ->
        a.meta["status"] in ["rejected", "rejected_final"] and is_binary(a.meta["repair_report"])
      end)

    {final, rejected}
  end
end

AuditRepairs.main(System.argv())
