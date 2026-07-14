# rubric_judge.exs — T2.4: rubric LLM-judge pass over PASSING tasks (sampled).
#
# Every root in this corpus is execution-verified (compiles, gold green, blind
# screen, mutation gates) — but our judges have only ever seen FAILURES. The
# OpenCodeInstruct ablation (docs/12 §6.4) shows judge filtering adds quality
# beyond execution filtering; its 3-axis rubric is used verbatim:
#
#   * requirement_conformance — does the gold do exactly what the prompt asks,
#     no more (silent extras) and no less (silent omissions)?
#   * logical_correctness    — is the algorithm sound beyond what the harness
#     happens to exercise (off-by-ones, degenerate inputs, concurrency)?
#   * edge_case_consideration — are the boundaries the prompt implies handled
#     and pinned (empty, zero, negative, duplicates, limits)?
#
# Each sampled root is judged TWICE: by the primary model (cfg.model) and by a
# SECOND model family (`--second-model`, default sonnet) on the same rubric,
# with per-axis agreement logged — a Panel-of-LLM-judges guard against
# single-judge bias (rule 10 in docs/14 §6 showed the bias is real).
#
# Scores are 1-5 per axis; any score <= 3 and any reported issue MUST carry
# verbatim evidence. The triage list is roots where BOTH families score <= 3
# on the same axis. An LLM verdict is a hypothesis (docs/14 rule 10): triage
# against the artifacts before editing anything.
#
#   mix run scripts/rubric_judge.exs                    # plan: strata + batch
#   mix run scripts/rubric_judge.exs -- --go --limit 4  # pilot (rule 9)
#   mix run scripts/rubric_judge.exs -- --go            # the sampled pass
#   mix run scripts/rubric_judge.exs -- --report        # ledger summary
#
# Ledger: logs/rubric_judge.jsonl — one row per root, BOTH judges inside, keyed
# by (task, prompt/solution/harness shas, rubric sha): editing any of the four
# invalidates the row (rule-7 corollary), and resume skips only current rows.

alias GenTask.{Config, Cycle, CycleLog}

defmodule RubricJudge do
  @moduledoc false

  @ledger "logs/rubric_judge.jsonl"
  @default_sample 40
  @axes ~w(requirement_conformance logical_correctness edge_case_consideration)

  @persona "You are a meticulous senior Elixir engineer auditing training data. " <>
             "You reply with ONLY the requested <file> block, nothing else."

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          go: :boolean,
          report: :boolean,
          only: :string,
          sample: :integer,
          limit: :integer,
          second_model: :string
        ]
      )

    cond do
      opts[:report] -> report()
      opts[:go] -> go(opts)
      true -> plan(opts)
    end
  end

  # ── population + deterministic stratified batch (semantic_review's shape) ──

  defp roots do
    EvalTask.Discovery.all()
    |> Enum.filter(&(&1.shape in [:single, :multifile] and &1.found))
    |> Enum.reject(&String.starts_with?(&1.name, "repair_"))
    |> Enum.map(& &1.dir)
    |> Enum.sort()
  end

  defp era(dir) do
    {out, 0} =
      System.cmd("git", [
        "log",
        "--diff-filter=A",
        "-1",
        "--format=%as",
        "--",
        dir <> "/prompt.md"
      ])

    case String.trim(out) do
      "" -> :unborn
      date when date < "2026-07-01" -> :hand_era
      date when date < "2026-07-10" -> :early_loop
      _ -> :current_loop
    end
  end

  defp batch(sample_size) do
    by_era = roots() |> Enum.group_by(&era/1)
    total = by_era |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

    counts =
      Map.new(by_era, fn {era, dirs} ->
        {era, max(1, round(sample_size * length(dirs) / total))}
      end)

    picked =
      Enum.flat_map(by_era, fn {era, dirs} ->
        dirs
        |> Enum.sort_by(&CycleLog.content_sha/1)
        |> Enum.take(counts[era])
        |> Enum.map(&{era, &1})
      end)

    {by_era, Enum.sort_by(picked, fn {_e, dir} -> dir end)}
  end

  defp plan(opts) do
    {by_era, picked} = batch(opts[:sample] || @default_sample)
    done = done_keys()

    IO.puts("Strata (era = git first-add of prompt.md):")

    for {era, dirs} <- Enum.sort(by_era) do
      n = Enum.count(picked, fn {e, _} -> e == era end)
      IO.puts("  #{era}: #{length(dirs)} root(s) -> #{n} in batch")
    end

    IO.puts("\nBatch (#{length(picked)}; 2 judge calls per root):")

    for {era, dir} <- picked do
      status = if MapSet.member?(done, row_key(dir)), do: "done", else: "todo"
      IO.puts("  #{era}  #{Path.basename(dir)}  #{status}")
    end

    IO.puts("\nRun with `-- --go` (pilot first: `-- --go --limit 4`, rule 9).")
  end

  # ── the loop ────────────────────────────────────────────────────────────────

  defp go(opts) do
    refuse_if_generate_alive!()
    cfg = Config.new([])
    second = opts[:second_model] || "sonnet"
    {_by_era, picked} = batch(opts[:sample] || @default_sample)
    done = done_keys()

    todo =
      picked
      |> Enum.filter(fn {_e, dir} -> match_only?(Path.basename(dir), opts[:only]) end)
      |> Enum.reject(fn {_e, dir} -> MapSet.member?(done, row_key(dir)) end)
      |> then(fn list -> if opts[:limit], do: Enum.take(list, opts[:limit]), else: list end)

    IO.puts(
      "judging #{length(todo)} root(s) with #{cfg.model} + #{second}, " <>
        "sequential, ledger #{@ledger}\n"
    )

    Enum.each(Enum.with_index(todo, 1), fn {{era, dir}, i} ->
      IO.write("[#{i}/#{length(todo)}] #{Path.basename(dir)} ... ")
      row = judge_root(cfg, second, dir, era)
      append_ledger(row)
      IO.puts(row_summary(row))
    end)

    report()
  end

  defp judge_root(cfg, second_model, dir, era) do
    name = Path.basename(dir)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    harness = File.read!(Path.join(dir, "test_harness.exs"))

    judges =
      for model <- [cfg.model, second_model] do
        case judge_call(%{cfg | model: model}, name, prompt, solution, harness) do
          {:ok, verdict} -> Map.merge(verdict, %{"model" => model})
          {:error, why} -> %{"model" => model, "error" => inspect(why)}
        end
      end

    %{
      task: name,
      era: era,
      prompt_sha: CycleLog.content_sha(prompt),
      solution_sha: CycleLog.content_sha(solution),
      harness_sha: CycleLog.content_sha(harness),
      rubric_sha: rubric_sha(),
      judges: judges,
      agreement: agreement(judges),
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Per axis: judges agree when both scored and within 1 point. `nil` when
  # either judge errored — an unknown, never an agreement.
  defp agreement([a, b]) do
    Map.new(@axes, fn axis ->
      with %{"scores" => %{^axis => sa}} <- a,
           %{"scores" => %{^axis => sb}} <- b do
        {axis, abs(sa - sb) <= 1}
      else
        _ -> {axis, nil}
      end
    end)
  end

  defp row_summary(%{judges: judges} = row) do
    scores =
      Enum.map_join(judges, " | ", fn j ->
        case j do
          %{"scores" => s} ->
            "#{j["model"]}: " <> Enum.map_join(@axes, "/", &to_string(s[&1]))

          _ ->
            "#{j["model"]}: ERROR"
        end
      end)

    flags = Enum.count(@axes, &(row.agreement[&1] == false))
    scores <> if flags > 0, do: "  [#{flags} axis disagreement(s)]", else: ""
  end

  # ── the rubric call ─────────────────────────────────────────────────────────

  defp judge_user(prompt, solution, harness) do
    """
    Score this VERIFIED-PASSING Elixir training task on the three axes below.
    Execution facts you must NOT re-litigate: it compiles warning-free, the
    gold passes every harness test, an independent prompt-only solve has been
    screened, and mutation gates measured the harness's kill rate. Judge what
    execution CANNOT prove.

    Axes (score each 1-5; 5 = exemplary, 4 = solid, 3 = adequate with real
    weaknesses, 2 = materially deficient, 1 = misleading training data):

    - "requirement_conformance": the gold does exactly what the prompt asks —
      no silent extras a student would wrongly learn as required, no silent
      omissions the harness fails to notice.
    - "logical_correctness": the algorithm is sound beyond what the tests
      happen to exercise — off-by-ones, degenerate inputs, ordering,
      concurrency and failure paths are handled the way the prompt implies.
    - "edge_case_consideration": the boundaries the prompt implies (empty,
      zero, negative, duplicates, limits, timeouts) are handled in the gold
      AND meaningfully pinned by the harness.

    Rules:
    - Any score <= 3, and every issue you report, MUST quote verbatim evidence
      from the files below and state the material consequence.
    - OUT OF SCOPE: style, idiom, naming, performance taste, test count,
      `Process.sleep`/`:sys.*` usage, and anything the compiler, formatter, or
      passing suite already proves. Scores of 4-5 with an empty issues list
      are the EXPECTED verdict for a clean task — do not invent findings.

    Reply with EXACTLY one file block and nothing else:

    <file path="rubric.json">
    {
      "scores": {
        "requirement_conformance": 1-5,
        "logical_correctness": 1-5,
        "edge_case_consideration": 1-5
      },
      "issues": [
        {
          "axis": "requirement_conformance | logical_correctness | edge_case_consideration",
          "file": "prompt.md | solution.ex | test_harness.exs",
          "evidence": "exact quoted line(s)",
          "why": "one or two sentences: the issue and its material consequence",
          "severity": "high | medium"
        }
      ]
    }
    </file>

    === prompt.md ===
    #{prompt}

    === solution.ex (the gold) ===
    #{solution}

    === test_harness.exs ===
    #{harness}
    """
  end

  defp judge_call(cfg, name, prompt, solution, harness) do
    user = judge_user(prompt, solution, harness)

    case Cycle.generate(cfg, name, "rubric_judge", @persona, user, &validate_rubric/1) do
      {:ok, %{"rubric.json" => json}} -> {:ok, Jason.decode!(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_rubric(files) do
    with json when is_binary(json) <- files["rubric.json"] || {:error, "missing rubric.json"},
         {:ok, %{"scores" => scores, "issues" => issues}} <- Jason.decode(json),
         true <- Enum.all?(@axes, &(is_integer(scores[&1]) and scores[&1] in 1..5)),
         true <- is_list(issues),
         true <-
           Enum.all?(issues, fn i ->
             is_map(i) and i["axis"] in @axes and is_binary(i["evidence"]) and
               is_binary(i["why"]) and i["severity"] in ["high", "medium"]
           end) do
      :ok
    else
      {:error, msg} ->
        {:error, msg}

      _ ->
        {:error,
         "rubric.json must be {\"scores\": {each axis 1-5}, \"issues\": " <>
           "[{axis,file,evidence,why,severity}]}"}
    end
  end

  # ── ledger / keys / report ──────────────────────────────────────────────────

  defp row_key(dir) do
    [
      Path.basename(dir),
      file_sha(dir, "prompt.md"),
      file_sha(dir, "solution.ex"),
      file_sha(dir, "test_harness.exs"),
      rubric_sha()
    ]
    |> Enum.join("|")
  end

  defp done_keys do
    case File.read(@ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(MapSet.new(), fn line, acc ->
          case Jason.decode(line) do
            {:ok,
             %{
               "task" => t,
               "prompt_sha" => p,
               "solution_sha" => s,
               "harness_sha" => h,
               "rubric_sha" => r
             }} ->
              MapSet.put(acc, Enum.join([t, p, s, h, r], "|"))

            _ ->
              acc
          end
        end)

      _ ->
        MapSet.new()
    end
  end

  # Editing the rubric invalidates every old row (rule-7 corollary).
  defp rubric_sha do
    :crypto.hash(:sha256, @persona <> judge_user("", "", ""))
    |> Base.encode16(case: :lower)
  end

  defp append_ledger(row) do
    File.mkdir_p!("logs")
    File.write!(@ledger, Jason.encode!(row) <> "\n", [:append])
  end

  defp report do
    case File.read(@ledger) do
      {:ok, body} ->
        rows = body |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

        IO.puts("\n=== RUBRIC JUDGE LEDGER (#{length(rows)} root(s)) ===")

        for axis <- @axes do
          {lows, agrees} = axis_stats(rows, axis)

          IO.puts(
            "  #{axis}: both-judge low (<=3): #{length(lows)}; " <>
              "agreement rate: #{agrees}"
          )

          for t <- lows, do: IO.puts("    TRIAGE #{t}")
        end

        errs = Enum.count(rows, fn r -> Enum.any?(r["judges"], &Map.has_key?(&1, "error")) end)
        if errs > 0, do: IO.puts("  rows with a judge error: #{errs}")

      _ ->
        IO.puts("no ledger yet")
    end
  end

  defp axis_stats(rows, axis) do
    lows =
      for r <- rows,
          scores = Enum.map(r["judges"], &get_in(&1, ["scores", axis])),
          Enum.all?(scores, &(is_integer(&1) and &1 <= 3)),
          do: r["task"]

    judged = Enum.filter(rows, fn r -> is_boolean(r["agreement"][axis]) end)

    rate =
      case length(judged) do
        0 -> "n/a"
        n -> "#{Enum.count(judged, & &1["agreement"][axis])}/#{n}"
      end

    {lows, rate}
  end

  defp match_only?(_f, nil), do: true

  defp match_only?(f, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, f)
    end)
  end

  defp file_sha(dir, name), do: CycleLog.content_sha(File.read!(Path.join(dir, name)))

  defp refuse_if_generate_alive! do
    {out, _} = System.cmd("pgrep", ["-af", "beam.smp"], stderr_to_stdout: true)

    if String.contains?(out, "generate.exs") do
      IO.puts("REFUSING --go: a generation loop (generate.exs) is alive.")
      System.halt(1)
    end
  end
end

RubricJudge.main(System.argv())
