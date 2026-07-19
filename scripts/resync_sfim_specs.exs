# resync_sfim_specs.exs — regenerate sfim prompt "## The task" spec embeds
# from the CURRENT parent prompt.md.
#
#   mix run scripts/resync_sfim_specs.exs -- --only "077_001*" [--apply]
#   mix run scripts/resync_sfim_specs.exs -- --self-test
#
# A deterministic sfim child (`<family>_0N`, minted by scripts/mint_sfim.exs)
# embeds the parent `_01` spec VERBATIM between the template's `## The task`
# section and its `## The module with `name` missing` marker. Editing a parent
# prompt silently stales that embed: module-FIM resync only re-derives the
# skeleton fence, and none of the other five drift gates scan fim dirs for
# spec embeds (the gap filed on 2026-07-19, STATUS STEP 4). This gate rebuilds
# the section deterministically — `String.trim(parent prompt.md)` — and
# byte-compares. LLM-era fim children (free prose, no template markers) are
# skipped structurally, not by naming.
#
# Without --apply it only reports which prompts would change; --apply rewrites
# the section in place. Idempotent: resyncing twice is a no-op. A child whose
# markers or parent are missing is an ERROR (never silently skipped).

defmodule ResyncSfimSpecs do
  @moduledoc false

  @header "# Implement the missing function"
  @task_marker "\n## The task\n\n"

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
      sfim_children(globs)
      |> Enum.map(&resync(&1, apply?))

    freq = Enum.frequencies_by(results, &elem(&1, 0))
    IO.puts("sfim-spec resync: #{inspect(freq)}")

    for {:would_resync, dir, _} <- results, do: IO.puts("  would_resync #{dir}")

    # Report-only, like the sibling resync gates: pre-push/CI grep the output
    # for would_resync/ERROR and do the failing — a nonzero exit here would
    # kill the `set -e` hook before the diagnostic lines print.
    for {:error, dir, msg} <- results, do: IO.puts("  ERROR #{dir}: #{msg}")
  end

  # Every `<a>_<b>_<slug>_0N` (N >= 2) dir whose prompt carries the sfim
  # template header — LLM-era fim children fail the marker test and drop out.
  defp sfim_children(globs) do
    Path.wildcard("#{tasks_root()}/*_*")
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(fn d ->
      base = Path.basename(d)

      numeric_family? = match?({_, ""}, Integer.parse(hd(String.split(base, "_"))))

      child? =
        case base |> String.split("_") |> List.last() |> Integer.parse() do
          {n, ""} -> n >= 2
          _ -> false
        end

      numeric_family? and child? and Enum.any?(globs, &match_glob?(base, &1)) and
        sfim_prompt?(Path.join(d, "prompt.md"))
    end)
    |> Enum.sort()
  end

  defp sfim_prompt?(path) do
    case File.read(path) do
      {:ok, p} -> String.starts_with?(p, @header) and String.contains?(p, @task_marker)
      _ -> false
    end
  end

  defp resync(dir, apply?) do
    base = Path.basename(dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    parent_prompt = Path.join([Path.dirname(dir), parent, "prompt.md"])

    with {:parent, {:ok, spec}} <- {:parent, File.read(parent_prompt)},
         {:ok, prompt} <- File.read(Path.join(dir, "prompt.md")),
         {:split, {:ok, head, embedded, tail}} <- {:split, split_prompt(prompt)} do
      expected = String.trim(spec)

      cond do
        embedded == expected ->
          {:unchanged, dir, nil}

        apply? ->
          File.write!(Path.join(dir, "prompt.md"), head <> expected <> tail)
          {:resynced, dir, nil}

        true ->
          {:would_resync, dir, nil}
      end
    else
      {:parent, _} -> {:error, dir, "parent prompt missing: #{parent_prompt}"}
      {:split, {:error, msg}} -> {:error, dir, msg}
      _ -> {:error, dir, "prompt.md unreadable"}
    end
  end

  # head | spec | tail, split on the template's own markers. The module marker
  # is matched as a full line (`## The module with `…` missing`) and the LAST
  # occurrence wins — the embedded spec may contain `## ` headers of its own,
  # but the template's module fence always sits below the spec.
  defp split_prompt(prompt) do
    with [pre, rest] <- String.split(prompt, @task_marker, parts: 2),
         [_ | _] = matches <-
           Regex.scan(~r/\n\n## The module with `[^`\n]+` missing\n/, rest, return: :index) do
      {mod_off, _len} = matches |> List.last() |> hd()
      spec = binary_part(rest, 0, mod_off)
      tail = binary_part(rest, mod_off, byte_size(rest) - mod_off)
      {:ok, pre <> @task_marker, spec, tail}
    else
      _ -> {:error, "sfim template markers not found (task/module sections)"}
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # Env-overridable so the self-test can sandbox the corpus root.
  defp tasks_root, do: System.get_env("RESYNC_TASKS_DIR") || "tasks"

  # Proves the gate is not vacuous: one REAL sfim family copied into a
  # sandbox must pass clean; a planted PARENT spec edit (the actual drift
  # class) must be detected; --apply must heal the child byte-for-byte.
  defp self_test do
    root = Path.join(System.tmp_dir!(), "resync_sfim_st_#{System.unique_integer([:positive])}")
    sandbox = Path.join(root, "tasks")
    File.mkdir_p!(sandbox)

    child =
      sfim_children(["*"])
      |> List.first() ||
        raise "self-test needs at least one sfim child in tasks/"

    base = Path.basename(child)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"

    for d <- [Path.join(Path.dirname(child), parent), child],
        do: File.cp_r!(d, Path.join(sandbox, Path.basename(d)))

    sb_child = Path.join(sandbox, base)
    sb_parent_prompt = Path.join([sandbox, parent, "prompt.md"])
    prev = System.get_env("RESYNC_TASKS_DIR")
    System.put_env("RESYNC_TASKS_DIR", sandbox)

    checks =
      try do
        clean = match?({:unchanged, _, _}, resync(sb_child, false))

        File.write!(
          sb_parent_prompt,
          File.read!(sb_parent_prompt) <> "\nA planted requirement line.\n"
        )

        drift = match?({:would_resync, _, _}, resync(sb_child, false))
        healed = match?({:resynced, _, _}, resync(sb_child, true))
        again = match?({:unchanged, _, _}, resync(sb_child, false))

        embedded_now =
          sb_child |> Path.join("prompt.md") |> File.read!() |> split_prompt() |> elem(2)

        byte_equal = embedded_now == String.trim(File.read!(sb_parent_prompt))

        [
          {"a clean copied family passes", clean},
          {"a planted PARENT spec edit is detected", drift},
          {"--apply heals the child", healed},
          {"the healed child passes again", again},
          {"healed embed equals the new parent spec byte-for-byte", byte_equal}
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
      IO.puts("\nsfim-spec self-test: OK ✓ (all #{length(checks)} checks pass; child: #{base})")
    else
      IO.puts("\nsfim-spec SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncSfimSpecs.main(System.argv())
