#!/usr/bin/env elixir
# check_embeds.exs — read-only embed-staleness checker for module-FIM (`<seed>_0N`,
# N >= 2) and `wt_` prompt embeds (docs/12 §5.1 item 8).
#
#   elixir scripts/check_embeds.exs [--only "021_001*"] [--tasks-dir tasks] [--verbose]
#   elixir scripts/check_embeds.exs --self-test [--scratch /some/tmp/dir]
#
# tfim_ embeds are covered by scripts/resync_tfim_embeds.exs (the S5 gate); repair_
# dirs have no parent-embed contract. Everything else that embeds a parent solution
# in its prompt is checked here:
#
#   * a module-FIM child embeds the ENTIRE parent `_01` solution in one ```elixir
#     fence with exactly one function blanked to a `# TODO` stub;
#   * a wt_ dir embeds the parent solution in one ```elixir fence, unmodified.
#
# The check diffs the embed against the CURRENT parent `solution.ex` line by line
# (`List.myers_difference/2`) and flags every difference EXCEPT these specific,
# named conventions:
#
#   (a) removed `@doc """ ... """` heredoc blocks — some historical embeds omit
#       docs that exist in the parent (e.g. the 001_004 family);
#   (e) removed one-line `@doc "..."` attributes — the same doc-omission
#       convention as (a) in its single-line spelling (e.g. the 002_00x
#       families); only a complete `@doc "…"` string on one line qualifies;
#   (b) the one blanked-function region of a module-FIM child — located as the
#       child's gold `solution.ex` matched into the parent (blank-line- and
#       indentation-agnostic contiguous match, mirroring
#       `EvalTask.Fim.build_skeleton/2`'s candidate locator; when the exact
#       line match fails because the formatter wraps the dedented gold
#       fragment differently than the module-nested original, a
#       whitespace-normalized contiguous match locates it instead and the
#       verdict carries a reflow-stale-gold note), plus the `# TODO`
#       stub lines the embed carries instead (`# TODO` marker, a bare `end`, and
#       a one-liner head converted `, do:` → ` do` — the exact forms
#       `EvalTask.Fim.signature_stub/3` emits);
#   (f) stub-head variants: historical embeds of MULTI-CLAUSE gold functions
#       carry one synthesized head whose argument names match no parent clause
#       (e.g. `defp bootstrap_ema(values, period) do` for a gold whose clauses
#       pattern-match `[]` / `[seed | rest]`). An extra-in-embed line is allowed
#       iff it is a `def`/`defp` block head (`… do`) whose function name equals
#       the child gold's own function name — module-FIM only, never wt_;
#   (c) leading/trailing blank lines at the fence edges;
#   (d) bundle parents only (`<file path=...>` bundles): module-FIM embeds strip
#       the `<file>`/`</file>` wrapper lines and may differ in blank lines at the
#       seams, so for those dirs marker lines are dropped from the parent and
#       blank-only diffs are ignored. (wt_ embeds keep the markers — no allowance.)
# One more verdict sits between clean and drift. When EVERY surviving diff line
# still pairs up — the deleted and inserted text are identical after removing
# all whitespace, the doctest continuation markers `iex>` / `...>`, and
# collapsing each `─` run in banner comments to a single character (rule g:
# `# ── Public API ──…──` re-ruled to a different width is formatting, not
# content) — the embed is byte-stale but content-identical: the 2026-07 corpus
# format canonicalization rewrapped the parent and the embed kept the old
# wrapping. That dir is verdict REFLOW, counted separately (it needs a resync,
# not an investigation).
#
# Anything else is DRIFT: extra functions/attributes the parent lacks (the
# 020_001 phantom `max_bytes/0` case), missing lines beyond @doc blocks and the
# blanked function, changed bodies.
#
# Verdicts: CLEAN / REFLOW (format-only staleness) / DRIFT (offending lines,
# capped at 10 per file, with parent-solution.ex / prompt.md line numbers) /
# SKIP (unreadable or mid-write dir, no fence — with the reason). The script is
# READ-ONLY over --tasks-dir and tolerates dirs appearing or half-written
# mid-scan (each dir is checked inside try/rescue; failures become SKIP). Exit
# status is 0 regardless of drift (report-only for now); grep the final summary
# line
#
#   embed check: N clean, R reflow, M drift, K skipped
#
# to gate it later, the same way CI greps the resync_tfim_embeds output.
#
# --self-test (positive control): copies one CLEAN module-FIM pair and one CLEAN
# wt_ pair into a scratch dir OUTSIDE tasks/ (default: a fresh dir under
# System.tmp_dir!/0; override with --scratch), plants a phantom line inside each
# copied prompt's embed fence, and asserts the checker reports DRIFT naming that
# line. Exits 1 if the control fails, 0 if it passes.
#
# Self-contained on purpose: it mirrors the few EvalTask.Fim/EvalTask.Bundle
# helpers it needs (fence selection, parent-dir naming, bundle detection) instead
# of loading _build beams, so it cannot be skewed by a stale or mid-rebuild
# _build while the generation loop runs. Each mirrored rule cites its source.

defmodule CheckEmbeds do
  @moduledoc false

  # Mirrors EvalTask.Fim @todo / @skeleton.
  @todo ~r/#\s*TODO/i
  @fence ~r/```elixir\n(.*?)\n```/s
  # `@doc` heredoc opener, on a trimmed line. Conservative (docs/12 §5.1 item 8
  # ignore rule a): the attribute line through the closing `"""` line only.
  @doc_open ~r/^@doc\s+~?[sS]?"""$/
  # Complete one-line `@doc "..."` attribute (ignore rule e): a plain string,
  # no embedded `"` — anything fancier stays flagged.
  @doc_oneline ~r/^@doc\s+"[^"]*"$/
  @bundle_marker ~r{^</?file( path=.*)?>$}
  @max_report 10

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          only: :string,
          tasks_dir: :string,
          verbose: :boolean,
          self_test: :boolean,
          scratch: :string
        ]
      )

    tasks_dir = opts[:tasks_dir] || "tasks"

    if opts[:self_test] do
      scratch =
        opts[:scratch] ||
          Path.join(System.tmp_dir!(), "check_embeds_selftest_#{System.os_time(:millisecond)}")

      self_test(tasks_dir, scratch)
    else
      run(tasks_dir, globs(opts[:only]), opts[:verbose] || false)
    end
  end

  # ------------------------------------------------------------------
  # Corpus run
  # ------------------------------------------------------------------

  defp run(tasks_dir, globs, verbose) do
    results =
      for {kind, dir} <- enumerate(tasks_dir, globs) do
        verdict = check_dir(kind, dir)
        print_verdict(kind, dir, verdict, verbose)
        {kind, verdict}
      end

    for k <- [:fim, :wt] do
      c = summarize(for {^k, v} <- results, do: v)

      IO.puts(
        "#{label(k)}: #{c.clean} clean, #{c.reflow} reflow, #{c.drift} drift, #{c.skip} skipped"
      )
    end

    t = summarize(for {_k, v} <- results, do: v)

    IO.puts(
      "embed check: #{t.clean} clean, #{t.reflow} reflow, #{t.drift} drift, #{t.skip} skipped"
    )
  end

  defp summarize(verdicts) do
    Enum.reduce(verdicts, %{clean: 0, reflow: 0, drift: 0, skip: 0}, fn v, acc ->
      key =
        case v do
          {:clean, _} -> :clean
          {:reflow, _, _} -> :reflow
          {:drift, _, _} -> :drift
          {:skip, _} -> :skip
        end

      Map.update!(acc, key, &(&1 + 1))
    end)
  end

  # Snapshot listing of tasks_dir. The generation loop may add dirs mid-scan; a
  # dir that appears after this listing is simply picked up by the next run, and
  # one that is half-written when we reach it fails its reads into a SKIP.
  defp enumerate(tasks_dir, globs) do
    case File.ls(tasks_dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.filter(fn base -> Enum.any?(globs, &match_glob?(base, &1)) end)
        |> Enum.flat_map(fn base ->
          dir = Path.join(tasks_dir, base)

          cond do
            String.starts_with?(base, "tfim_") -> []
            String.starts_with?(base, "repair_") -> []
            String.starts_with?(base, "wt_") -> [{:wt, dir}]
            fim_child_basename?(base) -> [{:fim, dir}]
            true -> []
          end
        end)

      {:error, e} ->
        IO.puts("cannot list #{tasks_dir}: #{:file.format_error(e)}")
        IO.puts("embed check: 0 clean, 0 drift, 0 skipped")
        []
    end
  end

  # A numeric `<a>_<b>_<slug>_0N` basename with N >= 2. Whether it really is a
  # module-FIM child is confirmed structurally in check_dir/2 (no harness of its
  # own, prompt has a `# TODO` fence — mirrors EvalTask.Fim.fim_dir?/1).
  defp fim_child_basename?(base) do
    String.match?(base, ~r/^\d/) and
      case base |> String.split("_") |> List.last() |> Integer.parse() do
        {n, ""} -> n >= 2
        _ -> false
      end
  end

  # ------------------------------------------------------------------
  # Per-directory check
  # ------------------------------------------------------------------

  # Returns {:clean, notes} | {:drift, violations, notes} | {:skip, reason}.
  # Every read failure or exception (a dir being written mid-scan) is a SKIP,
  # never a crash — the scan must survive the live generation loop.
  def check_dir(kind, dir) do
    if kind == :fim and File.regular?(Path.join(dir, "test_harness.exs")) do
      {:skip, "has its own test_harness.exs — not a module-FIM child"}
    else
      with {:ok, prompt} <- read(dir, "prompt.md"),
           {:ok, embed, fence_line} <- extract_embed(kind, prompt),
           {:ok, parent_src} <- read(parent_dir(kind, dir), "solution.ex"),
           {:ok, gold} <- read_gold(kind, dir) do
        compare(kind, parent_src, embed, fence_line, gold)
      end
    end
  rescue
    e -> {:skip, "unreadable (mid-write?): #{Exception.message(e)}"}
  end

  defp read(dir, name) do
    path = Path.join(dir, name)

    case File.read(path) do
      {:ok, s} -> {:ok, s}
      {:error, e} -> {:skip, "cannot read #{path}: #{:file.format_error(e)}"}
    end
  end

  defp read_gold(:wt, _dir), do: {:ok, nil}
  defp read_gold(:fim, dir), do: read(dir, "solution.ex")

  # Parent `_01` dir. :fim mirrors EvalTask.Fim.parent_dir/1 (drop the `_0N`
  # segment, append `_01`); :wt strips the `wt_` prefix and appends `_01`
  # (inverse of GenTask.WriteTest.wt_id/1).
  def parent_dir(:fim, dir) do
    base = Path.basename(dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    Path.join(Path.dirname(dir), parent)
  end

  def parent_dir(:wt, dir) do
    base = Path.basename(dir) |> String.replace_prefix("wt_", "")
    Path.join(Path.dirname(dir), base <> "_01")
  end

  # The embed fence, plus the 1-based prompt.md line number of its first body
  # line. :fim takes the LAST `# TODO`-bearing ```elixir fence (exactly
  # EvalTask.Fim.extract_skeleton/1's selection); :wt takes the last ```elixir
  # fence (GenTask.WriteTest.prompt_md/2 places the module fence last).
  defp extract_embed(kind, prompt) do
    fences =
      for [_whole, {bs, bl}] <- Regex.scan(@fence, prompt, return: :index) do
        {binary_part(prompt, bs, bl), line_of(prompt, bs)}
      end

    chosen =
      case kind do
        :fim -> fences |> Enum.filter(fn {b, _} -> String.match?(b, @todo) end) |> List.last()
        :wt -> List.last(fences)
      end

    case chosen do
      nil when kind == :fim -> {:skip, "no ```elixir fence with a `# TODO` marker"}
      nil -> {:skip, "no ```elixir fence"}
      {body, line} -> {:ok, body, line}
    end
  end

  defp line_of(bin, byte_off),
    do: 1 + length(:binary.matches(binary_part(bin, 0, byte_off), "\n"))

  # ------------------------------------------------------------------
  # The diff and its ignore rules
  # ------------------------------------------------------------------

  defp compare(kind, parent_src, embed, fence_line, gold) do
    # Mirrors EvalTask.Bundle.bundle?/1.
    bundle_fim? = kind == :fim and String.contains?(parent_src, "<file path=")

    {plines, pnums} = prep_side(parent_src, 1, drop_markers: bundle_fim?)
    {elines, enums} = prep_side(embed, fence_line, drop_markers: false)

    gold_lines = if gold, do: String.split(gold, "\n"), else: []
    {gold_idx, gold_note} = gold_indices(kind, plines, gold_lines)
    gold_trimmed = gold_lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    ctx = %{
      kind: kind,
      bundle_fim?: bundle_fim?,
      doc_idx: doc_block_indices(plines),
      gold_idx: gold_idx,
      gold_trimmed: gold_trimmed,
      gold_fn_names: gold_fn_names(gold_trimmed)
    }

    viols =
      List.myers_difference(plines, elines)
      |> walk(0, 0, ctx, [])
      |> Enum.map(fn
        {:del, i, text} -> {:del, Enum.at(pnums, i), text}
        {:ins, j, text} -> {:ins, Enum.at(enums, j), text}
      end)

    notes = if gold_note, do: [gold_note], else: []

    cond do
      viols == [] -> {:clean, notes}
      reflow_only?(viols) -> {:reflow, viols, notes}
      true -> {:drift, viols, notes}
    end
  end

  # Function names defined by the child's gold clauses (for ignore rule f).
  defp gold_fn_names(gold_trimmed) do
    for l <- gold_trimmed,
        m = Regex.run(~r/^defp?\s+([a-zA-Z_][a-zA-Z0-9_]*[?!]?)/, l),
        into: MapSet.new(),
        do: Enum.at(m, 1)
  end

  # Verdict REFLOW: every surviving del/ins still pairs up — the deleted and
  # inserted text are identical once all whitespace and the doctest
  # continuation markers `iex>` / `...>` are removed and each `─` banner run
  # is collapsed to one char (rule g: banner rule width is formatting). The
  # 2026-07 format canonicalization rewrapped the parent; the embed kept the
  # old wrapping.
  defp reflow_only?(viols) do
    join = fn side ->
      viols
      |> Enum.filter(&(elem(&1, 0) == side))
      |> Enum.map_join(fn {_, _, text} ->
        text
        |> String.replace(["iex>", "...>"], "")
        |> String.replace(~r/─+/u, "─")
        |> String.replace(~r/\s+/, "")
      end)
    end

    join.(:del) == join.(:ins)
  end

  # One side of the diff: split into lines, drop bundle `<file>`/`</file>`
  # marker lines when asked (ignore rule d), trim blank edge lines (ignore
  # rule c). Returns the line texts plus a parallel list of original 1-based
  # line numbers (`start` is the file line of the first split line).
  defp prep_side(src, start, drop_markers: drop?) do
    src
    |> String.split("\n")
    |> Enum.with_index(start)
    |> then(fn pairs ->
      if drop?,
        do: Enum.reject(pairs, fn {l, _} -> String.match?(String.trim(l), @bundle_marker) end),
        else: pairs
    end)
    |> trim_blank_edges()
    |> Enum.unzip()
  end

  defp trim_blank_edges(pairs) do
    blank? = fn {l, _} -> String.trim(l) == "" end

    pairs
    |> Enum.drop_while(blank?)
    |> Enum.reverse()
    |> Enum.drop_while(blank?)
    |> Enum.reverse()
  end

  # Locate the child's gold function in the parent: contiguous run of the gold's
  # trimmed non-blank lines (blank- and indentation-agnostic — the gold is
  # dedented in most children). Mirrors EvalTask.Fim.find_candidate_block/2.
  # Returns {MapSet of parent diff-indices, note-or-nil}; an unlocatable gold
  # yields an empty set, so the blanked-region dels get flagged — the parent has
  # drifted at the target function itself, which IS drift for the training pair.
  defp gold_indices(:wt, _plines, _gold), do: {MapSet.new(), nil}

  defp gold_indices(:fim, plines, gold_lines) do
    cand = gold_lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    pt = Enum.map(plines, &String.trim/1)
    n = length(pt)

    start =
      cand != [] and
        Enum.find(0..(n - 1)//1, fn i ->
          Enum.at(pt, i) == hd(cand) and
            pt |> Enum.drop(i) |> Enum.reject(&(&1 == "")) |> Enum.take(length(cand)) == cand
        end)

    case start do
      s when is_integer(s) ->
        {e, _} =
          Enum.reduce_while(s..(n - 1)//1, {s, 0}, fn i, {_last, c} ->
            c2 = if Enum.at(pt, i) == "", do: c, else: c + 1
            if c2 >= length(cand), do: {:halt, {i, c2}}, else: {:cont, {i, c2}}
          end)

        {MapSet.new(s..e), nil}

      _ ->
        # The formatter wraps a dedented fragment differently than the same
        # code nested in the module, so the child gold's LINES may not match
        # the parent's even though the content does. Fall back to locating the
        # gold as a contiguous parent span with identical whitespace-stripped
        # content (line boundaries ignored).
        case normalized_gold_span(pt, normjoin(cand)) do
          {s, e} ->
            {MapSet.new(s..e),
             "gold located by whitespace-normalized match " <>
               "(child gold wrapping differs from parent — reflow-stale gold)"}

          nil ->
            {MapSet.new(), "child gold not located in the parent (parent drifted at the target?)"}
        end
    end
  end

  defp normjoin(lines), do: lines |> Enum.join() |> String.replace(~r/\s+/, "")

  # Contiguous run of parent lines whose concatenated whitespace-stripped text
  # equals `target`. Returns {start, end} inclusive or nil.
  defp normalized_gold_span(pt, target) when target != "" do
    pn = Enum.map(pt, &String.replace(&1, ~r/\s+/, ""))
    n = length(pn)

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

  defp normalized_gold_span(_pt, _target), do: nil

  # Parent diff-indices lying inside `@doc """ ... """` heredoc blocks (ignore
  # rule a): the attribute line through the next line that is exactly `"""` —
  # plus complete one-line `@doc "..."` attributes (ignore rule e).
  defp doc_block_indices(plines) do
    {set, _} =
      plines
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), false}, fn {l, i}, {set, in_doc?} ->
        t = String.trim(l)

        cond do
          in_doc? -> {MapSet.put(set, i), t != ~s(""")}
          String.match?(t, @doc_open) -> {MapSet.put(set, i), true}
          String.match?(t, @doc_oneline) -> {MapSet.put(set, i), false}
          true -> {set, false}
        end
      end)

    set
  end

  # Walk the myers script tracking the parent (pi) and embed (ei) diff-indices;
  # collect the lines no ignore rule covers.
  defp walk([], _pi, _ei, _ctx, acc), do: Enum.reverse(acc)

  defp walk([{:eq, lines} | rest], pi, ei, ctx, acc) do
    n = length(lines)
    walk(rest, pi + n, ei + n, ctx, acc)
  end

  defp walk([{:del, lines} | rest], pi, ei, ctx, acc) do
    acc =
      lines
      |> Enum.with_index(pi)
      |> Enum.reduce(acc, fn {line, i}, acc ->
        if del_allowed?(line, i, ctx), do: acc, else: [{:del, i, line} | acc]
      end)

    walk(rest, pi + length(lines), ei, ctx, acc)
  end

  defp walk([{:ins, lines} | rest], pi, ei, ctx, acc) do
    acc =
      lines
      |> Enum.with_index(ei)
      |> Enum.reduce(acc, fn {line, j}, acc ->
        if ins_allowed?(line, ctx), do: acc, else: [{:ins, j, line} | acc]
      end)

    walk(rest, pi, ei + length(lines), ctx, acc)
  end

  # A parent line missing from the embed is fine only when it sits in a removed
  # @doc heredoc (rule a), in the blanked gold-function region (rule b), or is a
  # blank line at a bundle seam (rule d).
  defp del_allowed?(line, i, ctx) do
    MapSet.member?(ctx.doc_idx, i) or
      MapSet.member?(ctx.gold_idx, i) or
      (ctx.bundle_fim? and String.trim(line) == "")
  end

  # An embed line the parent lacks is fine only when it is part of the # TODO
  # stub of a module-FIM hole (rule b): the marker itself, the stub's bare
  # `end`, a one-liner gold head converted `, do: ...` → ` do` — exactly the
  # forms EvalTask.Fim.signature_stub/3 emits — or a historical synthesized
  # head for the gold's own function (rule f). Bundle seams may add blank lines
  # (rule d). Everything else — a phantom function, attribute, or changed body —
  # is drift.
  defp ins_allowed?(line, ctx) do
    t = String.trim(line)

    cond do
      ctx.bundle_fim? and t == "" -> true
      ctx.kind != :fim -> false
      String.match?(t, @todo) -> true
      t == "end" -> true
      oneliner_stub_head?(t, ctx.gold_trimmed) -> true
      stub_head_variant?(t, ctx.gold_fn_names) -> true
      true -> false
    end
  end

  # Rule f: a `def`/`defp` block head (`… do`, never `, do:`) whose function
  # name is the child gold's own — historical embeds of multi-clause golds
  # carry one synthesized head whose argument names match no parent clause.
  defp stub_head_variant?(t, gold_fn_names) do
    case Regex.run(~r/^defp?\s+([a-zA-Z_][a-zA-Z0-9_]*[?!]?)\s*(\(.*\))?(\s+when\s+.*)?\s+do$/, t) do
      [_ | [name | _]] -> MapSet.member?(gold_fn_names, name)
      _ -> false
    end
  end

  defp oneliner_stub_head?(t, gold_trimmed) do
    String.ends_with?(t, " do") and
      Enum.any?(gold_trimmed, fn g ->
        g != t and Regex.match?(~r/,\s*do:/, g) and
          String.replace(g, ~r/,\s*do:.*$/, " do") == t
      end)
  end

  # ------------------------------------------------------------------
  # Reporting
  # ------------------------------------------------------------------

  defp print_verdict(kind, dir, verdict, verbose) do
    case verdict do
      {:clean, notes} ->
        if verbose, do: IO.puts("CLEAN #{dir}")
        Enum.each(notes, &IO.puts("    note: #{&1}"))

      {:skip, reason} ->
        IO.puts("SKIP  #{dir}: #{reason}")

      {:reflow, viols, notes} ->
        IO.puts(
          "REFLOW #{dir} (#{label(kind)}; parent #{parent_dir(kind, dir)}): " <>
            "#{length(viols)} rewrapped line(s) — content identical, needs resync only"
        )

        Enum.each(notes, &IO.puts("    note: #{&1}"))

      {:drift, viols, notes} ->
        IO.puts("DRIFT #{dir} (#{label(kind)}; parent #{parent_dir(kind, dir)})")
        Enum.each(notes, &IO.puts("    note: #{&1}"))

        shown = Enum.take(viols, @max_report)

        Enum.each(shown, fn
          {:del, n, text} ->
            IO.puts(
              "    - missing from embed  #{parent_dir(kind, dir)}/solution.ex:#{n}: #{text}"
            )

          {:ins, n, text} ->
            IO.puts("    - extra in embed      #{dir}/prompt.md:#{n}: #{text}")
        end)

        hidden = length(viols) - length(shown)
        if hidden > 0, do: IO.puts("    ... #{hidden} more line(s) not shown")
    end
  end

  defp label(:fim), do: "module-FIM"
  defp label(:wt), do: "wt_"

  defp globs(nil), do: ["*"]
  defp globs(s), do: String.split(s, ",", trim: true)

  # Mirrors scripts/resync_tfim_embeds.exs match_glob?/2.
  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # ------------------------------------------------------------------
  # Positive control (--self-test): never touches tasks/ — copies one clean
  # pair per kind into `scratch`, plants a phantom line in the copy's embed
  # fence, and asserts the checker flags exactly that.
  # ------------------------------------------------------------------

  @phantom "  def phantom_fn_never_in_gold, do: :planted_drift"

  defp self_test(tasks_dir, scratch) do
    File.mkdir_p!(scratch)
    IO.puts("self-test scratch dir: #{scratch}")

    results =
      for kind <- [:fim, :wt] do
        case find_clean(kind, tasks_dir) do
          nil ->
            IO.puts("FAIL  #{label(kind)}: no CLEAN source dir found to build the control from")
            false

          dir ->
            control(kind, dir, scratch)
        end
      end

    if Enum.all?(results) do
      IO.puts("self-test: PASS (both planted phantoms flagged as DRIFT)")
    else
      IO.puts("self-test: FAIL")
      System.halt(1)
    end
  end

  defp find_clean(kind, tasks_dir) do
    enumerate(tasks_dir, ["*"])
    |> Enum.find_value(fn
      {^kind, dir} -> match?({:clean, _}, check_dir(kind, dir)) && dir
      _ -> nil
    end)
  end

  defp control(kind, dir, scratch) do
    copy = Path.join(scratch, Path.basename(dir))
    parent_copy = Path.join(scratch, Path.basename(parent_dir(kind, dir)))
    File.cp_r!(dir, copy)
    File.cp_r!(parent_dir(kind, dir), parent_copy)
    plant_phantom!(kind, Path.join(copy, "prompt.md"))

    case check_dir(kind, copy) do
      {:drift, viols, _} ->
        if Enum.any?(viols, fn {_, _, text} -> text =~ "phantom_fn_never_in_gold" end) do
          IO.puts("ok    #{label(kind)}: planted phantom in #{copy} flagged as DRIFT")
          true
        else
          IO.puts("FAIL  #{label(kind)}: DRIFT reported but the phantom line is not among:")
          print_verdict(kind, copy, {:drift, viols, []}, false)
          false
        end

      other ->
        IO.puts("FAIL  #{label(kind)}: expected DRIFT on #{copy}, got #{inspect(other)}")
        false
    end
  end

  # Insert the phantom line just before the last `end` of the embed fence body
  # (inside the module), rewriting only the scratch copy.
  defp plant_phantom!(kind, prompt_path) do
    prompt = File.read!(prompt_path)
    {:ok, body, _line} = extract_embed(kind, prompt)

    lines = String.split(body, "\n")

    last_end =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {l, _} -> String.trim(l) == "end" end)
      |> List.last()

    new_body =
      case last_end do
        {_l, i} -> lines |> List.insert_at(i, @phantom) |> Enum.join("\n")
        nil -> body <> "\n" <> @phantom
      end

    File.write!(prompt_path, String.replace(prompt, body, new_body))
  end
end

CheckEmbeds.main(System.argv())
