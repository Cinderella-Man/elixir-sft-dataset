# resync_tfim_embeds.exs — regenerate tfim prompt.md embeds from the CURRENT parent.
#
#   mix run scripts/resync_tfim_embeds.exs -- --only "073_001*" [--apply]
#
# A tfim child's prompt.md embeds the parent `_01` module and the parent harness with
# the child's gold test blanked to `# TODO`. Editing the parent harness (e.g. the
# docs/10 R10 tightening pass appends tests) makes those embeds stale. This script
# rebuilds each embed DETERMINISTICALLY — `TestFim.test_blocks/1` + `skeletonize/2` +
# `prompt_md/2` on the current parent files — instead of hand-editing fenced text.
#
# Per child it locates the gold block by the test NAME taken from the child's
# solution.ex first line; a child whose gold test no longer exists in the parent
# harness is reported as an ERROR (never silently skipped). Without --apply it only
# reports which prompts would change. Idempotent: regenerating twice is a no-op.
#
# NOT covered: module-FIM (`_0N`) prompts (different structure, use GenTask.Fim) and
# wt_ prompts (their embeds are the module + spec, not the harness).

# Run under `mix run` (GenTask must be compiled) — no manual ebin path juggling here:
# prepending _build/test would shadow a fresh dev build with a stale test beam.

defmodule ResyncTfimEmbeds do
  @moduledoc false

  alias GenTask.TestFim

  def main(argv) do
    # `mix run script.exs -- --only ...` leaves the literal `--` in System.argv, and
    # OptionParser treats it as an end-of-options terminator — silently unscoping the
    # run. Accept both invocations by dropping a leading `--`.
    argv = Enum.drop_while(argv, &(&1 == "--"))
    {opts, _, _} = OptionParser.parse(argv, strict: [only: :string, apply: :boolean])
    apply? = opts[:apply] || false

    globs =
      case opts[:only] do
        nil -> ["*"]
        s -> String.split(s, ",", trim: true)
      end

    dirs =
      Path.wildcard("tasks/tfim_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn d ->
        base = Path.basename(d)
        family = base |> String.replace_prefix("tfim_", "")
        Enum.any?(globs, &match_glob?(family, &1)) or Enum.any?(globs, &match_glob?(base, &1))
      end)
      |> Enum.sort()

    results = Enum.map(dirs, &resync(&1, apply?))
    freq = Enum.frequencies(results)

    IO.puts("tfim embeds: #{inspect(freq)}" <> if(apply?, do: " — APPLIED", else: " (report only)"))
    if freq[:error], do: System.halt(1)
  end

  defp resync(dir, apply?) do
    parent = EvalTask.Fim.test_fim_parent_dir(dir)
    module_src = File.read!(Path.join(parent, "solution.ex"))
    harness = File.read!(Path.join(parent, "test_harness.exs"))
    gold = File.read!(Path.join(dir, "solution.ex"))

    with {:ok, name} <- gold_name(gold),
         {:ok, block} <- find_block(harness, name) do
      new_prompt = TestFim.prompt_md(module_src, TestFim.skeletonize(harness, block))
      prompt_path = Path.join(dir, "prompt.md")

      cond do
        File.read!(prompt_path) == new_prompt ->
          :unchanged

        apply? ->
          File.write!(prompt_path, new_prompt)
          :resynced

        true ->
          IO.puts("  would resync #{dir}")
          :would_resync
      end
    else
      {:error, why} ->
        IO.puts("  ERROR #{dir}: #{why}")
        :error
    end
  end

  defp gold_name(gold) do
    case Regex.run(~r/^\s*test\s+"((?:[^"\\]|\\.)*)"/m, gold) do
      [_, name] -> {:ok, name}
      _ -> {:error, "no test \"…\" opener in solution.ex"}
    end
  end

  defp find_block(harness, name) do
    case Enum.find(TestFim.test_blocks(harness), &(&1.name == name)) do
      nil -> {:error, "gold test #{inspect(name)} not found in the parent harness"}
      block -> {:ok, block}
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end
end

ResyncTfimEmbeds.main(System.argv())
