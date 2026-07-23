# resync_bugfix_embeds.exs — keep bugfix_ prompts in sync with their parent spec.
#
# A `bugfix_<fam>_NN/prompt.md` embeds THREE things:
#   1. the parent `_01/prompt.md` verbatim (the task the module implements),
#   2. the BUGGY module (a captured one-line semantic mutant — immutable data),
#   3. the REAL failing-test report captured when that mutant was gated
#      (immutable data — it is evidence, not a derivation).
#
# Only (1) is derived, so only (1) may ever be rewritten. This script rebuilds
# each bugfix prompt from the CURRENT parent spec while preserving (2) and (3)
# byte-for-byte — the same contract as resync_tfim_embeds.exs, and the same
# gate: a dry run must report 0 would_resync in CI / pre-push, else a parent
# prompt was edited and its bugfix children now teach a stale spec.
#
# It ALSO verifies gold identity: the child's solution.ex must be byte-identical
# to the parent reference (audit_bugfix property 4). A parent-gold behavior edit
# without a bugfix re-mint leaves the child failing the parent harness while
# its buggy module + failing report stay captured mutants OF THE OLD GOLD —
# so `stale_gold` is NEVER healed by --apply (a gold copy would break the
# one-line-bug property); the only remediation is delete + deterministic
# re-mint (GEN_ONLY=topup). Found live 2026-07-23: bugfix_109_001_{01,02,03}
# reached main when a >20-family push overflowed the pre-push validate cap.
#
#   mix run scripts/resync_bugfix_embeds.exs                    # dry (gate)
#   mix run scripts/resync_bugfix_embeds.exs -- --apply
#   mix run scripts/resync_bugfix_embeds.exs -- --only "013_*"  # glob
#
# Refuses --apply while a generation loop is alive (it writes into tasks/).

alias GenTask.Bugfix

defmodule ResyncBugfix do
  @moduledoc false

  @buggy ~r/## The buggy module\n\n```elixir\n(.*?)\n```/s
  @report ~r/## Failing test report\n\n```\n(.*?)\n```/s

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [apply: :boolean, only: :string, self_test: :boolean])

    if opts[:self_test] do
      self_test()
      System.halt(0)
    end

    apply? = opts[:apply] || false

    if apply?, do: refuse_if_generate_alive!()

    dirs =
      "#{tasks_root()}/bugfix_*"
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(&match_only?(Path.basename(&1), opts[:only]))
      |> Enum.sort()

    freq =
      dirs
      |> Enum.map(&resync(&1, apply?))
      |> Enum.frequencies()

    IO.puts(
      "bugfix embeds: #{inspect(freq)}" <>
        if(apply?, do: " — APPLIED", else: " (report only)")
    )

    if freq[:error] || freq[:stale_gold], do: System.halt(1)
  end

  defp resync(dir, apply?) do
    prompt = File.read!(Path.join(dir, "prompt.md"))
    parent = EvalTask.Runner.bugfix_parent_dir(dir)

    with :ok <- gold_identity(dir, parent),
         {:ok, buggy} <- capture(@buggy, prompt, "buggy module fence"),
         {:ok, report} <- capture(@report, prompt, "failing test report fence"),
         {:ok, spec} <- File.read(Path.join(parent, "prompt.md")) do
      seed = %{files: %{"prompt.md" => spec}}
      want = Bugfix.prompt_md(seed, buggy, report, Path.basename(dir))

      cond do
        want == prompt ->
          :unchanged

        apply? ->
          File.write!(Path.join(dir, "prompt.md"), want)
          :resynced

        true ->
          IO.puts("  would resync #{dir} (parent spec changed)")
          :would_resync
      end
    else
      {:stale_gold, why} ->
        IO.puts("  STALE GOLD #{dir}: #{why}")
        :stale_gold

      {:error, why} ->
        IO.puts("  ERROR #{dir}: #{why}")
        :error
    end
  end

  # Gold identity is checked in BOTH modes and never healed here: the buggy
  # module and report are immutable captures of the OLD gold, so copying the
  # new gold over solution.ex would leave a multi-line buggy→gold diff and
  # break the shape's one-line-bug teaching contract.
  defp gold_identity(dir, parent) do
    with {:ok, child_gold} <- File.read(Path.join(dir, "solution.ex")),
         {:ok, parent_gold} <- File.read(Path.join(parent, "solution.ex")) do
      if child_gold == parent_gold do
        :ok
      else
        {:stale_gold,
         "solution.ex differs from the parent reference — delete the pair and " <>
           "re-mint (GEN_ONLY=topup mix run scripts/generate.exs <idea>); " <>
           "do NOT copy the gold over"}
      end
    else
      {:error, why} -> {:error, "solution.ex unreadable: #{inspect(why)}"}
    end
  end

  defp capture(re, prompt, what) do
    case Regex.run(re, prompt) do
      [_, body] -> {:ok, body}
      _ -> {:error, "no #{what} — prompt is not a bugfix prompt"}
    end
  end

  defp match_only?(_name, nil), do: true

  defp match_only?(name, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, name)
    end)
  end

  defp refuse_if_generate_alive! do
    {out, _} = System.cmd("pgrep", ["-af", "beam.smp"], stderr_to_stdout: true)

    if String.contains?(out, "generate.exs") do
      IO.puts("REFUSING --apply: a generation loop (generate.exs) is alive.")
      System.halt(1)
    end
  end

  # Env-overridable so the self-test (and tests) can sandbox the corpus root.
  defp tasks_root, do: System.get_env("RESYNC_TASKS_DIR") || "tasks"

  # Proves the gate is not vacuous (docs/12 §5.5 row 19): one REAL family is
  # copied into a sandbox, must pass clean; a planted spec edit must be
  # detected; --apply must heal it byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_bugfix_st_#{System.unique_integer([:positive])}")
    sandbox = Path.join(root, "tasks")
    File.mkdir_p!(sandbox)

    child = "tasks/bugfix_*" |> Path.wildcard() |> Enum.sort() |> List.first()
    parent = EvalTask.Runner.bugfix_parent_dir(child)
    for d <- [parent, child], do: File.cp_r!(d, Path.join(sandbox, Path.basename(d)))

    sandbox_child = Path.join(sandbox, Path.basename(child))
    sandbox_parent = Path.join(sandbox, Path.basename(parent))

    checks =
      try do
        [
          {"a clean copied family passes", resync(sandbox_child, false) == :unchanged},
          {"a planted PARENT spec edit is detected in the child",
           (
             File.write!(
               Path.join(sandbox_parent, "prompt.md"),
               File.read!(Path.join(sandbox_parent, "prompt.md")) <> "\nEDITED SPEC LINE\n"
             )

             resync(sandbox_child, false) == :would_resync
           )},
          {"--apply heals it byte-for-byte", resync(sandbox_child, true) == :resynced},
          {"the healed dir passes again", resync(sandbox_child, false) == :unchanged},
          {"a planted PARENT gold edit is detected as stale_gold",
           (
             gold_path = Path.join(sandbox_parent, "solution.ex")
             File.write!(gold_path, File.read!(gold_path) <> "\n# EDITED GOLD LINE\n")
             resync(sandbox_child, false) == :stale_gold
           )},
          {"--apply REFUSES to heal a stale gold", resync(sandbox_child, true) == :stale_gold}
        ]
      after
        File.rm_rf!(root)
      end

    for {label, ok?} <- checks,
        do: IO.puts("  #{if ok?, do: "caught ✓", else: "MISSED ✗"}  #{label}")

    if Enum.all?(checks, &elem(&1, 1)) do
      IO.puts(
        "\nbugfix-embed self-test: OK ✓ (all #{length(checks)} checks pass; family: #{Path.basename(child)})"
      )
    else
      IO.puts("\nbugfix-embed SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncBugfix.main(System.argv())
