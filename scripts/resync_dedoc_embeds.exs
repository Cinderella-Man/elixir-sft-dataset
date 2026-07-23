# resync_dedoc_embeds.exs — the standing drift gate for `dedoc_` dirs
# (docs/14 invariant 3: derived files must be regenerable, and gates must prove
# they still are).
#
# A dedoc_ dir is a DETERMINISTIC projection of its parent `_01`:
#   prompt.md        <- GenTask.Dedoc.prompt_md(GenTask.Dedoc.strip(parent solution))
#   solution.ex      <- the parent's solution.ex, byte-for-byte
#   test_harness.exs <- the parent's test_harness.exs, byte-for-byte
#   manifest.exs     <- the parent's manifest.exs when it has one
#
# Editing the parent gold or harness (or the stripper/template) makes the child
# stale. Dry by default (CI greps the output for `would_resync|error`);
# `--apply` rewrites. `--only "glob"` scopes.
#
#   mix run scripts/resync_dedoc_embeds.exs
#   mix run scripts/resync_dedoc_embeds.exs -- --only "dedoc_022*" --apply

alias GenTask.{Config, Dedoc}

defmodule ResyncDedocEmbeds do
  @moduledoc false

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [apply: :boolean, only: :string, self_test: :boolean])

    if opts[:self_test] do
      self_test()
    else
      if opts[:apply], do: refuse_if_generate_alive!()

      results = run_over(Config.new([]), opts[:apply] == true, opts[:only])

      for {:error, dir, why} <- results, do: IO.puts("  error #{Path.basename(dir)}: #{why}")

      for {:would_resync, dir, files} <- results,
          do: IO.puts("  would_resync #{Path.basename(dir)}: #{Enum.join(files, ", ")}")

      for {:resynced, dir, files} <- results,
          do: IO.puts("  resynced #{Path.basename(dir)}: #{Enum.join(files, ", ")}")

      summary = Enum.frequencies_by(results, &elem(&1, 0))

      IO.puts(
        "dedoc embeds: #{inspect(summary)}#{if opts[:apply], do: "", else: " (report only)"}"
      )
    end
  end

  @doc false
  def run_over(cfg, apply?, only \\ nil) do
    Path.wildcard("#{cfg.tasks_dir}/dedoc_*")
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(&match_only?(Path.basename(&1), only))
    |> Enum.sort()
    |> Enum.map(&sync(&1, cfg, apply?))
  end

  # Proves the gate is not vacuous (the check_embeds --self-test pattern): a
  # sandbox dedoc dir derived through the REAL stripper + template must pass
  # clean, a planted edit must be detected, --apply must heal it byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_dedoc_st_#{System.unique_integer([:positive])}")
    tasks = Path.join(root, "tasks")
    parent = Path.join(tasks, "001_001_widget_01")
    dedoc = Path.join(tasks, "dedoc_001_001_widget")
    for d <- [parent, dedoc], do: File.mkdir_p!(d)

    gold = """
    defmodule W do
      @moduledoc "Widget."

      @doc "Runs."
      @spec go() :: :ok
      def go, do: :ok
    end
    """

    File.write!(Path.join(parent, "prompt.md"), "# Widget\n")
    File.write!(Path.join(parent, "solution.ex"), gold)
    File.write!(Path.join(parent, "test_harness.exs"), "defmodule WTest do\nend\n")

    File.write!(Path.join(dedoc, "prompt.md"), Dedoc.prompt_md(Dedoc.strip(gold), Path.basename(dedoc)))
    File.cp!(Path.join(parent, "solution.ex"), Path.join(dedoc, "solution.ex"))
    File.cp!(Path.join(parent, "test_harness.exs"), Path.join(dedoc, "test_harness.exs"))

    cfg = %Config{tasks_dir: tasks}
    verdict = fn results -> results |> Enum.map(&elem(&1, 0)) |> Enum.sort() end

    checks = [
      {"a clean sandbox dir passes", verdict.(run_over(cfg, false)) == [:unchanged]},
      {"a planted prompt edit is detected",
       (
         File.write!(Path.join(dedoc, "prompt.md"), "DRIFTED\n")
         verdict.(run_over(cfg, false)) == [:would_resync]
       )},
      {"--apply heals it byte-for-byte", verdict.(run_over(cfg, true)) == [:resynced]},
      {"the healed dir passes again", verdict.(run_over(cfg, false)) == [:unchanged]},
      {"a planted gold edit on the PARENT is detected in the child",
       (
         File.write!(
           Path.join(parent, "solution.ex"),
           String.replace(gold, "def go, do: :ok", "def go, do: :changed")
         )

         verdict.(run_over(cfg, false)) == [:would_resync]
       )}
    ]

    File.rm_rf!(root)

    for {label, ok?} <- checks,
        do: IO.puts("  #{if ok?, do: "caught ✓", else: "MISSED ✗"}  #{label}")

    if Enum.all?(checks, &elem(&1, 1)) do
      IO.puts("\ndedoc-embed self-test: OK ✓ (all #{length(checks)} checks pass)")
    else
      IO.puts("\ndedoc-embed SELF-TEST FAILED")
      System.halt(1)
    end
  end

  defp sync(dir, cfg, apply?) do
    case expected_files(dir, cfg) do
      {:error, why} ->
        {:error, dir, why}

      {:ok, expected} ->
        stale =
          for {name, body} <- Enum.sort(expected),
              File.read(Path.join(dir, name)) != {:ok, body},
              do: name

        cond do
          stale == [] ->
            {:unchanged, dir, []}

          apply? ->
            for name <- stale, do: File.write!(Path.join(dir, name), expected[name])
            {:resynced, dir, stale}

          true ->
            {:would_resync, dir, stale}
        end
    end
  end

  # Re-derive every file of the dedoc_ dir from its parent, byte-for-byte —
  # through the SAME stripper + template the minter uses.
  defp expected_files(dir, cfg) do
    parent_dir =
      Path.join(
        cfg.tasks_dir,
        Path.basename(dir) |> String.replace_prefix("dedoc_", "") |> Kernel.<>("_01")
      )

    if File.dir?(parent_dir) do
      gold = File.read!(Path.join(parent_dir, "solution.ex"))

      expected = %{
        "prompt.md" => Dedoc.prompt_md(Dedoc.strip(gold), Path.basename(dir)),
        "solution.ex" => gold,
        "test_harness.exs" => File.read!(Path.join(parent_dir, "test_harness.exs"))
      }

      manifest = Path.join(parent_dir, "manifest.exs")

      expected =
        if File.regular?(manifest),
          do: Map.put(expected, "manifest.exs", File.read!(manifest)),
          else: expected

      {:ok, expected}
    else
      {:error, "parent dir #{parent_dir} missing"}
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

ResyncDedocEmbeds.main(System.argv())
