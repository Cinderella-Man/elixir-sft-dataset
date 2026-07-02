#!/usr/bin/env elixir
# dataset_stats.exs — a summary of the Elixir SFT dataset for training planning.
#
#   mix run scripts/dataset_stats.exs                 # pretty report
#   mix run scripts/dataset_stats.exs --json          # machine-readable
#   mix run scripts/dataset_stats.exs --chars-per-token 3.6   # tune the token estimate
#
# Token counts are ESTIMATES (chars / chars-per-token, default 4.0) — this repo has no
# tokenizer dependency. Raw chars/bytes/words/lines are reported too, so you can apply
# your model's own ratio. Shapes come from EvalTask.Discovery (same as run_all/validate).

# Belt-and-suspenders for a bare `elixir` launch; a no-op under `mix run`.
for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern),
    do: Code.prepend_path(path)

defmodule DatasetStats do
  @moduledoc false
  alias EvalTask.{Bundle, Discovery}

  @ctx_windows [2048, 4096, 8192, 16_384]
  @otp_markers [
    {"GenServer", ~r/\buse GenServer\b/},
    {"Supervisor", ~r/\buse Supervisor\b|\buse DynamicSupervisor\b/},
    {"Agent", ~r/\buse Agent\b/},
    {"GenStage/Task", ~r/\buse GenStage\b|\bTask\.async\b|\bTask\.Supervisor\b/},
    {"gen_statem", ~r/:gen_statem/},
    {"ETS", ~r/:ets\.new|:ets\.insert/},
    {"Phoenix", ~r/\buse Phoenix\b/},
    {"Ecto", ~r/\buse Ecto\.Schema\b|Ecto\.Migration/}
  ]

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [json: :boolean, chars_per_token: :float])

    cpt = opts[:chars_per_token] || 4.0
    rows = Discovery.all() |> Enum.map(&row(&1, cpt))
    stats = compute(rows, cpt)

    if opts[:json], do: IO.puts(Jason.encode!(stats)), else: render(stats)
  end

  # ---------------------------------------------------------------- per-task row

  defp row(t, cpt) do
    prompt = read(Path.join(t.dir, "prompt.md"))
    sol = if t.found, do: read(t.solution), else: ""
    harness = read(Path.join(t.dir, "test_harness.exs"))
    {idea, variant, subtask} = parse_name(t.name)

    %{
      name: t.name,
      shape: t.shape,
      found: t.found,
      idea: idea,
      variant: variant,
      subtask: subtask,
      base?: variant == 1 and subtask == 1,
      variation?: variant > 1 and subtask == 1,
      fim?: subtask > 1,
      has_harness?: harness != "",
      prompt: measure(prompt, cpt),
      sol: measure(sol, cpt),
      harness: measure(harness, cpt),
      bundle_files: if(t.shape == :multifile and t.found, do: bundle_count(sol), else: 1),
      bundle_kinds: if(t.shape == :multifile and t.found, do: bundle_kinds(sol), else: []),
      otp: for({label, re} <- @otp_markers, Regex.match?(re, sol), do: label),
      moduledoc?: String.contains?(sol, "@moduledoc"),
      spec?: Regex.match?(~r/@spec\s/, sol),
      doc?: Regex.match?(~r/@doc\s/, sol),
      ex_tokens: measure(prompt, cpt).tokens + measure(sol, cpt).tokens
    }
  end

  defp measure("", _cpt), do: %{chars: 0, bytes: 0, words: 0, lines: 0, tokens: 0}

  defp measure(text, cpt) do
    chars = String.length(text)

    %{
      chars: chars,
      bytes: byte_size(text),
      words: text |> String.split(~r/\s+/, trim: true) |> length(),
      lines: text |> String.split("\n") |> length(),
      tokens: ceil(chars / cpt)
    }
  end

  defp parse_name(name) do
    case String.split(name, "_") do
      [a, b | rest] when rest != [] ->
        with {idea, ""} <- Integer.parse(a),
             {variant, ""} <- Integer.parse(b),
             {sub, ""} <- rest |> List.last() |> Integer.parse() do
          {idea, variant, sub}
        else
          _ -> {nil, nil, nil}
        end

      _ ->
        {nil, nil, nil}
    end
  end

  defp bundle_count(src), do: src |> Bundle.parse() |> length()

  defp bundle_kinds(src) do
    src
    |> Bundle.parse()
    |> Enum.map(fn {path, _} ->
      cond do
        path =~ ~r/migrat/i -> "migration"
        path =~ ~r/^config\// -> "config"
        path =~ ~r/test/i -> "test"
        String.ends_with?(path, ".ex") -> "lib"
        true -> "other"
      end
    end)
  end

  defp read(path), do: if(File.regular?(path), do: File.read!(path), else: "")

  # ---------------------------------------------------------------- aggregation

  defp compute(rows, cpt) do
    found = Enum.filter(rows, & &1.found)
    with_harness = Enum.filter(rows, &(&1.shape in [:single, :multifile] and &1.found))

    %{
      generated_at_note: "token counts are estimates at #{cpt} chars/token",
      chars_per_token: cpt,
      corpus: corpus(rows, found),
      pairs: pairs(rows, found, with_harness),
      tokens: tokens(found),
      distributions: distributions(found),
      context_windows: context_windows(found),
      structure: structure(rows, found),
      quality: quality(with_harness),
      coverage: coverage(rows)
    }
  end

  defp corpus(rows, found) do
    %{
      task_dirs: length(rows),
      gradable_examples: length(found),
      missing_solution: Enum.count(rows, &(not &1.found)),
      by_shape: freq(rows, & &1.shape),
      base_tasks: Enum.count(rows, & &1.base?),
      variations: Enum.count(rows, & &1.variation?),
      fim_subtasks: Enum.count(rows, & &1.fim?),
      distinct_ideas: rows |> Enum.map(& &1.idea) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
      with_prompt: Enum.count(rows, &(&1.prompt.chars > 0)),
      with_harness: Enum.count(rows, & &1.has_harness?),
      alternate_solutions: alternate_solutions()
    }
  end

  defp pairs(rows, found, with_harness) do
    %{
      "prompt→solution": length(found),
      "prompt→solution+tests": length(with_harness),
      "FIM prompt→function": Enum.count(rows, & &1.fim?),
      "alternate/negative solutions": alternate_solutions() |> Map.values() |> Enum.sum()
    }
  end

  defp tokens(found) do
    sum = fn key -> found |> Enum.map(&(Map.fetch!(&1, key).tokens)) |> Enum.sum() end
    p = sum.(:prompt)
    s = sum.(:sol)
    h = sum.(:harness)
    total = p + s + h

    %{
      total_est: total,
      by_file: %{prompt: p, solution: s, harness: h},
      by_file_pct: %{
        prompt: pct(p, total),
        solution: pct(s, total),
        harness: pct(h, total)
      },
      by_shape:
        found
        |> Enum.group_by(& &1.shape)
        |> Map.new(fn {shape, rs} ->
          {shape, rs |> Enum.map(&(&1.prompt.tokens + &1.sol.tokens + &1.harness.tokens)) |> Enum.sum()}
        end),
      raw_totals: %{
        chars: raw(found, :chars),
        bytes: raw(found, :bytes),
        words: raw(found, :words),
        lines: raw(found, :lines)
      }
    }
  end

  defp raw(found, unit) do
    found
    |> Enum.flat_map(&[Map.fetch!(&1, :prompt), Map.fetch!(&1, :sol), Map.fetch!(&1, :harness)])
    |> Enum.map(&Map.fetch!(&1, unit))
    |> Enum.sum()
  end

  defp distributions(found) do
    %{
      example_tokens: dist(Enum.map(found, & &1.ex_tokens)),
      solution_tokens: dist(Enum.map(found, & &1.sol.tokens)),
      prompt_tokens: dist(Enum.map(found, & &1.prompt.tokens)),
      harness_tokens: dist(found |> Enum.filter(& &1.has_harness?) |> Enum.map(& &1.harness.tokens))
    }
  end

  defp context_windows(found) do
    ex = Enum.map(found, & &1.ex_tokens)

    Map.new(@ctx_windows, fn w ->
      over = Enum.count(ex, &(&1 > w))
      lost = ex |> Enum.map(&max(0, &1 - w)) |> Enum.sum()
      {"#{w}", %{examples_over: over, pct_over: pct(over, length(ex)), tokens_truncated: lost}}
    end)
  end

  defp structure(rows, found) do
    var_fanout =
      rows
      |> Enum.filter(&(&1.subtask == 1 and &1.idea))
      |> Enum.group_by(& &1.idea)
      |> Map.new(fn {idea, rs} -> {idea, length(rs)} end)

    fim_per_parent =
      rows
      |> Enum.filter(& &1.fim?)
      |> Enum.group_by(&{&1.idea, &1.variant})
      |> Map.new(fn {k, rs} -> {k, length(rs)} end)

    multifile = Enum.filter(found, &(&1.shape == :multifile))

    %{
      variations_per_idea: dist(Map.values(var_fanout)),
      fim_subtasks_per_parent: dist(Map.values(fim_per_parent)),
      multifile_blocks: dist(Enum.map(multifile, & &1.bundle_files)),
      multifile_total_blocks: multifile |> Enum.map(& &1.bundle_files) |> Enum.sum(),
      multifile_file_kinds: multifile |> Enum.flat_map(& &1.bundle_kinds) |> freq(& &1),
      otp_behaviours: found |> Enum.flat_map(& &1.otp) |> freq(& &1)
    }
  end

  defp quality(with_harness) do
    n = max(length(with_harness), 1)

    ratios =
      with_harness
      |> Enum.filter(&(&1.sol.bytes > 0 and &1.has_harness?))
      |> Enum.map(&(&1.harness.bytes / &1.sol.bytes))

    %{
      solutions_scored: length(with_harness),
      moduledoc_pct: pct(Enum.count(with_harness, & &1.moduledoc?), n),
      spec_pct: pct(Enum.count(with_harness, & &1.spec?), n),
      doc_pct: pct(Enum.count(with_harness, & &1.doc?), n),
      tests_to_solution_ratio: dist_f(ratios),
      reference_scores: reference_scores()
    }
  end

  defp coverage(rows) do
    built = rows |> Enum.map(& &1.idea) |> Enum.reject(&is_nil/1) |> MapSet.new()
    planned = planned_ideas()

    %{
      ideas_built: MapSet.size(built),
      ideas_planned: MapSet.size(planned),
      pct_built: pct(MapSet.size(MapSet.intersection(built, planned)), max(MapSet.size(planned), 1))
    }
  end

  # ---------------------------------------------------------------- disk helpers

  defp alternate_solutions do
    Path.wildcard("tasks/*/solution_*.ex")
    |> Enum.map(fn p ->
      Path.basename(p) |> String.replace_prefix("solution_", "") |> String.replace_suffix(".ex", "")
    end)
    |> freq(& &1)
  end

  defp planned_ideas do
    ["tasks/tasks.md", "tasks/tasks_external.md"]
    |> Enum.filter(&File.regular?/1)
    |> Enum.flat_map(fn f ->
      Regex.scan(~r/^###\s+(\d+)\.\s/m, File.read!(f)) |> Enum.map(fn [_, n] -> String.to_integer(n) end)
    end)
    |> MapSet.new()
  end

  defp reference_scores do
    files = Path.wildcard("results/*.json") |> Enum.reject(&String.contains?(&1, "report_"))

    scores =
      files
      |> Enum.flat_map(fn f ->
        case Jason.decode(File.read!(f)) do
          {:ok, %{"score" => %{"overall" => o}}} when is_number(o) -> [o]
          _ -> []
        end
      end)

    case scores do
      [] -> %{available: false}
      _ -> Map.merge(%{available: true, count: length(scores)}, dist_f(scores))
    end
  end

  # ---------------------------------------------------------------- stat helpers

  defp freq(list, fun), do: list |> Enum.frequencies_by(fun) |> Map.new(fn {k, v} -> {to_string(k), v} end)

  defp dist([]), do: %{n: 0}

  defp dist(values) do
    s = Enum.sort(values)
    n = length(s)

    %{
      n: n,
      sum: Enum.sum(s),
      min: List.first(s),
      median: pctile(s, 0.50),
      mean: round(Enum.sum(s) / n),
      p90: pctile(s, 0.90),
      p99: pctile(s, 0.99),
      max: List.last(s)
    }
  end

  defp dist_f([]), do: %{n: 0}

  defp dist_f(values) do
    s = Enum.sort(values)
    n = length(s)
    r2 = &(Float.round(&1 / 1, 2))

    %{
      n: n,
      min: r2.(List.first(s)),
      median: r2.(pctile(s, 0.50)),
      mean: r2.(Enum.sum(s) / n),
      p90: r2.(pctile(s, 0.90)),
      max: r2.(List.last(s))
    }
  end

  defp pctile([], _), do: 0
  defp pctile(sorted, q), do: Enum.at(sorted, min(round(q * (length(sorted) - 1)), length(sorted) - 1))

  defp pct(_, 0), do: 0.0
  defp pct(x, total), do: Float.round(x * 100 / total, 1)

  # ---------------------------------------------------------------- rendering

  defp render(s) do
    line = String.duplicate("═", 64)
    IO.puts("\n#{line}\n  ELIXIR SFT DATASET — SUMMARY\n#{line}")
    IO.puts("  token counts are ESTIMATES at #{s.chars_per_token} chars/token\n")

    c = s.corpus
    section("CORPUS COMPOSITION")
    kv("Task directories", c.task_dirs)
    kv("Gradable examples (has solution)", c.gradable_examples)
    kv("  missing solution", c.missing_solution)
    kv("By shape", inspect(c.by_shape))
    kv("Base tasks / variations / FIM", "#{c.base_tasks} / #{c.variations} / #{c.fim_subtasks}")
    kv("Distinct ideas covered", c.distinct_ideas)
    kv("Have test_harness.exs", c.with_harness)
    kv("Alternate model solutions", inspect(c.alternate_solutions))

    section("SFT TRAINING PAIRS (by framing)")
    Enum.each(s.pairs, fn {k, v} -> kv(to_string(k), v) end)

    t = s.tokens
    section("TOKEN VOLUME (est)")
    kv("TOTAL tokens (prompt+solution+harness)", fmt(t.total_est))
    kv("  prompts", "#{fmt(t.by_file.prompt)}  (#{t.by_file_pct.prompt}%)")
    kv("  solutions", "#{fmt(t.by_file.solution)}  (#{t.by_file_pct.solution}%)")
    kv("  harnesses", "#{fmt(t.by_file.harness)}  (#{t.by_file_pct.harness}%)")
    kv("By shape", inspect(Map.new(t.by_shape, fn {k, v} -> {k, fmt(v)} end)))
    kv("Raw chars / bytes / words / lines",
      "#{fmt(t.raw_totals.chars)} / #{fmt(t.raw_totals.bytes)} / #{fmt(t.raw_totals.words)} / #{fmt(t.raw_totals.lines)}")

    section("LENGTH DISTRIBUTIONS (tokens/example)")
    drow("prompt+solution", s.distributions.example_tokens)
    drow("solution only", s.distributions.solution_tokens)
    drow("prompt only", s.distributions.prompt_tokens)
    drow("harness only", s.distributions.harness_tokens)

    section("CONTEXT-WINDOW FIT (prompt+solution)")
    Enum.each(@ctx_windows, fn w ->
      cw = s.context_windows["#{w}"]
      kv("> #{w} tok", "#{cw.examples_over} examples (#{cw.pct_over}%),  #{fmt(cw.tokens_truncated)} tok truncated")
    end)

    st = s.structure
    section("STRUCTURE & DIVERSITY")
    drow("_01s/idea (base+variations)", st.variations_per_idea)
    drow("FIM subtasks/parent (of parents w/ FIM)", st.fim_subtasks_per_parent)
    kv("Multi-file bundles", "#{st.multifile_blocks[:n]} tasks, #{st.multifile_total_blocks} <file> blocks")
    kv("  bundle file kinds", inspect(st.multifile_file_kinds))
    kv("OTP behaviours (in solutions)", inspect(st.otp_behaviours))

    q = s.quality
    section("QUALITY SIGNALS (single+multifile refs)")
    kv("Refs measured", q.solutions_scored)
    kv("@moduledoc / @spec / @doc", "#{q.moduledoc_pct}% / #{q.spec_pct}% / #{q.doc_pct}%")
    kv("tests:solution size ratio (mean)", "#{q.tests_to_solution_ratio[:mean]}×")

    if q.reference_scores.available do
      kv("Reference score (last run_all, may be stale)",
        "mean #{q.reference_scores[:mean]}, min #{q.reference_scores[:min]} (n=#{q.reference_scores.count}) — re-run scripts/run_all.exs to refresh")
    end

    cov = s.coverage
    section("ROADMAP COVERAGE")
    kv("Ideas built / planned", "#{cov.ideas_built} / #{cov.ideas_planned}  (#{cov.pct_built}% of catalog)")
    IO.puts("\n#{line}\n")
  end

  defp section(title), do: IO.puts("\n── #{title} " <> String.duplicate("─", max(0, 60 - String.length(title))))
  defp kv(k, v), do: IO.puts("  #{String.pad_trailing(k, 38)} #{v}")

  defp drow(label, %{n: 0}), do: kv(label, "(none)")

  defp drow(label, d) do
    kv(label, "n=#{d.n}  min #{fmt(d.min)}  med #{fmt(d.median)}  mean #{fmt(d.mean)}  p90 #{fmt(d.p90)}  max #{fmt(d.max)}")
  end

  defp fmt(n) when is_integer(n) do
    n |> Integer.to_string() |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
  end

  defp fmt(n), do: to_string(n)
end

DatasetStats.main(System.argv())
