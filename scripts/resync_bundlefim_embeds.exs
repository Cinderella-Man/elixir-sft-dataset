# resync_bundlefim_embeds.exs — regenerate bundle-FIM dirs from the CURRENT
# parent.
#
#   mix run scripts/resync_bundlefim_embeds.exs -- --only "016_001*" [--apply]
#   mix run scripts/resync_bundlefim_embeds.exs -- --self-test
#
# A bundle-FIM child is FULLY derived: prompt.md = GenTask.BundleFimTemplate
# over (holed path, parent spec, stripped parent with that file blanked),
# solution.ex = the file's verbatim content. A parent prompt OR bundle edit
# silently stales it. This gate re-derives both files byte-exactly by the
# path in the child's own heading. A path the parent no longer carries is an
# ERROR (fix_child class). Children NOT built by this template (LLM-era
# function-hole bundle fims) are skipped structurally by the heading test.
#
# Report-only exit like the sibling gates: pre-push/CI grep the output for
# would_resync/ERROR and do the failing.

defmodule ResyncBundlefimEmbeds do
  @moduledoc false

  alias EvalTask.Bundle
  alias GenTask.BundleFimTemplate

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
      Path.wildcard("#{tasks_root()}/[0-9]*_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn d ->
        base = Path.basename(d)

        child? =
          match?(
            {n, ""} when n >= 2,
            base |> String.split("_") |> List.last() |> Integer.parse()
          )

        child? and Enum.any?(globs, &match_glob?(base, &1)) and
          bundlefim_prompt?(Path.join(d, "prompt.md"))
      end)
      |> Enum.sort()
      |> Enum.map(&resync(&1, apply?))

    freq = Enum.frequencies_by(results, &elem(&1, 0))

    IO.puts(
      "bundlefim embeds: #{inspect(freq)}#{if apply?, do: " — APPLIED", else: " (report only)"}"
    )

    for {:would_resync, dir, _} <- results, do: IO.puts("  would_resync #{dir}")
    for {:error, dir, msg} <- results, do: IO.puts("  ERROR #{dir}: #{msg}")
  end

  defp bundlefim_prompt?(path) do
    case File.read(path) do
      {:ok, p} -> String.starts_with?(p, "# Implement the missing file")
      _ -> false
    end
  end

  defp resync(dir, apply?) do
    base = Path.basename(dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    parent_dir = Path.join(Path.dirname(dir), parent)

    with {:parent, {:ok, src}} <- {:parent, File.read(Path.join(parent_dir, "solution.ex"))},
         {:spec, {:ok, spec}} <- {:spec, File.read(Path.join(parent_dir, "prompt.md"))},
         {:ok, prompt} <- File.read(Path.join(dir, "prompt.md")),
         {:path, [_, path]} <-
           {:path, Regex.run(~r/## The bundle with `([^`\n]+)` missing/, prompt)},
         {:body, body} when is_binary(body) <-
           {:body, Bundle.parse(src) |> Enum.find_value(fn {p, b} -> p == path && b end)} do
      stripped = Bundle.strip_markers(src)

      if length(String.split(stripped, body)) != 2 do
        {:error, dir, "file body not uniquely locatable in the stripped parent"}
      else
        skeleton = String.replace(stripped, body, "# TODO")

        expected = %{
          "prompt.md" => BundleFimTemplate.prompt(path, spec, skeleton),
          "solution.ex" => String.trim_trailing(body, "\n")
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
      end
    else
      {:parent, _} -> {:error, dir, "parent bundle missing"}
      {:spec, _} -> {:error, dir, "parent prompt missing"}
      {:path, _} -> {:error, dir, "no bundle-marker heading in the prompt"}
      {:body, _} -> {:error, dir, "holed path no longer exists in the parent (fix_child class)"}
      _ -> {:error, dir, "prompt.md unreadable"}
    end
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # Env-overridable so the self-test can sandbox the corpus root.
  defp tasks_root, do: System.get_env("RESYNC_TASKS_DIR") || "tasks"

  # Proves the gate is not vacuous: one REAL bundle-FIM family copied into a
  # sandbox must pass clean; a planted PARENT spec edit must be detected;
  # --apply must heal byte-for-byte.
  defp self_test do
    root =
      Path.join(System.tmp_dir!(), "resync_bundlefim_st_#{System.unique_integer([:positive])}")

    sandbox = Path.join(root, "tasks")
    File.mkdir_p!(sandbox)

    child =
      Path.wildcard("tasks/[0-9]*_*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.sort()
      |> Enum.find(&bundlefim_prompt?(Path.join(&1, "prompt.md"))) ||
        raise "self-test needs at least one bundle-FIM dir in tasks/"

    base = Path.basename(child)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"

    for d <- [Path.join("tasks", parent), child],
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

        [
          {"a clean copied family passes", clean},
          {"a planted PARENT spec edit is detected", drift},
          {"--apply heals the dir", healed},
          {"the healed dir passes again", again}
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
      IO.puts("\nbundlefim-embed self-test: OK ✓ (all #{length(checks)} checks pass)")
    else
      IO.puts("\nbundlefim-embed SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ResyncBundlefimEmbeds.main(System.argv())
