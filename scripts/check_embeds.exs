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
#       blank-only diffs are ignored. When a wt_ parent IS a bundle the embed
#       keeps the markers and they match — no allowance needed; when a wt_
#       parent is NOT a bundle, the wt_ generator still wraps the module in a
#       single-file `<file path=...>` tag, so those wrapper lines are dropped
#       from the EMBED side (the wrapped content is still diffed in full);
#   NOT a convention — deliberately absent: removed `@spec` attributes. The
#       089_002/089_003/089_004 embeds lack @spec lines their parents carry,
#       which looks like an (a)/(e)-style omission convention but is real
#       post-mint drift: git shows all three parents gained @doc+@spec in
#       cff116d3 (2026-07-07) AFTER the children were minted (737f3806,
#       2026-07-02), and 4k+ embeds repo-wide DO retain @spec. Missing @spec
#       stays DRIFT (remediation: resync);
#   (j) synthesized stub scaffold comments (module-FIM only): an extra `#`
#       comment whose contiguous embed comment block contains the `# TODO`
#       marker (a TODO comment wrapped over continuation lines — 037_004) or
#       sits directly above a recognized stub head (the descriptor comment
#       the generator emits with synthesized multi-clause heads — 061_001,
#       087_001); comment blocks anywhere else stay flagged;
#   (k) gold-seam alias lines (module-FIM only): a deleted parent line that is
#       blank or exactly `@impl true` and contiguous with the blanked-gold span
#       — collapsing an N-clause gold to one stub makes myers alias the stub's
#       trailing `end`/blank/`@impl true` onto an interior clause boundary and
#       push these seam lines out as phantom deletions even though the embed
#       carries them verbatim (011_001_04, 023_001_04, 104_001_03, 104_002_04,
#       106_001_03, and the blank-only dels of 037_004_04/041_001_03/087_001_03).
# One more verdict sits between clean and drift. When EVERY surviving diff line
# still pairs up — the deleted and inserted text are identical after removing
# all whitespace, the doctest continuation markers `iex>` / `...>`, and
# collapsing each `─` run in banner comments to a single character (rule g:
# `# ── Public API ──…──` re-ruled to a different width is formatting, not
# content) — the embed is byte-stale but content-identical: the 2026-07 corpus
# format canonicalization rewrapped the parent and the embed kept the old
# wrapping. That dir is verdict REFLOW, counted separately (it needs a resync,
# not an investigation). Three refinements of that pairing:
#
#   (i) markdown-table separator rows (`|---|----|`) collapse each `-` run to
#       one dash before comparing — re-aligning a @moduledoc table's column
#       widths changes dash counts, which is formatting, not content
#       (041_001); content rows are already covered by whitespace removal;
#   (m) the stub-end allowance in (b) swallows an INSERTED bare `end` that was
#       actually the reflowed copy of a re-indented parent `end`, leaving the
#       deletion unpaired; a del-join that equals the ins-join plus exactly one
#       trailing `end` when such an insert was swallowed is still a reflow
#       (103_004_02/03/04);
#   (l) wt_ only, last resort before DRIFT: if the embed and the parent parse
#       to the identical AST (line/column metadata stripped) with identical
#       comment text (whitespace + banner-run normalized), the difference is
#       formatter variance by construction (optional DSL parens, hand
#       alignment, line wrapping — wt_016_001, wt_102_001) and the verdict is
#       REFLOW. Any real code change, edited doc heredoc, or edited comment
#       fails the test. Module-FIM embeds contain a stub hole and can never
#       AST-match, so the fallback is not attempted for them.
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
  # The closing ``` may be indented: a return-shape example fence nested in a
  # Markdown list (`  ```elixir … \n  ````) must close at its own indented
  # delimiter instead of swallowing prose up to — and the opening backticks
  # of — the real module fence (the wt_036 false-drift family).
  @fence ~r/```elixir[ \t]*\n(.*?)\n[ \t]*```/s
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
    parent_bundle? = String.contains?(parent_src, "<file path=")
    bundle_fim? = kind == :fim and parent_bundle?
    # Rule d, wt_ side: a non-bundle parent gets a single-file <file> wrapper
    # from the wt_ generator; drop the wrapper lines from the embed only.
    wt_wrapped? = kind == :wt and not parent_bundle?

    {plines, pnums} = prep_side(parent_src, 1, drop_markers: bundle_fim?)
    {elines, enums} = prep_side(embed, fence_line, drop_markers: wt_wrapped?)

    gold_lines = if gold, do: String.split(gold, "\n"), else: []
    {gold_idx, gold_note} = gold_indices(kind, plines, gold_lines)
    gold_trimmed = gold_lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    ctx = %{
      kind: kind,
      bundle_fim?: bundle_fim?,
      doc_idx: doc_block_indices(plines),
      gold_idx: extend_gold_seam(gold_idx, plines),
      gold_trimmed: gold_trimmed,
      gold_fn_names: gold_fn_names(gold_trimmed),
      elines_trimmed: Enum.map(elines, &String.trim/1)
    }

    {raw_viols, swallowed_ends} =
      List.myers_difference(plines, elines)
      |> walk(0, 0, ctx, {[], 0})

    viols =
      Enum.map(raw_viols, fn
        {:del, i, text} -> {:del, Enum.at(pnums, i), text}
        {:ins, j, text} -> {:ins, Enum.at(enums, j), text}
      end)

    notes = if gold_note, do: [gold_note], else: []

    cond do
      viols == [] ->
        {:clean, notes}

      reflow_only?(viols, swallowed_ends) ->
        {:reflow, viols, notes}

      kind == :wt and ast_reflow?(parent_src, embed) ->
        {:reflow, viols,
         ["formatter-only variance: AST and comment text identical (rule l)" | notes]}

      true ->
        {:drift, viols, notes}
    end
  end

  # Rule (k): extend the blanked-gold span over the contiguous run of blank /
  # `@impl true` lines that trail it. Collapsing an N-clause gold to a single
  # stub lets myers alias the stub's trailing `end`/blank/`@impl true` onto an
  # interior clause boundary, pushing these seam lines out as phantom
  # deletions even though the embed carries them verbatim. Bounded to
  # metadata-only lines — the first content line ends the run.
  defp extend_gold_seam(gold_idx, plines) do
    if MapSet.size(gold_idx) == 0 do
      gold_idx
    else
      mx = Enum.max(gold_idx)

      plines
      |> Enum.drop(mx + 1)
      |> Enum.with_index(mx + 1)
      |> Enum.take_while(fn {l, _} -> String.trim(l) in ["", "@impl true"] end)
      |> Enum.reduce(gold_idx, fn {_, i}, set -> MapSet.put(set, i) end)
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
  # continuation markers `iex>` / `...>` are removed, each `─` banner run
  # is collapsed to one char (rule g: banner rule width is formatting), and
  # `-` runs in pure markdown-table separator rows are collapsed to one dash
  # (rule i: table column width is formatting). The 2026-07 format
  # canonicalization rewrapped the parent; the embed kept the old wrapping.
  #
  # Rule (m): when ins_allowed? swallowed a bare `end` insert that was really
  # the reflowed copy of a re-indented parent `end` (not the stub's own), the
  # del side carries exactly one unpaired trailing `end` — still a reflow.
  defp reflow_only?(viols, swallowed_ends) do
    join = fn side ->
      viols
      |> Enum.filter(&(elem(&1, 0) == side))
      |> Enum.map_join(fn {_, _, text} ->
        text
        |> String.replace(["iex>", "...>"], "")
        |> String.replace(~r/─+/u, "─")
        |> table_sep_collapse()
        |> String.replace(~r/\s+/, "")
      end)
    end

    d = join.(:del)
    i = join.(:ins)
    d == i or (swallowed_ends > 0 and d == i <> "end")
  end

  # Rule (i): a row whose cells are only `-`/`:` runs is a markdown-table
  # separator; its dash counts encode column alignment width, not content.
  defp table_sep_collapse(text) do
    if String.match?(String.trim(text), ~r/^\|[\s\-:|]+\|$/) and String.contains?(text, "-"),
      do: String.replace(text, ~r/-+/, "-"),
      else: text
  end

  # Rule (l), wt_ only: identical AST (metadata stripped) + identical comment
  # text (whitespace and `─`/`-` banner runs normalized) means the two sides
  # differ only by formatter variance — optional parens on DSL macros, hand
  # alignment, line wrapping. Any code change, edited doc heredoc (a literal
  # in the AST), or edited comment text fails this test. Bundle wrapper lines
  # are stripped from both sides first; a multi-module bundle parses as one
  # top-level block on both sides alike.
  defp ast_reflow?(parent_src, embed) do
    with {:ok, pq, pc} <- quoted_with_comments(strip_marker_lines(parent_src)),
         {:ok, eq, ec} <- quoted_with_comments(strip_marker_lines(embed)) do
      strip_meta(pq) == strip_meta(eq) and norm_comments(pc) == norm_comments(ec)
    else
      _ -> false
    end
  end

  defp quoted_with_comments(src) do
    case Code.string_to_quoted_with_comments(src) do
      {:ok, quoted, comments} -> {:ok, quoted, comments}
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  defp strip_marker_lines(src) do
    src
    |> String.split("\n")
    |> Enum.reject(&String.match?(String.trim(&1), @bundle_marker))
    |> Enum.join("\n")
  end

  defp strip_meta(quoted) do
    Macro.prewalk(quoted, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end

  defp norm_comments(comments) do
    Enum.map(comments, fn %{text: t} ->
      t
      |> String.replace(~r/[─-]{2,}/u, "─")
      |> String.replace(~r/\s+/, "")
    end)
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
  # collect the lines no ignore rule covers, plus the count of bare `end`
  # inserts the stub allowance swallowed (input to reflow rule m).
  defp walk([], _pi, _ei, _ctx, {acc, ends}), do: {Enum.reverse(acc), ends}

  defp walk([{:eq, lines} | rest], pi, ei, ctx, acc) do
    n = length(lines)
    walk(rest, pi + n, ei + n, ctx, acc)
  end

  defp walk([{:del, lines} | rest], pi, ei, ctx, {acc, ends}) do
    acc =
      lines
      |> Enum.with_index(pi)
      |> Enum.reduce(acc, fn {line, i}, acc ->
        if del_allowed?(line, i, ctx), do: acc, else: [{:del, i, line} | acc]
      end)

    walk(rest, pi + length(lines), ei, ctx, {acc, ends})
  end

  defp walk([{:ins, lines} | rest], pi, ei, ctx, {acc, ends}) do
    {acc, ends} =
      lines
      |> Enum.with_index(ei)
      |> Enum.reduce({acc, ends}, fn {line, j}, {acc, ends} ->
        cond do
          not ins_allowed?(line, j, ctx) -> {[{:ins, j, line} | acc], ends}
          String.trim(line) == "end" -> {acc, ends + 1}
          true -> {acc, ends}
        end
      end)

    walk(rest, pi, ei + length(lines), ctx, {acc, ends})
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
  # forms EvalTask.Fim.signature_stub/3 emits — a historical synthesized
  # head for the gold's own function (rule f), or a stub scaffold comment
  # (rule j). Bundle seams may add blank lines (rule d). Everything else — a
  # phantom function, attribute, or changed body — is drift.
  defp ins_allowed?(line, j, ctx) do
    t = String.trim(line)

    cond do
      ctx.bundle_fim? and t == "" -> true
      ctx.kind != :fim -> false
      String.match?(t, @todo) -> true
      t == "end" -> true
      t == "" -> seam_blank?(j, ctx)
      String.starts_with?(t, "#") -> stub_scaffold_comment?(j, ctx)
      oneliner_stub_head?(t, ctx.gold_trimmed) -> true
      cont_stub_line?(t, ctx.gold_trimmed) -> true
      stub_head_variant?(t, ctx.gold_fn_names) -> true
      true -> false
    end
  end

  # Rule (k): EvalTask.Fim.build_skeleton's seam repair (2026-07-19) inserts
  # ONE blank line inside the hole when the carve glued the stub against a
  # neighboring definition (the corpus format gate mandates the separation).
  # A blank insert is stub material exactly when it sits directly above the
  # stub's head or directly below the stub's `end`, with the `# TODO` marker
  # in reach — anywhere else a blank insert stays a violation.
  defp seam_blank?(j, ctx) do
    lines = ctx.elines_trimmed
    at = &Enum.at(lines, &1, "")
    todo_near? = fn range -> Enum.any?(range, &String.match?(at.(&1), @todo)) end

    head_like? =
      stub_head_variant?(at.(j + 1), ctx.gold_fn_names) or
        oneliner_stub_head?(at.(j + 1), ctx.gold_trimmed) or
        cont_stub_line?(at.(j + 1), ctx.gold_trimmed)

    (head_like? and todo_near?.((j + 2)..(j + 4))) or
      (at.(j - 1) == "end" and todo_near?.((j - 4)..(j - 2)))
  end

  # Rule b, continuation-one-liner spelling: EvalTask.Fim.signature_stub converts a
  # multi-line head whose `do:` sits alone on the next line by turning the head's
  # trailing comma into ` do` — so the stub carries a line that equals a gold line
  # with `,` → ` do` (e.g. `when is_atom(event) and is_atom(from) do`).
  defp cont_stub_line?(t, gold_trimmed) do
    String.ends_with?(t, " do") and
      String.replace_suffix(t, " do", ",") in gold_trimmed
  end

  # Rule (j): a `#` comment is stub scaffold when its contiguous comment block
  # in the embed either contains the `# TODO` marker (a TODO comment wrapped
  # over continuation lines — 037_004_04) or sits directly above a recognized
  # stub head (the descriptor comment the generator emits with synthesized
  # multi-clause heads — 061_001_02, 087_001_03). A comment block anywhere
  # else in the embed stays flagged.
  defp stub_scaffold_comment?(j, ctx) do
    lines = ctx.elines_trimmed
    comment? = fn i -> String.starts_with?(Enum.at(lines, i, ""), "#") end

    first = j |> Stream.iterate(&(&1 - 1)) |> Enum.find(fn i -> i == 0 or not comment?.(i - 1) end)
    last = j |> Stream.iterate(&(&1 + 1)) |> Enum.find(fn i -> not comment?.(i + 1) end)
    block = Enum.slice(lines, first..last)
    next = Enum.at(lines, last + 1, "")

    Enum.any?(block, &String.match?(&1, @todo)) or
      stub_head_variant?(next, ctx.gold_fn_names) or
      oneliner_stub_head?(next, ctx.gold_trimmed)
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
