# resync_adapt_embeds.exs — the standing drift gate for `adapt_` dirs
# (docs/14 invariant 3: derived files must be regenerable, and gates must prove
# they still are).
#
# An adapt_ dir is a DETERMINISTIC projection of three parents:
#   prompt.md        <- GenTask.Adapt.prompt_md(base gold, variation prompt)
#   solution.ex      <- the variation's solution.ex, byte-for-byte
#   test_harness.exs <- the variation's test_harness.exs, byte-for-byte
#   manifest.exs     <- the variation's manifest.exs when it has one
#
# Editing the base gold, the variation prompt, the variation gold, or the
# variation harness makes the child stale. Dry by default (CI greps the output
# for `would_resync|error`); `--apply` rewrites. `--only "glob"` scopes.
#
#   mix run scripts/resync_adapt_embeds.exs
#   mix run scripts/resync_adapt_embeds.exs -- --only "adapt_022*" --apply

alias GenTask.{Adapt, Config}

defmodule ResyncAdaptEmbeds do
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
        "adapt embeds: #{inspect(summary)}#{if opts[:apply], do: "", else: " (report only)"}"
      )
    end
  end

  @doc false
  def run_over(cfg, apply?, only \\ nil) do
    Path.wildcard("#{cfg.tasks_dir}/adapt_*")
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(&match_only?(Path.basename(&1), only))
    |> Enum.sort()
    |> Enum.map(&sync(&1, cfg, apply?))
  end

  # Proves the gate is not vacuous (the check_embeds --self-test pattern): a
  # sandbox adapt dir derived through the REAL template must pass clean, a
  # planted edit must be detected, --apply must heal it byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_adapt_st_#{System.unique_integer([:positive])}")
    tasks = Path.join(root, "tasks")
    base = Path.join(tasks, "001_001_base_01")
    var = Path.join(tasks, "001_002_var_01")
    adapt = Path.join(tasks, "adapt_001_002_var")
    for d <- [base, var, adapt], do: File.mkdir_p!(d)

    File.write!(Path.join(base, "solution.ex"), "defmodule B do\n  def go, do: :b\nend\n")
    File.write!(Path.join(var, "prompt.md"), "# Variation spec\n\nDo V instead.\n")
    File.write!(Path.join(var, "solution.ex"), "defmodule V do\n  def go, do: :v\nend\n")
    File.write!(Path.join(var, "test_harness.exs"), "defmodule VTest do\nend\n")

    File.write!(
      Path.join(adapt, "prompt.md"),
      GenTask.Adapt.prompt_md(
        File.read!(Path.join(base, "solution.ex")),
        File.read!(Path.join(var, "prompt.md")),
        Path.basename(adapt)
      )
    )

    File.cp!(Path.join(var, "solution.ex"), Path.join(adapt, "solution.ex"))
    File.cp!(Path.join(var, "test_harness.exs"), Path.join(adapt, "test_harness.exs"))

    cfg = %Config{tasks_dir: tasks}
    verdict = fn results -> results |> Enum.map(&elem(&1, 0)) |> Enum.sort() end

    checks = [
      {"a clean sandbox dir passes", verdict.(run_over(cfg, false)) == [:unchanged]},
      {"a planted prompt edit is detected",
       (
         File.write!(Path.join(adapt, "prompt.md"), "DRIFTED\n")
         verdict.(run_over(cfg, false)) == [:would_resync]
       )},
      {"--apply heals it byte-for-byte", verdict.(run_over(cfg, true)) == [:resynced]},
      {"the healed dir passes again", verdict.(run_over(cfg, false)) == [:unchanged]},
      {"a planted gold edit on the VARIATION is detected in the child",
       (
         File.write!(Path.join(var, "solution.ex"), "defmodule V2 do\nend\n")
         verdict.(run_over(cfg, false)) == [:would_resync]
       )}
    ]

    File.rm_rf!(root)

    for {label, ok?} <- checks,
        do: IO.puts("  #{if ok?, do: "caught ✓", else: "MISSED ✗"}  #{label}")

    if Enum.all?(checks, &elem(&1, 1)) do
      IO.puts("\nadapt-embed self-test: OK ✓ (all #{length(checks)} checks pass)")
    else
      IO.puts("\nadapt-embed SELF-TEST FAILED")
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

  # Re-derive every file of the adapt_ dir from its parents, byte-for-byte —
  # through the SAME template function the minter uses (GenTask.Adapt.prompt_md/2).
  defp expected_files(dir, cfg) do
    var_dir =
      Path.join(
        cfg.tasks_dir,
        Path.basename(dir) |> String.replace_prefix("adapt_", "") |> Kernel.<>("_01")
      )

    with {:var, true} <- {:var, File.dir?(var_dir)},
         num = var_num(var_dir),
         base_dir when is_binary(base_dir) <- Adapt.base_dir(cfg, num) || {:error, :no_base} do
      base_gold = File.read!(Path.join(base_dir, "solution.ex"))
      var_prompt = File.read!(Path.join(var_dir, "prompt.md"))

      expected = %{
        "prompt.md" => Adapt.prompt_md(base_gold, var_prompt, Path.basename(dir)),
        "solution.ex" => File.read!(Path.join(var_dir, "solution.ex")),
        "test_harness.exs" => File.read!(Path.join(var_dir, "test_harness.exs"))
      }

      manifest = Path.join(var_dir, "manifest.exs")

      expected =
        if File.regular?(manifest),
          do: Map.put(expected, "manifest.exs", File.read!(manifest)),
          else: expected

      {:ok, expected}
    else
      {:var, false} -> {:error, "variation dir #{var_dir} missing"}
      {:error, :no_base} -> {:error, "no base `_001_*_01` sibling on disk"}
    end
  end

  defp var_num(var_dir) do
    [a | _] = var_dir |> Path.basename() |> String.split("_")
    String.to_integer(a)
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

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module's pure decision functions without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncAdaptEmbeds.main(System.argv())
