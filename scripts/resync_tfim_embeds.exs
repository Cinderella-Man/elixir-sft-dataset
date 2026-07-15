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

    {opts, _, _} =
      OptionParser.parse(argv, strict: [only: :string, apply: :boolean, self_test: :boolean])

    if opts[:self_test] do
      self_test()
      System.halt(0)
    end

    apply? = opts[:apply] || false

    globs =
      case opts[:only] do
        nil -> ["*"]
        s -> String.split(s, ",", trim: true)
      end

    dirs =
      Path.wildcard("#{tasks_root()}/tfim_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn d ->
        base = Path.basename(d)
        family = base |> String.replace_prefix("tfim_", "")
        Enum.any?(globs, &match_glob?(family, &1)) or Enum.any?(globs, &match_glob?(base, &1))
      end)
      |> Enum.sort()

    results = Enum.map(dirs, &resync(&1, apply?))
    freq = Enum.frequencies(results)

    IO.puts(
      "tfim embeds: #{inspect(freq)}" <> if(apply?, do: " — APPLIED", else: " (report only)")
    )

    if freq[:error], do: System.halt(1)
  end

  defp resync(dir, apply?) do
    parent = EvalTask.Fim.test_fim_parent_dir(dir)
    module_src = File.read!(Path.join(parent, "solution.ex"))
    harness = File.read!(Path.join(parent, "test_harness.exs"))
    gold = File.read!(Path.join(dir, "solution.ex"))

    with {:ok, name} <- gold_name(gold),
         {:ok, block} <- find_block(harness, name, File.read!(Path.join(dir, "prompt.md"))) do
      new_prompt =
        TestFim.prompt_md(
          module_src,
          TestFim.skeletonize(harness, block),
          TestFim.kind_of(harness, block)
        )

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

  # `property "…"` blocks carve exactly like `test` blocks (docs/13 §1.2) — the
  # gold-name regex must know both, or every property unit errors here (it did:
  # 28 of them, minted 2026-07-13, caught by the full-corpus dry run).
  defp gold_name(gold) do
    case Regex.run(~r/^\s*(?:test|property)\s+"((?:[^"\\]|\\.)*)"/m, gold) do
      [_, name] -> {:ok, name}
      _ -> {:error, "no test/property \"…\" opener in solution.ex"}
    end
  end

  # Locate by the QUALIFIED name (describe-prefix from the child's own prompt
  # skeleton): two describes may hold same-named tests, and a describe-nested gold
  # carries no describe context in its solution.ex.
  defp find_block(harness, name, child_prompt) do
    qual = TestFim.qual_from_prompt(child_prompt, name)

    case Enum.find(TestFim.carvable_blocks(harness), &(TestFim.qual(&1) == qual)) do
      nil -> {:error, "gold test #{inspect(qual)} not found in the parent harness"}
      block -> {:ok, block}
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # Env-overridable so the self-test (and tests) can sandbox the corpus root.
  defp tasks_root, do: System.get_env("RESYNC_TASKS_DIR") || "tasks"

  # Proves the gate is not vacuous (docs/12 §5.5 row 19): one REAL family is
  # copied into a sandbox, must pass clean; a planted prompt edit must be
  # detected; --apply must heal it byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_tfim_st_#{System.unique_integer([:positive])}")
    sandbox = Path.join(root, "tasks")
    File.mkdir_p!(sandbox)

    child = "tasks/tfim_*" |> Path.wildcard() |> Enum.sort() |> List.first()
    parent = EvalTask.Fim.test_fim_parent_dir(child)
    for d <- [parent, child], do: File.cp_r!(d, Path.join(sandbox, Path.basename(d)))

    sandbox_child = Path.join(sandbox, Path.basename(child))
    prev = System.get_env("RESYNC_TASKS_DIR")
    System.put_env("RESYNC_TASKS_DIR", sandbox)

    checks =
      try do
        [
          {"a clean copied family passes", resync(sandbox_child, false) == :unchanged},
          {"a planted prompt edit is detected",
           (
             File.write!(Path.join(sandbox_child, "prompt.md"), "DRIFTED\n")
             resync(sandbox_child, false) == :would_resync
           )},
          {"--apply heals it byte-for-byte", resync(sandbox_child, true) == :resynced},
          {"the healed dir passes again", resync(sandbox_child, false) == :unchanged}
        ]
      after
        if prev,
          do: System.put_env("RESYNC_TASKS_DIR", prev),
          else: System.delete_env("RESYNC_TASKS_DIR")

        File.rm_rf!(root)
      end

    for {label, ok?} <- checks,
        do: IO.puts("  #{if ok?, do: "caught ✓", else: "MISSED ✗"}  #{label}")

    if Enum.all?(checks, &elem(&1, 1)) do
      IO.puts(
        "\ntfim-embed self-test: OK ✓ (all #{length(checks)} checks pass; family: #{Path.basename(child)})"
      )
    else
      IO.puts("\ntfim-embed SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncTfimEmbeds.main(System.argv())
