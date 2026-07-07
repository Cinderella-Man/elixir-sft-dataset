defmodule EvalTask.Analysis do
  @moduledoc """
  Static analysis + scoring for evaluated solutions.

  ## Scoring model

      overall = tests · 0.7  +  analysis · 0.2  +  compilation · 0.1

  `overall` hard-fails to 0.0 when: the solution does not compile, it compiles
  with warnings, no test ran (`tests_total == 0`), or the harness errored
  (`tests_errors > 0`).

  * `compilation` = `max(0.0, 1.0 - warnings · 0.1)`
  * `tests`       = `tests_passed / tests_total`
  * `analysis`    = `awarded_points / max_points` over the checks below

  ### Analysis checks (KI-1 fix / T-SCORE-FIX)

  Points are awarded **only when the check passes** (the historical evaluator
  hardcoded the max regardless of pass/fail, making analysis a constant 1.0).
  Credo is **not** scored — it was a declared dependency that was never actually
  run (`credo_issues` was always `[]`), so its points are dropped and the
  remaining checks are renormalized.

  | mode      | checks                                                                 | max |
  |-----------|------------------------------------------------------------------------|-----|
  | `:full`   | moduledoc(2) @spec(2) @doc(1) line≤98(1) no-TODO(1) no-SQLi(1)          | 8   |
  | `:fim`    | line≤98(1) no-TODO(1) no-SQLi(1)  (a single infilled fn has no docs)    | 3   |
  """

  @type mode :: :full | :fim

  @type t :: %{
          has_moduledoc: boolean(),
          has_typespecs: boolean(),
          has_doc_on_public_fns: boolean(),
          line_count: non_neg_integer(),
          max_line_length: non_neg_integer(),
          lines_over_98: non_neg_integer(),
          public_fn_count: non_neg_integer(),
          defp_count: non_neg_integer(),
          todo_count: non_neg_integer(),
          pipe_chain_count: non_neg_integer(),
          sql_injection_risk: boolean(),
          mode: mode()
        }

  @doc "Analyze a single source string. `mode` selects the applicable check set."
  @spec analyze(String.t(), mode()) :: t()
  def analyze(source, mode \\ :full) do
    lines = String.split(source, "\n")
    line_lengths = Enum.map(lines, &String.length/1)

    %{
      has_moduledoc: String.contains?(source, "@moduledoc"),
      has_typespecs: Regex.match?(~r/@spec\s/, source),
      has_doc_on_public_fns: Regex.match?(~r/@doc\s/, source),
      line_count: length(lines),
      max_line_length: Enum.max(line_lengths, fn -> 0 end),
      lines_over_98: Enum.count(line_lengths, &(&1 > 98)),
      public_fn_count: length(Regex.scan(~r/^\s*def\s+\w+/m, source)),
      defp_count: length(Regex.scan(~r/^\s*defp\s+\w+/m, source)),
      todo_count: length(Regex.scan(~r/#\s*(TODO|FIXME|HACK|XXX)/i, source)),
      pipe_chain_count: length(Regex.scan(~r/\|>/m, source)),
      sql_injection_risk: Regex.match?(~r/".*\#\{.*\}.*FROM|WHERE.*\#\{/m, source),
      mode: mode
    }
  end

  @doc "Analyze several sources as one (multi-file: pass the bundle's `lib/**/*.ex`)."
  @spec analyze_all([String.t()], mode()) :: t()
  def analyze_all(sources, mode \\ :full) do
    analyze(Enum.join(sources, "\n"), mode)
  end

  # Each check: {awarded, max, passed?, label}. awarded is 0 unless passed.
  defp checks(a) do
    doc_checks =
      case a.mode do
        :fim ->
          []

        _ ->
          [
            check(2, a.has_moduledoc, "@moduledoc present"),
            check(2, a.has_typespecs, "@spec annotations present"),
            check(1, a.has_doc_on_public_fns, "@doc on public functions")
          ]
      end

    doc_checks ++
      [
        check(1, a.lines_over_98 == 0, "no lines over 98 chars (found #{a.lines_over_98})"),
        check(1, a.todo_count == 0, "no TODO/FIXME/HACK comments (found #{a.todo_count})"),
        check(1, !a.sql_injection_risk, "no SQL injection risk")
      ]
  end

  defp check(max, passed?, label), do: {if(passed?, do: max, else: 0), max, passed?, label}

  @doc """
  Compute the score map from compile info, analysis, and test counts.

  `compile` needs `:compiled` (bool) and `:compile_warnings` (int).
  `tests` needs `:tests_passed` and `:tests_total`.
  """
  @spec score(map(), t(), map()) :: map()
  def score(compile, analysis, tests) do
    compilation_score =
      if compile.compiled, do: max(0.0, 1.0 - compile.compile_warnings * 0.1), else: 0.0

    test_score =
      if tests.tests_total > 0, do: tests.tests_passed / tests.tests_total, else: 0.0

    cs = checks(analysis)
    awarded = cs |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    max_points = cs |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    analysis_score = if max_points > 0, do: min(awarded / max_points, 1.0), else: 1.0

    overall =
      cond do
        # A warning is treated as an error: a task with any compile/type
        # warning hard-fails, exactly like a compile failure.
        not compile.compiled -> 0.0
        compile.compile_warnings > 0 -> 0.0
        # No tests ran, or the harness errored: hard fail. A solution must not
        # bank the analysis+compilation subscores (up to 0.3) without a single
        # passing test — a harness-load failure used to outscore honest zeros.
        tests.tests_total == 0 -> 0.0
        Map.get(tests, :tests_errors, 0) > 0 -> 0.0
        true -> test_score * 0.7 + analysis_score * 0.2 + compilation_score * 0.1
      end

    %{
      compilation: Float.round(compilation_score, 2),
      tests: Float.round(test_score, 2),
      analysis: Float.round(analysis_score, 2),
      overall: Float.round(overall, 2),
      analysis_max_points: max_points,
      mode: analysis.mode,
      reasons: reasons(compile, tests, cs)
    }
  end

  defp reasons(compile, tests, cs) do
    []
    |> then(fn acc ->
      cond do
        not compile.compiled ->
          ["compilation: failed to compile (0.0)" | acc]

        compile.compile_warnings > 0 ->
          [
            "compilation: #{compile.compile_warnings} warning(s) → hard fail (overall 0.0)"
            | acc
          ]

        true ->
          acc
      end
    end)
    |> then(fn acc ->
      cond do
        tests.tests_total == 0 and compile.compiled ->
          ["tests: no tests ran → hard fail (overall 0.0)" | acc]

        Map.get(tests, :tests_errors, 0) > 0 ->
          ["tests: #{tests.tests_errors} harness error(s) → hard fail (overall 0.0)" | acc]

        tests.tests_total > 0 and tests.tests_passed < tests.tests_total ->
          ["tests: #{tests.tests_total - tests.tests_passed}/#{tests.tests_total} failed" | acc]

        true ->
          acc
      end
    end)
    |> then(fn acc ->
      failed =
        cs
        |> Enum.reject(fn {awarded, max, _p, _l} -> awarded == max end)
        |> Enum.map(fn {awarded, max, _p, label} ->
          "analysis: #{label} → #{awarded}/#{max} pts"
        end)

      failed ++ acc
    end)
    |> Enum.reverse()
    |> case do
      [] -> ["perfect score — no deductions"]
      list -> list
    end
  end
end
