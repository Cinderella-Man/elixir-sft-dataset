# resync_specfim_embeds.exs — regenerate specfim_ dirs from the CURRENT parent.
#
#   mix run scripts/resync_specfim_embeds.exs -- --only "001_001*" [--apply]
#   mix run scripts/resync_specfim_embeds.exs -- --self-test
#
# A specfim_ dir is FULLY derived: prompt.md = GenTask.SpecFimTemplate over
# the parent-minus-that-spec skeleton (GenTask.SpecFim — the same carve the
# miner uses), solution.ex = the attribute's verbatim span. A parent gold
# edit (spec tightened, module repaired) silently stales both files. This
# gate re-derives them byte-exactly by the site's `name/arity` id from the
# child's own prompt heading. A site the parent no longer carries is an
# ERROR (never silently skipped — the fix_child work-list class).
#
# Report-only exit like the sibling gates: pre-push/CI grep the output for
# would_resync/ERROR and do the failing.

defmodule ResyncSpecfimEmbeds do
  @moduledoc false

  alias GenTask.{SpecFim, SpecFimTemplate}

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
      Path.wildcard("#{tasks_root()}/specfim_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn d ->
        base = Path.basename(d)
        family = base |> String.replace_prefix("specfim_", "") |> String.replace(~r/_\d+$/, "")
        Enum.any?(globs, &match_glob?(family, &1)) or Enum.any?(globs, &match_glob?(base, &1))
      end)
      |> Enum.sort()
      |> Enum.map(&resync(&1, apply?))

    freq = Enum.frequencies_by(results, &elem(&1, 0))

    IO.puts(
      "specfim embeds: #{inspect(freq)}#{if apply?, do: " — APPLIED", else: " (report only)"}"
    )

    for {:would_resync, dir, _} <- results, do: IO.puts("  would_resync #{dir}")
    for {:error, dir, msg} <- results, do: IO.puts("  ERROR #{dir}: #{msg}")
  end

  defp resync(dir, apply?) do
    base = Path.basename(dir)
    family = base |> String.replace_prefix("specfim_", "") |> String.replace(~r/_\d+$/, "")
    parent_sol = Path.join([Path.dirname(dir), family <> "_01", "solution.ex"])

    with {:parent, {:ok, src}} <- {:parent, File.read(parent_sol)},
         {:ok, prompt} <- File.read(Path.join(dir, "prompt.md")),
         {:id, [_, id]} <-
           {:id, Regex.run(~r/the `@spec` for\n?`([a-z_0-9?!]+\/\d+)` has been removed/, prompt)},
         {:site, %{} = site} <- {:site, SpecFim.site_by_id(src, id)} do
      [name, arity] = String.split(id, "/")

      expected = %{
        "prompt.md" =>
          SpecFimTemplate.prompt(name, String.to_integer(arity), SpecFim.skeleton(src, site)),
        "solution.ex" => String.trim_trailing(site.span, "\n")
      }

      stale =
        Enum.filter(expected, fn {file, want} ->
          File.read(Path.join(dir, file)) != {:ok, want}
        end)

      cond do
        stale == [] ->
          {:unchanged, dir, nil}

        apply? ->
          for {file, want} <- stale, do: File.write!(Path.join(dir, file), want)
          {:resynced, dir, nil}

        true ->
          {:would_resync, dir, nil}
      end
    else
      {:parent, _} -> {:error, dir, "parent gold missing: #{parent_sol}"}
      {:id, _} -> {:error, dir, "site id not found in the prompt heading"}
      {:site, _} -> {:error, dir, "site no longer exists in the parent (fix_child class)"}
      _ -> {:error, dir, "prompt.md unreadable"}
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # Env-overridable so the self-test can sandbox the corpus root.
  defp tasks_root, do: System.get_env("RESYNC_TASKS_DIR") || "tasks"

  # Proves the gate is not vacuous: one REAL specfim family copied into a
  # sandbox must pass clean; a planted PARENT spec edit (return type changed)
  # must be detected in BOTH derived files; --apply must heal byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_specfim_st_#{System.unique_integer([:positive])}")
    sandbox = Path.join(root, "tasks")
    File.mkdir_p!(sandbox)

    child =
      Path.wildcard("tasks/specfim_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.sort()
      |> List.first() ||
        raise "self-test needs at least one specfim_ dir in tasks/"

    family =
      child
      |> Path.basename()
      |> String.replace_prefix("specfim_", "")
      |> String.replace(~r/_\d+$/, "")

    parent = Path.join("tasks", family <> "_01")
    for d <- [parent, child], do: File.cp_r!(d, Path.join(sandbox, Path.basename(d)))

    sb_child = Path.join(sandbox, Path.basename(child))
    sb_parent_sol = Path.join([sandbox, family <> "_01", "solution.ex"])
    gold_span = File.read!(Path.join(sb_child, "solution.ex"))
    prev = System.get_env("RESYNC_TASKS_DIR")
    System.put_env("RESYNC_TASKS_DIR", sandbox)

    checks =
      try do
        clean = match?({:unchanged, _, _}, resync(sb_child, false))

        # Plant: change the carved spec's return type IN THE PARENT.
        planted = String.replace(gold_span, ~r/(::(?!.*::).*)$/s, ":: :planted_return")

        File.write!(
          sb_parent_sol,
          String.replace(File.read!(sb_parent_sol), gold_span, planted)
        )

        drift = match?({:would_resync, _, _}, resync(sb_child, false))
        healed = match?({:resynced, _, _}, resync(sb_child, true))
        again = match?({:unchanged, _, _}, resync(sb_child, false))

        byte_equal =
          File.read!(Path.join(sb_child, "solution.ex")) ==
            String.trim_trailing(planted, "\n")

        [
          {"a clean copied family passes", clean},
          {"a planted PARENT spec edit is detected", drift},
          {"--apply heals the dir", healed},
          {"the healed dir passes again", again},
          {"healed gold equals the edited parent spec byte-for-byte", byte_equal}
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
      IO.puts("\nspecfim-embed self-test: OK ✓ (all #{length(checks)} checks pass)")
    else
      IO.puts("\nspecfim-embed SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncSpecfimEmbeds.main(System.argv())
