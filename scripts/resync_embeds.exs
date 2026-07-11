# resync_embeds.exs — regenerate module-FIM (`_0N`) and `wt_` dirs from the CURRENT
# parent. The remediation half of docs/12 §5.1 item 8 (scripts/check_embeds.exs is
# the detection half). One-shot catch-up tool: delete at the line per docs/12 §7.2.
#
#   mix run scripts/resync_embeds.exs -- --dirs-file <file> [--apply]
#   mix run scripts/resync_embeds.exs -- --self-test <flagged-dir>
#
# The dirs file lists one task dir per line — produce it from the checker so the
# scope is exactly what is currently flagged (NEVER run this over clean dirs: their
# embeds legitimately differ from regeneration by the historical mint conventions
# a/e/f/j that check_embeds tolerates; regenerating them is a scope decision, not
# remediation):
#
#   elixir scripts/check_embeds.exs > /tmp/embed_report.txt
#   grep -E '^(REFLOW|DRIFT)' /tmp/embed_report.txt | awk '{print $2}' > /tmp/embed_dirs.txt
#   mix run scripts/resync_embeds.exs -- --dirs-file /tmp/embed_dirs.txt --apply
#
# What "resync" means per kind:
#   * module-FIM child: fence := EvalTask.Fim.rewrite_skeleton(prompt,
#     EvalTask.Fim.build_skeleton(parent_src, child gold)). Bundle parents get the
#     `<file>` marker lines stripped from parent_src first (the loop never
#     deterministically rebuilds bundle skeletons, and the shipped embeds carry no
#     markers). When the gold itself is reflow-stale (locatable in the parent only
#     after whitespace normalization), the gold is FIRST rewritten from the
#     parent's current lines (re-indented to the gold's existing base indent) and
#     the skeleton built from that — recorded as `gold_rewritten` in the ledger.
#     A gold that cannot be located at all is an ERROR (the fix_child_gold
#     worklist — the parent was redesigned at the target; hand-fix, never auto).
#   * wt_ dir: full refresh to the generator's own outputs — solution.ex and
#     test_harness.exs byte-copied from the parent, prompt.md rebuilt by
#     GenTask.WriteTest.prompt_md(parent solution, parent prompt), manifest.exs
#     copied through when the parent carries one (mirrors WriteTest.build_files/2).
#
# Safety rails:
#   * --apply refuses to run while another BEAM is running scripts/generate.exs
#     (the generation loop rewrites task dirs; this script rewrites prompt.md).
#   * Every changed file is backed up to logs/embed_resync_backup/<dir>/ before
#     the write, and every action appended to logs/embed_resync.jsonl (idempotent:
#     a second run reports unchanged and appends nothing).
#   * A module-FIM prompt must contain EXACTLY one `# TODO`-bearing ```elixir
#     fence — rewrite_skeleton would replace every one of them, so 0 or >1 is an
#     ERROR, never a write.
#   * --self-test copies <flagged-dir> and its parent into a scratch tasks dir,
#     applies the resync there, and asserts `elixir scripts/check_embeds.exs`
#     reports the copy CLEAN. Exits 1 on failure. Never touches tasks/.

defmodule ResyncEmbeds do
  @moduledoc false

  @todo ~r/#\s*TODO/i
  @fence ~r/```elixir[ \t]*\n(.*?)\n[ \t]*```/s
  @bundle_marker ~r{^</?file( path=.*)?>$}
  @ledger "logs/embed_resync.jsonl"
  @backup_root "logs/embed_resync_backup"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [dirs_file: :string, apply: :boolean, self_test: :string]
      )

    cond do
      opts[:self_test] -> self_test(opts[:self_test])
      opts[:dirs_file] -> run(opts[:dirs_file], opts[:apply] || false)
      true -> IO.puts("need --dirs-file <file> or --self-test <dir>") && System.halt(1)
    end
  end

  defp run(dirs_file, apply?) do
    if apply? and generate_loop_alive?() do
      IO.puts("REFUSING --apply: a generation loop (mix run scripts/generate.exs) is alive.")
      System.halt(1)
    end

    dirs =
      dirs_file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    results = Enum.map(dirs, fn dir -> {dir, resync(dir, "tasks", apply?)} end)
    freq = results |> Enum.map(&elem(&1, 1)) |> Enum.frequencies()

    IO.puts(
      "resync_embeds over #{length(dirs)} dirs: #{inspect(freq)}" <>
        if(apply?, do: " — APPLIED", else: " (report only)")
    )

    for {dir, :error} <- results, do: IO.puts("  fix_child_gold / hand-fix: #{dir}")
    if freq[:error], do: System.halt(2)
  end

  # :unchanged | :resynced | :would_resync | :error
  defp resync(dir, tasks_dir, apply?) do
    base = Path.basename(dir)

    desired =
      cond do
        String.starts_with?(base, "wt_") -> desired_wt(dir, tasks_dir)
        true -> desired_fim(dir, tasks_dir)
      end

    case desired do
      {:error, why} ->
        IO.puts("  ERROR #{dir}: #{why}")
        :error

      {:ok, files, notes} ->
        changed = changed_files(dir, files)

        cond do
          changed == [] ->
            :unchanged

          apply? ->
            write!(dir, changed, notes)
            :resynced

          true ->
            IO.puts("  would resync #{dir}: #{Enum.map_join(changed, ",", &elem(&1, 0))}" <> notes_str(notes))
            :would_resync
        end
    end
  rescue
    e ->
      IO.puts("  ERROR #{dir}: #{Exception.message(e)}")
      :error
  end

  # ---------------- wt_: full refresh from the parent ----------------

  defp desired_wt(dir, tasks_dir) do
    parent = parent_dir(:wt, dir, tasks_dir)
    sol = File.read!(Path.join(parent, "solution.ex"))
    harness = File.read!(Path.join(parent, "test_harness.exs"))
    spec = File.read!(Path.join(parent, "prompt.md"))

    files = %{
      "solution.ex" => sol,
      "test_harness.exs" => harness,
      "prompt.md" => GenTask.WriteTest.prompt_md(sol, spec)
    }

    manifest = Path.join(parent, "manifest.exs")

    files =
      if File.regular?(manifest),
        do: Map.put(files, "manifest.exs", File.read!(manifest)),
        else: files

    {:ok, files, []}
  end

  # ---------------- module-FIM: rebuild the skeleton fence ----------------

  defp desired_fim(dir, tasks_dir) do
    parent = parent_dir(:fim, dir, tasks_dir)
    parent_raw = File.read!(Path.join(parent, "solution.ex"))
    gold = File.read!(Path.join(dir, "solution.ex"))
    prompt = File.read!(Path.join(dir, "prompt.md"))

    # The shipped embeds of bundle parents carry no <file> marker lines.
    parent_src =
      if EvalTask.Bundle.bundle?(parent_raw),
        do: strip_marker_lines(parent_raw),
        else: parent_raw

    with :ok <- exactly_one_todo_fence(prompt),
         {:ok, gold2, notes} <- locate_or_rewrap_gold(parent_src, gold) do
      skeleton = EvalTask.Fim.build_skeleton(parent_src, gold2)
      new_prompt = EvalTask.Fim.rewrite_skeleton(prompt, skeleton)
      {:ok, %{"prompt.md" => new_prompt, "solution.ex" => gold2}, notes}
    end
  end

  defp exactly_one_todo_fence(prompt) do
    n =
      Regex.scan(@fence, prompt, capture: :all_but_first)
      |> Enum.count(fn [body] -> String.match?(body, @todo) end)

    if n == 1, do: :ok, else: {:error, "#{n} TODO-bearing ```elixir fences (need exactly 1)"}
  end

  # The gold as build_skeleton needs it: verbatim-locatable in the parent. A gold
  # whose content matches only after whitespace normalization (the parent was
  # reformatted) is rewritten from the parent's current lines, re-based to the
  # gold's existing indentation.
  defp locate_or_rewrap_gold(parent_src, gold) do
    try do
      # Probe: build_skeleton raises iff the gold is not verbatim-locatable.
      EvalTask.Fim.build_skeleton(parent_src, gold)
      {:ok, gold, []}
    rescue
      _ ->
        pl = String.split(parent_src, "\n")
        gl = gold |> String.trim_trailing() |> String.split("\n")

        case normalized_span(pl, gl) do
          {s, e} ->
            span = Enum.slice(pl, s..e)
            {:ok, rebase_indent(span, gl) <> "\n", [:gold_rewritten]}

          nil ->
            {:error, "child gold not locatable in the parent (parent redesigned at target?)"}
        end
    end
  end

  # Shift the parent span so its first line's indent matches the old gold's first
  # line indent (most golds keep module-level indentation; some are dedented).
  defp rebase_indent(span, old_gold_lines) do
    span_indent = leading_ws(hd(span))
    gold_indent = old_gold_lines |> Enum.find(&(String.trim(&1) != "")) |> leading_ws()
    delta = String.length(gold_indent) - String.length(span_indent)

    cond do
      delta == 0 ->
        Enum.join(span, "\n")

      delta > 0 ->
        pad = String.duplicate(" ", delta)
        Enum.map_join(span, "\n", fn l -> if String.trim(l) == "", do: l, else: pad <> l end)

      true ->
        cut = -delta

        Enum.map_join(span, "\n", fn l ->
          ws = leading_ws(l)
          if String.length(ws) >= cut, do: String.slice(l, cut..-1//1), else: l
        end)
    end
  end

  defp leading_ws(line), do: Regex.run(~r/^\s*/, line) |> hd()

  # Contiguous parent run whose concatenated whitespace-stripped text equals the
  # gold's (mirrors check_embeds normalized_gold_span/2).
  defp normalized_span(pl, gl) do
    target = gl |> Enum.map(&String.replace(&1, ~r/\s+/, "")) |> Enum.join()
    pn = Enum.map(pl, &String.replace(&1, ~r/\s+/, ""))
    n = length(pn)

    if target == "" do
      nil
    else
      Enum.find_value(0..(n - 1)//1, fn i ->
        first = Enum.at(pn, i)

        if first != "" and String.starts_with?(target, first) do
          i..(n - 1)//1
          |> Enum.reduce_while("", fn j, acc ->
            acc2 = acc <> Enum.at(pn, j)

            cond do
              acc2 == target -> {:halt, {i, j}}
              String.starts_with?(target, acc2) -> {:cont, acc2}
              true -> {:halt, nil}
            end
          end)
          |> case do
            {s, e} -> {s, e}
            _ -> nil
          end
        end
      end)
    end
  end

  defp strip_marker_lines(src) do
    src
    |> String.split("\n")
    |> Enum.reject(&String.match?(String.trim(&1), @bundle_marker))
    |> Enum.join("\n")
  end

  defp parent_dir(:fim, dir, tasks_dir) do
    base = Path.basename(dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    Path.join(tasks_dir, parent)
  end

  defp parent_dir(:wt, dir, tasks_dir) do
    base = Path.basename(dir) |> String.replace_prefix("wt_", "")
    Path.join(tasks_dir, base <> "_01")
  end

  # ---------------- writes: backup + ledger ----------------

  defp write!(dir, changed, notes) do
    backup_dir = Path.join(@backup_root, Path.basename(dir))
    File.mkdir_p!(backup_dir)
    File.mkdir_p!(Path.dirname(@ledger))

    entry =
      for {name, content} <- changed, into: %{} do
        old = File.read!(Path.join(dir, name))
        File.write!(Path.join(backup_dir, name), old)
        File.write!(Path.join(dir, name), content)
        {name, %{before: sha(old), after: sha(content)}}
      end

    line =
      Jason.encode!(%{
        dir: dir,
        files: entry,
        notes: notes,
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    File.write!(@ledger, line <> "\n", [:append])
    IO.puts("  resynced #{dir}: #{Enum.map_join(changed, ",", &elem(&1, 0))}" <> notes_str(notes))
  end

  # A file the dir lacks entirely (manifest.exs) counts as changed.
  defp changed_files(dir, files) do
    for {name, content} <- files,
        File.read(Path.join(dir, name)) != {:ok, content},
        do: {name, content}
  end

  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower) |> binary_part(0, 12)

  defp notes_str([]), do: ""
  defp notes_str(notes), do: " [#{Enum.join(notes, ",")}]"

  # Another BEAM running the generation loop? (`pgrep -af generate.exs` also finds
  # wrapper shells; match beam.smp lines only, and never our own OS pid.)
  defp generate_loop_alive?() do
    case System.cmd("pgrep", ["-a", "beam.smp"], stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.any?(fn line ->
          [pid | _] = String.split(line, " ", parts: 2)
          pid != System.pid() and String.contains?(line, "generate.exs")
        end)

      _ ->
        false
    end
  end

  # ---------------- self-test: scratch copy, apply, verify CLEAN ----------------

  defp self_test(flagged_dir) do
    scratch = Path.join(System.tmp_dir!(), "resync_embeds_selftest_#{System.os_time(:millisecond)}")
    File.mkdir_p!(scratch)
    base = Path.basename(flagged_dir)
    kind = if String.starts_with?(base, "wt_"), do: :wt, else: :fim
    parent = parent_dir(kind, flagged_dir, Path.dirname(flagged_dir))

    copy = Path.join(scratch, base)
    File.cp_r!(flagged_dir, copy)
    File.cp_r!(parent, Path.join(scratch, Path.basename(parent)))
    IO.puts("self-test scratch: #{scratch}")

    case resync_in(copy, scratch) do
      :resynced ->
        {out, 0} =
          System.cmd("elixir", ["scripts/check_embeds.exs", "--tasks-dir", scratch, "--verbose"])

        verdict_line = out |> String.split("\n") |> Enum.find(&String.contains?(&1, base))

        if verdict_line && String.starts_with?(verdict_line, "CLEAN") do
          # Idempotence: a second resync must be a no-op.
          case resync_in(copy, scratch) do
            :unchanged -> IO.puts("self-test: PASS (resynced -> CLEAN, second run unchanged)")
            other -> IO.puts("self-test: FAIL (second run #{inspect(other)})") && System.halt(1)
          end
        else
          IO.puts("self-test: FAIL — verdict after resync: #{verdict_line || "(dir not in report)"}")
          IO.puts(out)
          System.halt(1)
        end

      other ->
        IO.puts("self-test: FAIL — resync returned #{inspect(other)}")
        System.halt(1)
    end
  end

  # Scratch-scoped resync: same logic, parent resolved inside `tasks_root`, always
  # applied, no ledger/backup (scratch only).
  defp resync_in(dir, tasks_root) do
    base = Path.basename(dir)

    desired =
      if String.starts_with?(base, "wt_"),
        do: desired_wt(dir, tasks_root),
        else: desired_fim(dir, tasks_root)

    case desired do
      {:error, why} ->
        IO.puts("  ERROR #{dir}: #{why}")
        :error

      {:ok, files, _notes} ->
        changed = changed_files(dir, files)

        if changed == [] do
          :unchanged
        else
          Enum.each(changed, fn {name, content} -> File.write!(Path.join(dir, name), content) end)
          :resynced
        end
    end
  end
end

ResyncEmbeds.main(System.argv())
