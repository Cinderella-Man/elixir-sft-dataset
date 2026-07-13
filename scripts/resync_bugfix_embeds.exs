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
    {opts, _, _} = OptionParser.parse(argv, strict: [apply: :boolean, only: :string])
    apply? = opts[:apply] || false

    if apply?, do: refuse_if_generate_alive!()

    dirs =
      "tasks/bugfix_*"
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
end

ResyncBugfix.main(System.argv())
