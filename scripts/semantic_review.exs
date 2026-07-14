# semantic_review.exs — T2.2: scaled semantic review of root tasks (docs/15 T2.2).
#
# The 2026-07-12 11-dir pilot (review + adversarial verify) found 2 defective
# families among 11 — defects NO executing gate can see: a gold that games the
# style gate with dead code and no-op helpers (018_003), a harness asserting an
# API the prompt never grants (101_002), a @spec contradicting its own code
# (019_001), a test name promising a boundary its body does not touch. Both
# systemic classes from that pilot are hard accept lints now; this tool asks
# what ELSE is out there, at a measured cost, before deciding whether the full
# ~330-root pass pays.
#
# Method (register: "adversarially verified findings only"):
#   1. ONE review call per root — full context (prompt.md + solution.ex +
#      test_harness.exs), a rubric limited to the pilot's finding classes, and
#      an explicit anti-noise instruction (silence is the expected verdict).
#   2. ONE verify call per finding — an independent skeptic sees the same
#      context and one finding, and is told to REFUTE it. Only unrefuted
#      findings are CONFIRMED; everything else is recorded as noise.
#   3. Confirmed findings are hypotheses for a HUMAN (docs/14 rule 10) — they
#      become rule-7 two-tier STATUS items only after a hand-check.
#
# Population: the 332 screenable roots (single/multifile `_01`, repair_
# excluded), stratified by git first-add date of prompt.md — hand era
# (< 2026-07-01), early loop (07-01..07-09), current loop (>= 07-10) — and
# sampled deterministically (per-bucket sort by content sha, take first k;
# proportional allocation). No randomness: the same corpus state always picks
# the same batch, and the ledger makes reruns free.
#
# Usage:
#   mix run scripts/semantic_review.exs                      # plan: strata + batch
#   mix run scripts/semantic_review.exs -- --go --only "018_003*"   # pilot
#   mix run scripts/semantic_review.exs -- --go --dir <path> --as <label>
#                                          # review ONE staged dir (controls)
#   mix run scripts/semantic_review.exs -- --go              # the 60-root batch
#   mix run scripts/semantic_review.exs -- --go --sample 60  # explicit size
#   mix run scripts/semantic_review.exs -- --report          # ledger summary
#
# Ledger: logs/semantic_review.jsonl — one row per reviewed root, keyed by the
# (prompt, solution, harness) sha triple AND review_sha (sha256 of both prompt
# templates): editing either template re-opens every old row (rule-7 corollary).

alias GenTask.{Config, Cycle, CycleLog}

defmodule SemanticReview do
  @moduledoc false

  @ledger "logs/semantic_review.jsonl"
  @default_sample 60

  @review_persona """
  You are a principal Elixir engineer doing semantic quality control on a
  supervised-fine-tuning dataset. Each task is a triple: a natural-language
  prompt, a reference ("gold") solution, and an ExUnit test harness. All three
  already compile, pass, and satisfy the style gates — your job is ONLY the
  semantics no executing gate can see. You are terse and precise, you quote
  evidence verbatim, and you NEVER pad: for most tasks the correct verdict is
  an empty findings list.
  """

  @verify_persona """
  You are a skeptical principal Elixir engineer. A reviewer claims a defect in
  a training-data task. Your job is to REFUTE the claim if you can: re-read the
  full context and decide whether the claimed defect is real, material, and in
  scope. Reviewers over-report; when the evidence is ambiguous or the defect is
  out of scope, the claim is refuted. Be terse.
  """

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          go: :boolean,
          report: :boolean,
          only: :string,
          sample: :integer,
          dir: :string,
          as: :string
        ]
      )

    cond do
      opts[:report] -> report()
      opts[:go] && opts[:dir] -> go_single(opts)
      opts[:go] -> go(opts)
      true -> plan(opts)
    end
  end

  # ── population + strata ─────────────────────────────────────────────────────

  defp roots do
    EvalTask.Discovery.all()
    |> Enum.filter(&(&1.shape in [:single, :multifile] and &1.found))
    |> Enum.reject(&String.starts_with?(&1.name, "repair_"))
    |> Enum.map(& &1.dir)
    |> Enum.sort()
  end

  # Era = the git author date of the commit that ADDED the root's prompt.md.
  # One `git log` per root (~332 fast local calls, plan/go only).
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
      "" -> {:unborn, "9999"}
      date when date < "2026-07-01" -> {:hand_era, date}
      date when date < "2026-07-10" -> {:early_loop, date}
      date -> {:current_loop, date}
    end
  end

  # Deterministic proportional sample: per bucket, order by sha256(dir name)
  # and take the first k. Same corpus -> same batch, no randomness needed.
  defp batch(sample_size) do
    by_era = roots() |> Enum.group_by(fn dir -> era(dir) |> elem(0) end)
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

    IO.puts("Strata (332-root population, era = git first-add of prompt.md):")

    for {era, dirs} <- Enum.sort(by_era) do
      n = Enum.count(picked, fn {e, _} -> e == era end)
      IO.puts("  #{era}: #{length(dirs)} root(s) -> #{n} in batch")
    end

    IO.puts("\nBatch (#{length(picked)}):")

    for {era, dir} <- picked do
      status = if MapSet.member?(done, row_key(dir)), do: "done", else: "todo"
      IO.puts("  #{era}  #{Path.basename(dir)}  #{status}")
    end

    IO.puts("\nRun with `-- --go` (~1 review call + ~0-2 verify calls per root).")
  end

  # ── the loop ────────────────────────────────────────────────────────────────

  defp go(opts) do
    cfg = Config.new([])
    {_by_era, picked} = batch(opts[:sample] || @default_sample)
    done = done_keys()

    todo =
      picked
      |> Enum.filter(fn {_e, dir} -> match_only?(Path.basename(dir), opts[:only]) end)
      |> Enum.reject(fn {_e, dir} -> MapSet.member?(done, row_key(dir)) end)

    IO.puts("reviewing #{length(todo)} root(s), sequential, ledger #{@ledger}\n")

    Enum.each(Enum.with_index(todo, 1), fn {{era, dir}, i} ->
      IO.write("[#{i}/#{length(todo)}] #{Path.basename(dir)} ... ")
      row = review_root(cfg, dir, era)
      append_ledger(row)

      IO.puts(
        "#{length(row.findings)} finding(s), #{length(row.confirmed)} confirmed" <>
          if(row[:error], do: " — ERROR #{row.error}", else: "")
      )
    end)

    report()
  end

  # Review one arbitrary staged dir (positive controls: a pre-fix gold
  # reconstructed from git history). Rows are labeled and NEVER count toward
  # the batch ledger keys (the label prefixes the task name).
  defp go_single(opts) do
    cfg = Config.new([])
    label = opts[:as] || "control"
    row = review_root(cfg, opts[:dir], :control, "#{label}:#{Path.basename(opts[:dir])}")
    append_ledger(row)
    IO.puts(Jason.encode!(row, pretty: true))
  end

  defp review_root(cfg, dir, era, name_override \\ nil) do
    name = name_override || Path.basename(dir)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    harness = File.read!(Path.join(dir, "test_harness.exs"))

    base = %{
      task: name,
      era: era,
      prompt_sha: CycleLog.content_sha(prompt),
      solution_sha: CycleLog.content_sha(solution),
      harness_sha: CycleLog.content_sha(harness),
      review_sha: review_sha(),
      model: cfg.model,
      ts: now()
    }

    case review_call(cfg, name, prompt, solution, harness) do
      {:ok, findings} ->
        {confirmed, verdicts} =
          findings
          |> Enum.map(fn f ->
            case verify_call(cfg, name, prompt, solution, harness, f) do
              {:ok, %{"refuted" => false} = v} -> {f, Map.put(v, "finding", f)}
              {:ok, v} -> {nil, Map.put(v, "finding", f)}
              {:error, why} -> {nil, %{"error" => inspect(why), "finding" => f}}
            end
          end)
          |> Enum.unzip()

        Map.merge(base, %{
          findings: findings,
          confirmed: Enum.reject(confirmed, &is_nil/1),
          verdicts: verdicts
        })

      {:error, why} ->
        Map.merge(base, %{findings: [], confirmed: [], error: inspect(why)})
    end
  end

  # ── the two calls ───────────────────────────────────────────────────────────

  defp review_user(prompt, solution, harness) do
    """
    Review this task triple for SEMANTIC defects only. It already compiles,
    every test passes against the gold, formatting/style gates are green, and
    a prompt-only blind solve has been screened separately — do NOT comment on
    any of that.

    Report a finding ONLY in these classes (the ones that have produced real
    defects in this corpus):

    - "gold_defect": the solution contradicts the prompt (wrong algorithm,
      wrong edge case, wrong default), or contains dead/unreachable code,
      no-op helpers, or constructs whose only purpose is silencing a warning
      or gaming a style gate, or @doc/@spec statements that contradict the
      code itself.
    - "harness_gap": the harness never exercises a load-bearing behavior the
      prompt explicitly promises (a solver could ship that behavior wrong and
      still go green), or a test whose NAME/comment claims to pin one thing
      while its body tests something else.
    - "prompt_defect": the prompt contradicts itself, or is ambiguous on a
      load-bearing detail that the harness then silently pins one way.

    OUT OF SCOPE (do not report): style, idiom, naming taste, performance,
    test count, `Process.sleep` usage, `:sys.*` usage, missing describe
    blocks, "could also test X" suggestions where X is a minor variation of
    an existing test, and anything a compiler, formatter, or the passing test
    suite already proves.

    Most tasks in this corpus are CLEAN — an empty findings list is the
    expected verdict. Report a finding only when you can quote concrete
    evidence and state a material consequence; every finding you report is
    checked by an adversarial verifier, and unsupported findings are noise.

    Reply with EXACTLY one file block and nothing else:

    <file path="review.json">
    {
      "findings": [
        {
          "class": "gold_defect | harness_gap | prompt_defect",
          "file": "prompt.md | solution.ex | test_harness.exs",
          "evidence": "exact quoted line(s), with the line's text verbatim",
          "why": "one or two sentences: the defect and its material consequence",
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

  defp review_call(cfg, name, prompt, solution, harness) do
    user = review_user(prompt, solution, harness)

    case Cycle.generate(cfg, name, "semantic_review", @review_persona, user, &validate_review/1) do
      {:ok, %{"review.json" => json}} -> {:ok, Jason.decode!(json)["findings"]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_review(files) do
    with json when is_binary(json) <- files["review.json"] || {:error, "missing review.json"},
         {:ok, %{"findings" => f}} when is_list(f) <- Jason.decode(json),
         true <-
           Enum.all?(f, fn x ->
             is_map(x) and is_binary(x["class"]) and is_binary(x["evidence"]) and
               x["class"] in ["gold_defect", "harness_gap", "prompt_defect"]
           end) do
      :ok
    else
      {:error, msg} -> {:error, msg}
      _ -> {:error, "review.json must be {\"findings\": [{class,file,evidence,why,severity}]}"}
    end
  end

  defp verify_user(prompt, solution, harness, finding) do
    """
    A reviewer claims this defect in the task triple below:

    ```json
    #{Jason.encode!(finding, pretty: true)}
    ```

    Try to REFUTE the claim. It is refuted when ANY of these hold:
    - the quoted evidence does not appear in the stated file, or is quoted out
      of a context that changes its meaning;
    - the claimed behavior is actually consistent with the prompt when read
      carefully (quote the prompt line that reconciles it);
    - the claim is out of scope: style/idiom/performance/test-count taste,
      `Process.sleep` or `:sys.*` usage, or anything the compiler, formatter,
      or passing test suite already proves;
    - the consequence is immaterial: no plausible solver, trainer, or student
      of this data is misled.

    The claim SURVIVES only if the evidence is real, in scope, and material.

    Reply with EXACTLY one file block and nothing else:

    <file path="verdict.json">
    {
      "refuted": true or false,
      "reason": "one or two sentences; if refuted, the strongest single ground"
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

  defp verify_call(cfg, name, prompt, solution, harness, finding) do
    user = verify_user(prompt, solution, harness, finding)

    case Cycle.generate(cfg, name, "semantic_verify", @verify_persona, user, &validate_verdict/1) do
      {:ok, %{"verdict.json" => json}} -> {:ok, Jason.decode!(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_verdict(files) do
    with json when is_binary(json) <- files["verdict.json"] || {:error, "missing verdict.json"},
         {:ok, %{"refuted" => r}} when is_boolean(r) <- Jason.decode(json) do
      :ok
    else
      {:error, msg} -> {:error, msg}
      _ -> {:error, "verdict.json must be JSON with a boolean \"refuted\" field"}
    end
  end

  # ── ledger / keys / report ──────────────────────────────────────────────────

  # A root is done when its CURRENT content triple was reviewed under the
  # CURRENT templates. Control rows (label:name) never match a real root key.
  defp row_key(dir) do
    [
      Path.basename(dir),
      file_sha(dir, "prompt.md"),
      file_sha(dir, "solution.ex"),
      file_sha(dir, "test_harness.exs"),
      review_sha()
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
               "review_sha" => r
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

  # Editing either template invalidates every old row (the rule-7 corollary:
  # ledger rows are keyed to the gate's own code).
  defp review_sha do
    :crypto.hash(:sha256, review_user("", "", "") <> verify_user("", "", "", %{}))
    |> Base.encode16(case: :lower)
  end

  defp append_ledger(row) do
    File.mkdir_p!("logs")
    File.write!(@ledger, Jason.encode!(row) <> "\n", [:append])
  end

  defp report do
    case File.read(@ledger) do
      {:ok, body} ->
        rows =
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        real = Enum.reject(rows, &String.contains?(&1["task"], ":"))

        confirmed =
          Enum.flat_map(real, fn r -> Enum.map(r["confirmed"] || [], &{r["task"], &1}) end)

        noise =
          Enum.sum(
            Enum.map(real, &(length(&1["findings"] || []) - length(&1["confirmed"] || [])))
          )

        errors = Enum.count(rows, & &1["error"])

        IO.puts("\n=== SEMANTIC REVIEW LEDGER: #{length(real)} root(s) reviewed ===")

        IO.puts(
          "confirmed findings: #{length(confirmed)}  refuted/noise: #{noise}  errors: #{errors}"
        )

        for {task, f} <- confirmed do
          IO.puts(
            "  #{task} [#{f["class"]}/#{f["severity"]}] #{String.slice(f["why"] || "", 0, 140)}"
          )
        end

      _ ->
        IO.puts("no ledger yet")
    end
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

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end

SemanticReview.main(System.argv())
