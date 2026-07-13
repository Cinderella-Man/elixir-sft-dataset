# lint_temp_paths.exs — harnesses must not share a temp path across parallel evals.
#
# The validator runs ONE BEAM PER TASK, in parallel. Any harness that builds a
# path in a SHARED directory (`System.tmp_dir!()`, `/tmp/…`) must make that path
# unique per OS PROCESS:
#
#     System.pid()  AND  System.unique_integer([:positive])
#
# `System.unique_integer/1` alone is NOT enough — it is unique only *within one
# BEAM*, so two concurrent evals can draw the same integer, open the same SQLite
# file, and corrupt each other's tests. This produced flaky ~1-in-3 failures in
# 102_002 (2026-07-13); 102_003 had the same latent bug and 102_004 used a
# completely FIXED filename. `EvalTask.Runner.uniq_suffix/0` has always followed
# this rule — the harnesses did not.
#
# A path that is deliberately meant NOT to exist (e.g.
# "/tmp/does_not_exist_#{:rand.uniform(999_999)}.csv", used to test error paths)
# is exempt: a collision there is harmless, both sides expect a missing file.
#
#   mix run scripts/lint_temp_paths.exs          # gate: exits 1 on a violation
#   mix run scripts/lint_temp_paths.exs -- --list  # show every harness it checked

defmodule LintTempPaths do
  @moduledoc false

  # Builds a path in a shared directory.
  @shared ~r/System\.tmp_dir!?\(\)|"\/tmp/
  # Deliberately-missing paths: a collision is harmless.
  @exempt ~r/does_not_exist|no_such|missing_file/

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [list: :boolean])

    {checked, violations} =
      "tasks/*/test_harness.exs"
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce({0, []}, fn path, {n, bad} ->
        src = File.read!(path)

        cond do
          not Regex.match?(@shared, src) ->
            {n, bad}

          Regex.match?(@exempt, src) and not sqlite?(src) ->
            {n + 1, bad}

          String.contains?(src, "System.pid()") ->
            {n + 1, bad}

          true ->
            {n + 1, [{path, reason(src)} | bad]}
        end
      end)

    if opts[:list], do: IO.puts("checked #{checked} harness(es) that build a shared temp path")

    case violations do
      [] ->
        IO.puts("temp-path lint: #{checked} shared-path harness(es), 0 violations ✓")

      bad ->
        IO.puts("temp-path lint: #{length(bad)} VIOLATION(S) — a parallel eval can collide:\n")

        for {path, why} <- Enum.reverse(bad) do
          IO.puts("  #{path}\n      #{why}")
        end

        IO.puts("""

        Fix: include System.pid() in the path, alongside
        System.unique_integer([:positive]) — see EvalTask.Runner.uniq_suffix/0.
        """)

        System.halt(1)
    end
  end

  defp sqlite?(src), do: String.contains?(src, ".sqlite") or String.contains?(src, ".db")

  defp reason(src) do
    if String.contains?(src, "System.unique_integer"),
      do: "uses System.unique_integer WITHOUT System.pid() (unique per BEAM, not per OS process)",
      else: "builds a shared temp path with NO per-process uniqueness at all"
  end
end

LintTempPaths.main(System.argv())
