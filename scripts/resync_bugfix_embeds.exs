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

    if freq[:error], do: System.halt(1)
  end

  defp resync(dir, apply?) do
    prompt = File.read!(Path.join(dir, "prompt.md"))
    parent = EvalTask.Runner.bugfix_parent_dir(dir)

    with {:ok, buggy} <- capture(@buggy, prompt, "buggy module fence"),
         {:ok, report} <- capture(@report, prompt, "failing test report fence"),
         {:ok, spec} <- File.read(Path.join(parent, "prompt.md")) do
      seed = %{files: %{"prompt.md" => spec}}
      want = Bugfix.prompt_md(seed, buggy, report)

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
      {:error, why} ->
        IO.puts("  ERROR #{dir}: #{why}")
        :error
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
          {"the healed dir passes again", resync(sandbox_child, false) == :unchanged}
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
