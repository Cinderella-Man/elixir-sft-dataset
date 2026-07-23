# resync_tdd_embeds.exs — regenerate tdd_ dirs from the CURRENT parent.
#
#   mix run scripts/resync_tdd_embeds.exs -- --only "043_001*" [--apply]
#   mix run scripts/resync_tdd_embeds.exs -- --self-test
#
# A tdd_ dir is FULLY derived: prompt.md = GenTask.TddTemplate over the parent
# harness (tests-as-spec), solution.ex + test_harness.exs = byte-copies of the
# parent gold + harness. Editing the parent (a harness growth, a gold repair)
# silently stales all three. This gate re-derives every file byte-exactly —
# harness drift and template-wording drift are the same failure to it. Same
# single-source policy as resync_sfim_specs (2026-07-19).
#
# Report-only exit like the sibling gates: pre-push/CI grep the output for
# would_resync/ERROR and do the failing.

defmodule ResyncTddEmbeds do
  @moduledoc false

  def main(argv) do
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

    results =
      Path.wildcard("#{tasks_root()}/tdd_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn d ->
        base = Path.basename(d)
        family = String.replace_prefix(base, "tdd_", "")
        Enum.any?(globs, &match_glob?(family, &1)) or Enum.any?(globs, &match_glob?(base, &1))
      end)
      |> Enum.sort()
      |> Enum.map(&resync(&1, apply?))

    freq = Enum.frequencies_by(results, &elem(&1, 0))
    IO.puts("tdd embeds: #{inspect(freq)}#{if apply?, do: " — APPLIED", else: " (report only)"}")

    for {:would_resync, dir, _} <- results, do: IO.puts("  would_resync #{dir}")
    for {:error, dir, msg} <- results, do: IO.puts("  ERROR #{dir}: #{msg}")
  end

  defp resync(dir, apply?) do
    family = dir |> Path.basename() |> String.replace_prefix("tdd_", "")
    parent = Path.join(Path.dirname(dir), family <> "_01")

    with {:parent, true} <- {:parent, File.dir?(parent)},
         {:ok, p_sol} <- File.read(Path.join(parent, "solution.ex")),
         {:ok, p_harness} <- File.read(Path.join(parent, "test_harness.exs")) do
      expected = %{
        "prompt.md" => GenTask.TddTemplate.prompt(p_harness, Path.basename(dir)),
        "solution.ex" => p_sol,
        "test_harness.exs" => p_harness
      }

      stale =
        Enum.filter(expected, fn {name, want} ->
          File.read(Path.join(dir, name)) != {:ok, want}
        end)

      cond do
        stale == [] ->
          {:unchanged, dir, nil}

        apply? ->
          for {name, want} <- stale, do: File.write!(Path.join(dir, name), want)
          {:resynced, dir, nil}

        true ->
          {:would_resync, dir, nil}
      end
    else
      {:parent, false} -> {:error, dir, "parent dir missing: #{parent}"}
      _ -> {:error, dir, "parent files unreadable: #{parent}"}
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # Env-overridable so the self-test can sandbox the corpus root.
  defp tasks_root, do: System.get_env("RESYNC_TASKS_DIR") || "tasks"

  # Proves the gate is not vacuous: one REAL tdd_ family copied into a
  # sandbox must pass clean; a planted PARENT harness edit (the actual drift
  # class — e.g. a promise-audit growth) must be detected in BOTH the prompt
  # embed and the harness copy; --apply must heal byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_tdd_st_#{System.unique_integer([:positive])}")
    sandbox = Path.join(root, "tasks")
    File.mkdir_p!(sandbox)

    child =
      Path.wildcard("tasks/tdd_*") |> Enum.filter(&File.dir?/1) |> Enum.sort() |> List.first() ||
        raise "self-test needs at least one tdd_ dir in tasks/"

    family = child |> Path.basename() |> String.replace_prefix("tdd_", "")
    parent = Path.join("tasks", family <> "_01")

    for d <- [parent, child], do: File.cp_r!(d, Path.join(sandbox, Path.basename(d)))

    sb_child = Path.join(sandbox, Path.basename(child))
    sb_parent_harness = Path.join([sandbox, family <> "_01", "test_harness.exs"])
    prev = System.get_env("RESYNC_TASKS_DIR")
    System.put_env("RESYNC_TASKS_DIR", sandbox)

    checks =
      try do
        clean = match?({:unchanged, _, _}, resync(sb_child, false))

        File.write!(
          sb_parent_harness,
          File.read!(sb_parent_harness) <> "\n# a planted harness growth\n"
        )

        drift = match?({:would_resync, _, _}, resync(sb_child, false))
        healed = match?({:resynced, _, _}, resync(sb_child, true))
        again = match?({:unchanged, _, _}, resync(sb_child, false))

        byte_equal =
          File.read!(Path.join(sb_child, "test_harness.exs")) ==
            File.read!(sb_parent_harness) and
            File.read!(Path.join(sb_child, "prompt.md")) ==
              GenTask.TddTemplate.prompt(File.read!(sb_parent_harness), Path.basename(sb_child))

        [
          {"a clean copied family passes", clean},
          {"a planted PARENT harness edit is detected", drift},
          {"--apply heals the dir", healed},
          {"the healed dir passes again", again},
          {"healed files equal the parent + template byte-for-byte", byte_equal}
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
      IO.puts("\ntdd-embed self-test: OK ✓ (all #{length(checks)} checks pass)")
    else
      IO.puts("\ntdd-embed SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncTddEmbeds.main(System.argv())
