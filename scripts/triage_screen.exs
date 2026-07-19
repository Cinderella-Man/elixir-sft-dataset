# triage_screen.exs — LLM-judge triage of the blind-solve quarantine (docs/10 R12d).
#
# For every task whose LATEST screen verdict is RED, ask a judge one question:
#
#     Is the failing assertion ENTAILED by prompt.md? Quote the sentence that
#     justifies it — or say none.
#
# ENTAILED  → solver-weak: the task is legitimately hard; verdict "keep".
# NOT       → prompt gap: the judge proposes the ONE sentence to add; a human
#             applies it (never automatically — prompt edits cascade, see
#             docs/10 invariant #5) and the sha-keyed screen re-screens it.
#
# Verdicts append to logs/screen_triage.jsonl keyed by (task, prompt sha):
# re-running skips already-triaged reds; a changed prompt re-triages.
#
# Usage:
#   mix run scripts/triage_screen.exs                   # all untriaged reds
#   mix run scripts/triage_screen.exs --only "007_*"    # name filter
#   mix run scripts/triage_screen.exs --limit 5
#   mix run scripts/triage_screen.exs --model opus
#   mix run scripts/triage_screen.exs --report          # NO calls: summarize ledger

alias GenTask.{Config, Cycle, CycleLog}

defmodule TriageScreen do
  @moduledoc false

  @screen_ledger "screen_blind.jsonl"
  @triage_ledger "screen_triage.jsonl"

  @judge_persona """
  You are a meticulous test-requirements auditor for an Elixir SFT dataset.
  Your only job: decide whether a failing test assertion is ENTAILED by the
  task prompt a blind solver was given. Entailed means a careful reader of the
  prompt ALONE (no reference solution, no harness) must arrive at code that
  satisfies the assertion. House-style conventions (idiomatic Elixir, OTP
  patterns) count as known; specific undocumented values, names, message
  wordings, or option semantics do not.
  """

  def main(argv) do
    # `mix run script.exs -- --report` leaves the literal `--` in System.argv, and
    # OptionParser treats it as an end-of-options terminator — silently dropping every
    # flag and turning a report-only invocation into a PAID screen run. Accept both
    # invocations by dropping a leading `--` (same fix as resync_tfim_embeds.exs).
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [only: :string, limit: :integer, model: :string, report: :boolean]
      )

    cfg = Config.new([])
    cfg = if opts[:model], do: %{cfg | model: opts[:model]}, else: cfg

    if opts[:report], do: report(cfg), else: triage(cfg, opts)
  end

  defp triage(cfg, opts) do
    reds =
      latest_entries(screen_path(cfg))
      |> Enum.filter(&(&1["green"] == false))
      |> Enum.filter(&match_only?(&1["task"], opts[:only]))
      |> Enum.reject(&triaged?(cfg, &1))
      |> Enum.sort_by(& &1["task"])

    reds = if opts[:limit], do: Enum.take(reds, opts[:limit]), else: reds

    IO.puts("Screen triage: #{length(reds)} untriaged RED task(s) — model=#{cfg.model}")

    Enum.with_index(reds, 1)
    |> Enum.each(fn {entry, i} ->
      IO.write("[#{i}/#{length(reds)}] #{entry["task"]} ... ")
      verdict = judge_one(cfg, entry)
      IO.puts(verdict_text(verdict))
      append_ledger(cfg, verdict)
    end)

    summarize(cfg)
  end

  defp judge_one(cfg, entry) do
    task = entry["task"]
    dir = Path.join("tasks", task)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    candidate = read_candidate(cfg, task, entry["sha"])

    user = """
    ## Task prompt (what the blind solver saw — the ONLY specification)

    #{prompt}

    ## Blind-solve failure (first failing test against the official harness)

    ```
    #{entry["first_failure"] || "unknown"}
    ```
    #{candidate_section(candidate)}

    ## Your job

    Decide: is the behavior the failing test demands ENTAILED by the prompt above?

    Reply with EXACTLY one file block and nothing else:

    <file path="verdict.json">
    {
      "entailed": true or false,
      "quote": "the exact prompt sentence(s) that justify the assertion, or \\"\\" if none",
      "reason": "one or two sentences explaining the decision",
      "missing_contract": "if not entailed: the single sentence to add to the prompt that would close the gap, else \\"\\""
    }
    </file>
    """

    case Cycle.generate(cfg, task, "screen_triage", @judge_persona, user, &validate_verdict/1) do
      {:ok, %{"verdict.json" => json}} ->
        v = Jason.decode!(json)

        %{
          task: task,
          sha: entry["sha"],
          entailed: v["entailed"],
          quote: v["quote"],
          reason: v["reason"],
          missing_contract: v["missing_contract"],
          first_failure: String.slice(entry["first_failure"] || "", 0, 200),
          model: cfg.model,
          ts: DateTime.utc_now() |> DateTime.to_iso8601()
        }

      {:error, reason} ->
        %{
          task: task,
          sha: entry["sha"],
          error: inspect(reason),
          model: cfg.model,
          ts: DateTime.utc_now() |> DateTime.to_iso8601()
        }
    end
  end

  defp validate_verdict(files) do
    with json when is_binary(json) <- files["verdict.json"] || {:error, "missing verdict.json"},
         {:ok, %{"entailed" => e}} when is_boolean(e) <- Jason.decode(json) do
      :ok
    else
      {:error, msg} -> {:error, msg}
      _ -> {:error, "verdict.json must be JSON with a boolean \"entailed\" field"}
    end
  end

  defp candidate_section(nil), do: ""

  defp candidate_section(src) do
    """

    ## The blind solver's candidate (for context — judge the PROMPT, not this code)

    ```elixir
    #{String.slice(src, 0, 8000)}
    ```
    """
  end

  defp read_candidate(cfg, task, sha) do
    sha8 = String.slice(sha || "", 0, 8)
    path = Path.join([cfg.logs_dir, "screen_candidates", "#{task}__#{sha8}.ex"])

    case File.read(path) do
      {:ok, src} -> src
      _ -> nil
    end
  end

  # ── ledgers ─────────────────────────────────────────────────────────────────

  defp screen_path(cfg), do: Path.join(cfg.logs_dir, @screen_ledger)
  defp triage_path(cfg), do: Path.join(cfg.logs_dir, @triage_ledger)

  defp rows(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, e} -> [e]
            _ -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp latest_entries(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, e} -> [e]
            _ -> []
          end
        end)
        |> Enum.reduce(%{}, fn e, acc -> Map.put(acc, e["task"], e) end)
        |> Map.values()

      {:error, _} ->
        []
    end
  end

  defp triaged?(cfg, entry) do
    latest_entries(triage_path(cfg))
    |> Enum.any?(fn t ->
      t["task"] == entry["task"] and t["sha"] == entry["sha"] and t["error"] == nil
    end)
  end

  defp append_ledger(cfg, verdict) do
    File.mkdir_p!(cfg.logs_dir)
    File.write!(triage_path(cfg), Jason.encode!(verdict) <> "\n", [:append])
  end

  # ── reporting ───────────────────────────────────────────────────────────────

  defp verdict_text(%{error: reason}), do: "ERROR (#{reason})"
  defp verdict_text(%{entailed: true}), do: "ENTAILED (solver-weak — keep)"
  defp verdict_text(%{entailed: false} = v), do: "PROMPT GAP: #{v.missing_contract}"

  defp summarize(cfg) do
    entries = latest_entries(triage_path(cfg))
    keep = Enum.filter(entries, &(&1["entailed"] == true))
    errors = Enum.filter(entries, &(&1["error"] != nil))

    # A gap verdict is only actionable while it refers to the CURRENT prompt and the
    # task is still red: an applied backfill changes the prompt sha (and usually
    # re-screens green), so those entries are history, not work.
    screen = latest_entries(screen_path(cfg)) |> Map.new(&{&1["task"], &1})

    # A human-review row with `resolution` (e.g. "rejected") closes the gap for
    # that (task, prompt sha) even though the prompt was deliberately NOT
    # edited — over-specified or gold-contradicting proposals end here.
    resolutions =
      rows(triage_path(cfg))
      |> Enum.filter(&(&1["resolution"] != nil))
      |> MapSet.new(&{&1["task"], &1["sha"]})

    {gaps, stale} =
      entries
      |> Enum.filter(&(&1["entailed"] == false))
      |> Enum.split_with(fn g ->
        current_sha(g["task"]) == g["sha"] and get_in(screen, [g["task"], "green"]) != true and
          not MapSet.member?(resolutions, {g["task"], g["sha"]})
      end)

    IO.puts("""

    === SCREEN TRIAGE SUMMARY (whole ledger) ===
      triaged: #{length(entries)}   entailed/keep: #{length(keep)}   open prompt gaps: #{length(gaps)}   stale/resolved/rejected gaps: #{length(stale)}   errors: #{length(errors)}   review-resolutions: #{MapSet.size(resolutions)}
    """)

    if gaps != [] do
      IO.puts("  PROMPT GAPS (human sign-off + backfill needed — cascade per docs/10 inv. #5):")

      Enum.each(gaps, fn g ->
        IO.puts("    - #{g["task"]}\n        #{g["missing_contract"]}")
      end)
    end
  end

  defp current_sha(task) do
    path = Path.join(["tasks", task, "prompt.md"])

    case File.read(path) do
      {:ok, prompt} -> CycleLog.content_sha(prompt)
      _ -> nil
    end
  end

  defp report(cfg), do: summarize(cfg)

  defp match_only?(_name, nil), do: true

  defp match_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end
end

TriageScreen.main(System.argv())
