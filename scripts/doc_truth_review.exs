# doc_truth_review.exs — the G5 @doc-prose-truth sweep (STATUS item 6).
#
# For every root (`_01`, shapes :single/:multifile), one LLM judge call reads
# prompt.md + solution.ex and reports every @moduledoc/@doc/@typedoc
# BEHAVIORAL claim that is:
#
#   * `contradiction` — the code demonstrably does something else (the 062_001
#     failed-stage-timing class),
#   * `phantom_api`   — the doc references a function/arity that does not
#     exist (the 099_004 `stats/0` class),
#   * `unpromised`    — the doc asserts contractual-sounding behavior the
#     prompt never promises AND no test anchors (the docs/19 class; per G5
#     the fix is a prompt sentence + anchored test, or the sentence is cut).
#
# REPORT-ONLY, like semantic_review.exs: findings are hypotheses for the fix
# queue, each verified on artifact reads before any edit (CONTEXT rule 8 and
# the standing per-finding-evidence lesson). No verify pass here — the G5
# pilot measured this finding class at 5/5 CONFIRMED on hand reads; the fix
# lane is the adversarial filter.
#
# Ledger: logs/doc_truth.jsonl — one row per root, keyed by prompt+solution
# shas + THIS FILE's own sha (a changed judge re-opens its verdicts, docs/12
# §5.1.12). Resumable: sha-current rows are skipped.
#
#   mix run scripts/doc_truth_review.exs -- --census        # no calls
#   mix run scripts/doc_truth_review.exs -- --limit 5       # pilot
#   mix run scripts/doc_truth_review.exs -- --only "032_*"
#   mix run scripts/doc_truth_review.exs                    # full sweep
#   mix run scripts/doc_truth_review.exs -- --report        # summarize ledger
#
# Run DETACHED (scripts/run_detached.sh) — 1 call per root, ~330 total.

alias GenTask.{Config, Cycle, CycleLog}

defmodule DocTruthReview do
  @moduledoc false

  @ledger "doc_truth.jsonl"

  @persona """
  You are a principal Elixir engineer auditing DOCUMENTATION TRUTH in a
  supervised-fine-tuning dataset. Each task pairs a natural-language prompt
  (the contract) with a reference solution. Everything compiles and passes
  its tests — your job is ONLY whether the solution's documentation prose
  (@moduledoc/@doc/@typedoc) tells the truth. You are terse, you quote
  evidence verbatim, and you NEVER pad: most modules are clean, and an empty
  findings list is the expected verdict.
  """

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [census: :boolean, report: :boolean, limit: :integer, only: :string]
      )

    cond do
      opts[:report] -> report()
      true -> run(opts)
    end
  end

  defp run(opts) do
    cfg = Config.new([])
    todo = candidates(cfg, opts[:only])

    if opts[:census] do
      IO.puts("doc-truth candidates (no sha-current ledger row): #{length(todo)}")
      System.halt(0)
    end

    todo = if opts[:limit], do: Enum.take(todo, opts[:limit]), else: todo
    IO.puts("doc-truth review: #{length(todo)} root(s), sequential, 1 call each")

    freq =
      todo
      |> Enum.with_index(1)
      |> Enum.map(fn {dir, i} ->
        IO.write("[#{i}/#{length(todo)}] #{Path.basename(dir)} ... ")
        out = review_one(dir, cfg)
        IO.puts(out)
        out
      end)
      |> Enum.frequencies()

    IO.puts("doc-truth review done: #{inspect(freq)}")
    if freq[:error], do: System.halt(1)
  end

  # ── scope: roots with doc attributes, minus sha-current ledger rows ────────

  @doc false
  def candidates(cfg, only_glob) do
    seen = current_keys(cfg)

    Path.wildcard(Path.join(cfg.tasks_dir, "[0-9]*_01"))
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(&match_only?(Path.basename(&1), only_glob))
    |> Enum.filter(fn dir ->
      with {:ok, p} <- File.read(Path.join(dir, "prompt.md")),
           {:ok, s} <- File.read(Path.join(dir, "solution.ex")) do
        String.contains?(s, "@moduledoc") and not MapSet.member?(seen, key(p, s))
      else
        _ -> false
      end
    end)
    |> Enum.sort()
  end

  defp key(prompt, solution) do
    CycleLog.content_sha(prompt) <> ":" <> CycleLog.content_sha(solution) <> ":" <> gate_sha()
  end

  # The judge's own bytes key the verdicts: an edited judge re-opens them.
  defp gate_sha, do: CycleLog.content_sha(File.read!(__ENV__.file))

  defp current_keys(cfg) do
    case File.read(Path.join(cfg.logs_dir, @ledger)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn l ->
          case Jason.decode(l) do
            {:ok, %{"key" => k}} -> [k]
            _ -> []
          end
        end)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  # ── the judge call ─────────────────────────────────────────────────────────

  defp review_one(dir, cfg) do
    id = Path.basename(dir)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    harness = File.read(Path.join(dir, "test_harness.exs")) |> elem(1)

    user = """
    Audit the documentation prose of this solution against its prompt (the
    contract) and its code. Report ONLY doc-truth findings:

    - "contradiction": a @moduledoc/@doc/@typedoc sentence claims behavior the
      CODE demonstrably does not have (quote the sentence AND name the code
      path that contradicts it).
    - "phantom_api": the doc references a function/arity that does not exist
      in the module.
    - "unpromised": the doc asserts contractual-sounding behavior (limits,
      ordering, atomicity, persistence, cleanup, exactness…) that the PROMPT
      never promises and no test in the harness anchors — the claim may even
      be true today, but nothing pins it.

    NOT findings: style, missing docs, wording taste, claims the prompt DOES
    entail, private-helper comments, or anything about the tests themselves.

    Reply with exactly one file block:

    <file path="review.json">
    {"findings": [{"class": "contradiction|phantom_api|unpromised",
                   "claim": "<the doc sentence, verbatim>",
                   "why": "<one terse sentence>",
                   "severity": "high|medium|low"}]}
    </file>

    An empty findings list is the expected verdict for a clean module.

    === PROMPT (the contract) ===
    #{prompt}

    === SOLUTION ===
    ```elixir
    #{solution}
    ```

    === HARNESS (for the "no test anchors" half of unpromised) ===
    ```elixir
    #{harness}
    ```
    """

    case Cycle.generate(cfg, id, "doc_truth", @persona, user, &validate/1) do
      {:ok, files} ->
        {:ok, %{"findings" => findings}} = Jason.decode(files["review.json"])

        append(cfg, %{
          ts: DateTime.utc_now() |> DateTime.to_iso8601(),
          task: id,
          key: key(prompt, solution),
          prompt_sha: CycleLog.content_sha(prompt),
          solution_sha: CycleLog.content_sha(solution),
          model: cfg.model,
          findings: findings
        })

        if findings == [], do: :clean, else: :"#{length(findings)}_findings"

      {:error, why} ->
        IO.write("(#{inspect(why)}) ")
        :error
    end
  end

  defp validate(files) do
    with json when is_binary(json) <- files["review.json"] || {:error, "missing review.json"},
         {:ok, %{"findings" => f}} when is_list(f) <- Jason.decode(json),
         true <-
           Enum.all?(f, fn x ->
             is_map(x) and is_binary(x["claim"]) and
               x["class"] in ["contradiction", "phantom_api", "unpromised"]
           end) do
      :ok
    else
      {:error, %Jason.DecodeError{} = e} -> {:error, "review.json: " <> Exception.message(e)}
      {:error, msg} -> {:error, msg}
      _ -> {:error, "review.json must be {\"findings\": [{class,claim,why,severity}]}"}
    end
  end

  defp append(cfg, row) do
    File.mkdir_p!(cfg.logs_dir)
    File.write!(Path.join(cfg.logs_dir, @ledger), Jason.encode!(row) <> "\n", [:append])
  end

  # ── report ─────────────────────────────────────────────────────────────────

  defp report do
    cfg = Config.new([])

    rows =
      case File.read(Path.join(cfg.logs_dir, @ledger)) do
        {:ok, body} ->
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        _ ->
          []
      end

    latest = rows |> Enum.reduce(%{}, fn r, acc -> Map.put(acc, r["task"], r) end)
    with_findings = latest |> Map.values() |> Enum.filter(&(&1["findings"] != []))

    IO.puts("doc-truth ledger: #{map_size(latest)} root(s), #{length(with_findings)} with findings")

    for r <- Enum.sort_by(with_findings, & &1["task"]),
        f <- r["findings"] do
      IO.puts("  #{r["task"]} [#{f["severity"]}/#{f["class"]}] #{String.slice(f["claim"], 0, 90)}")
    end
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
end

unless System.get_env("SCRIPTS_NO_AUTORUN"), do: DocTruthReview.main(System.argv())
