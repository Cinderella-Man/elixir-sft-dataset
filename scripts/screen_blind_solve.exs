# screen_blind_solve.exs — the blind re-solve SCREEN (docs/10 §1.1, R4a).
#
# For every `_01` task (shapes :single and :multifile) call the solver with the
# task's prompt.md ONLY (never the harness), grade the candidate against the real
# harness, and record the verdict. One attempt, NO repair loop — repairing against
# the failing tests would defeat the point, which is:
#
#     a task is well-specified iff an independent solver can go green from the
#     prompt alone.
#
# A failure QUARANTINES (ledger + report), never deletes: it means EITHER an
# under-specified prompt (hidden requirement — the common case, see docs/10 §1.1)
# OR a too-weak solver. A human (or a stronger model) decides which.
#
# The ledger `logs/screen_blind.jsonl` is content-keyed by sha256(prompt.md), so:
#   * interrupted runs RESUME for free (screened tasks are skipped),
#   * fixing a prompt automatically re-screens it on the next run.
#
# Usage:
#   mix run scripts/screen_blind_solve.exs                     # everything unscreened
#   mix run scripts/screen_blind_solve.exs --only "001_001*"   # name filter (glob, comma-ok)
#   mix run scripts/screen_blind_solve.exs --limit 10          # first N unscreened
#   mix run scripts/screen_blind_solve.exs --model sonnet      # solver model override
#   mix run scripts/screen_blind_solve.exs --rescreen          # ignore ledger hits
#   mix run scripts/screen_blind_solve.exs --report            # NO calls: summarize ledger
#
# Cost: one `claude -p` call per unscreened task (299 for the full corpus), run
# SEQUENTIALLY (the transport already handles usage-window waits and backoff).
# Canaries (predicted to fail — if they PASS, the screen is too weak):
#   001_001_rate_limiter_01 (`:infinity` hidden contract, docs/10 §1.1)
#   016_001_paginated_list_endpoint_01 (non-numeric param fallback never stated)

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Prompts, Reply}

defmodule ScreenBlind do
  @moduledoc false

  @ledger "screen_blind.jsonl"

  def main(argv) do
    # `mix run script.exs -- --report` leaves the literal `--` in System.argv, and
    # OptionParser treats it as an end-of-options terminator — silently dropping every
    # flag and turning a report-only invocation into a PAID screen run. Accept both
    # invocations by dropping a leading `--` (same fix as resync_tfim_embeds.exs).
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          only: :string,
          limit: :integer,
          model: :string,
          rescreen: :boolean,
          report: :boolean
        ]
      )

    cfg = Config.new([])
    cfg = if opts[:model], do: %{cfg | model: opts[:model]}, else: cfg

    if opts[:report] do
      report(cfg)
    else
      screen(cfg, opts)
    end
  end

  defp screen(cfg, opts) do
    tasks =
      EvalTask.Discovery.all()
      |> Enum.filter(&(&1.shape in [:single, :multifile] and &1.found))
      # repair_ prompts are frozen captured evidence (docs/13 §1.5): they embed
      # a failed attempt + its report, so "blind-solvable from the prompt" is
      # not a property they can have. Excluding them here keeps a bare
      # `screen_blind_solve` run from burning calls on unscreenable dirs.
      |> Enum.reject(&String.starts_with?(&1.name, "repair_"))
      |> Enum.filter(&match_only?(&1.name, opts[:only]))

    {todo, cached} =
      if opts[:rescreen],
        do: {tasks, []},
        else: Enum.split_with(tasks, &(cached_verdict(cfg, &1) == :miss))

    todo = if opts[:limit], do: Enum.take(todo, opts[:limit]), else: todo

    IO.puts(
      "Blind-solve screen: #{length(todo)} task(s) to screen " <>
        "(#{length(cached)} already in the ledger; --rescreen to redo) — " <>
        "model=#{cfg.model}, sequential, ~1 call each"
    )

    {results, aborted?} =
      todo
      |> Enum.with_index(1)
      |> Enum.reduce_while({[], false}, fn {task, i}, {acc, _} ->
        IO.write("[#{i}/#{length(todo)}] #{task.name} ... ")
        entry = screen_one(cfg, task)
        IO.puts(verdict_text(entry))

        # Only reachable when GEN_USAGE_MAX_WAIT_MS > 0 (default is wait-forever):
        # tokens did not come back within the cap, so every remaining task would
        # hit the same wall — stop the sweep instead of churning. The ledger only
        # counts conclusive verdicts, so re-running resumes exactly here.
        if usage_exhausted?(entry),
          do: {:halt, {[entry | acc], true}},
          else: {:cont, {[entry | acc], false}}
      end)

    results = Enum.reverse(results)

    if aborted? do
      IO.puts("""

      !! Token/credit allowance did not return within GEN_USAGE_MAX_WAIT_MS — sweep stopped.
         Re-run the same command to resume (screened tasks are skipped via the ledger).
      """)
    end

    summarize(results)
  end

  @usage_exhausted inspect({:usage_limit, :exhausted})
  defp usage_exhausted?(entry), do: entry[:error] == @usage_exhausted

  defp screen_one(cfg, task) do
    prompt = File.read!(Path.join(task.dir, "prompt.md"))
    {system, user} = Prompts.base_solve(prompt, task.shape)

    validator =
      case task.shape do
        :multifile -> &Reply.validate_bundle_answer/1
        _ -> &Reply.validate_answer/1
      end

    entry =
      case Cycle.generate(cfg, task.name, "screen_blind", system, user, validator) do
        {:ok, answer} ->
          candidate = assemble_candidate(task.shape, answer)
          save_candidate(cfg, task, prompt, candidate)
          grade_candidate(cfg, task, candidate)

        {:error, reason} ->
          # A transport/contract failure is NOT a verdict on the prompt — record it
          # as :error so `--report` separates it from real reds.
          %{green: nil, error: inspect(reason)}
      end

    entry =
      Map.merge(entry, %{
        task: task.name,
        sha: CycleLog.content_sha(prompt),
        # The blind property belongs to the (prompt, harness) PAIR: a later
        # harness edit invalidates this verdict. check_screen_freshness.exs
        # compares this sha against the harness on disk (STATUS T1.2).
        harness_sha: harness_sha(task),
        model: cfg.model,
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    append_ledger(cfg, entry)
    entry
  end

  # A single-shape reply is the solution.ex content verbatim. A multifile reply
  # is one <file> block per app source file (the solver cannot know the repo's
  # inner-bundle convention) — assemble those blocks into the bundle form the
  # evaluator's multifile runner expects. A solver that inlined everything into
  # solution.ex anyway is passed through unchanged.
  defp assemble_candidate(:multifile, answer) do
    case answer do
      %{"solution.ex" => src} ->
        src

      files ->
        files
        |> Enum.sort_by(fn {path, _} -> path end)
        |> Enum.map_join("\n", fn {path, content} ->
          "<file path=\"#{path}\">\n#{String.trim_trailing(content)}\n</file>"
        end)
    end
  end

  defp assemble_candidate(_shape, answer), do: answer["solution.ex"]

  # Keep the blind candidate for triage: a red's ledger entry holds only a
  # 200-char failure snippet, and diagnosing WHY an independent solver failed
  # (solver slip vs prompt gap) usually needs the full source. Keyed by prompt
  # sha like the ledger, so re-screens of a fixed prompt don't overwrite the
  # candidate that failed against the old prompt.
  defp save_candidate(cfg, task, prompt, candidate_src) do
    dir = Path.join(cfg.logs_dir, "screen_candidates")
    File.mkdir_p!(dir)
    sha8 = String.slice(CycleLog.content_sha(prompt), 0, 8)
    File.write!(Path.join(dir, "#{task.name}__#{sha8}.ex"), candidate_src)
  end

  defp grade_candidate(cfg, task, candidate_src) do
    path =
      Path.join(
        System.tmp_dir!(),
        "screen_#{System.pid()}_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, candidate_src)

    try do
      case Evaluator.grade(task.dir, cfg, path) do
        {:ok, json} ->
          entry = %{
            green: Evaluator.green?(json),
            compiled: json["compiled"] == true,
            tests_passed: json["tests_passed"] || 0,
            tests_failed: json["tests_failed"] || 0,
            tests_total: json["tests_total"] || 0,
            first_failure: first_failure(json)
          }

          # F7-B (STATUS): an eval that failed because the ENVIRONMENT is
          # missing (e.g. the runner's "Postgres is required for this task but
          # is not reachable" raise) says nothing about the prompt — record it
          # like a transport error (green: nil), never as a RED verdict.
          if environmental?(entry.first_failure),
            do: %{green: nil, error: "environmental: " <> entry.first_failure},
            else: entry

        :timeout_or_crash ->
          %{green: false, compiled: false, first_failure: "eval timed out or crashed"}
      end
    after
      File.rm(path)
    end
  end

  defp environmental?(nil), do: false

  defp environmental?(text),
    do: String.contains?(text, "required for this task but is not reachable")

  defp first_failure(json) do
    case json["test_failures"] do
      [%{"test" => t, "message" => m} | _] -> "#{t}: #{String.slice(m || "", 0, 200)}"
      _ -> if json["compiled"] == true, do: nil, else: first_compile_error(json)
    end
  end

  defp first_compile_error(json) do
    case json["compile_errors"] do
      [%{"message" => m} | _] -> "compile: #{String.slice(m, 0, 200)}"
      _ -> "compile failed"
    end
  end

  # ── ledger ──────────────────────────────────────────────────────────────────

  defp ledger_path(cfg), do: Path.join(cfg.logs_dir, @ledger)

  defp harness_sha(task) do
    path = Path.join(task.dir, "test_harness.exs")
    if File.regular?(path), do: CycleLog.content_sha(File.read!(path))
  end

  defp append_ledger(cfg, entry) do
    File.mkdir_p!(cfg.logs_dir)
    File.write!(ledger_path(cfg), Jason.encode!(entry) <> "\n", [:append])
  end

  # A task counts as screened iff the ledger has a CONCLUSIVE entry (green true or
  # false — transport errors don't count) for its CURRENT prompt content.
  defp cached_verdict(cfg, task) do
    sha = CycleLog.content_sha(File.read!(Path.join(task.dir, "prompt.md")))

    case File.read(ledger_path(cfg)) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(:miss, fn line, acc ->
          case Jason.decode(line) do
            {:ok, %{"task" => t, "sha" => ^sha, "green" => g}}
            when t == task.name and is_boolean(g) ->
              {:ok, g}

            _ ->
              acc
          end
        end)

      {:error, _} ->
        :miss
    end
  end

  # ── reporting ───────────────────────────────────────────────────────────────

  defp verdict_text(%{green: true}), do: "GREEN"
  defp verdict_text(%{green: false} = e), do: "RED (#{e[:first_failure] || "failed"})"
  defp verdict_text(%{error: reason}), do: "ERROR (#{reason})"

  defp summarize([]), do: IO.puts("\nNothing screened.")

  defp summarize(results) do
    green = Enum.count(results, &(&1.green == true))
    red = Enum.filter(results, &(&1.green == false))
    errors = Enum.filter(results, &is_nil(&1.green))

    IO.puts("""

    === BLIND-SOLVE SCREEN SUMMARY ===
      screened: #{length(results)}   green: #{green}   RED: #{length(red)}   transport errors: #{length(errors)}
    """)

    if red != [] do
      IO.puts("  QUARANTINE (prompt under-specified OR solver too weak — human review):")
      Enum.each(red, &IO.puts("    - #{&1.task}: #{&1[:first_failure] || "failed"}"))
    end

    if errors != [],
      do: IO.puts("  errors (re-run to retry): #{Enum.map_join(errors, ", ", & &1.task)}")
  end

  # Summarize the whole ledger without any calls (latest entry per task wins).
  defp report(cfg) do
    case File.read(ledger_path(cfg)) do
      {:error, _} ->
        IO.puts("No ledger at #{ledger_path(cfg)} — run the screen first.")

      {:ok, content} ->
        latest =
          content
          |> String.split("\n", trim: true)
          |> Enum.flat_map(fn line ->
            case Jason.decode(line) do
              {:ok, e} -> [e]
              _ -> []
            end
          end)
          |> Enum.reduce(%{}, fn e, acc -> Map.put(acc, e["task"], e) end)

        entries = Map.values(latest)
        green = Enum.count(entries, &(&1["green"] == true))
        red = Enum.filter(entries, &(&1["green"] == false))

        IO.puts(
          "Ledger: #{map_size(latest)} task(s) screened — green #{green}, RED #{length(red)}"
        )

        Enum.each(red, fn e ->
          IO.puts("  - #{e["task"]} (#{e["model"]}): #{e["first_failure"] || "failed"}")
        end)
    end
  end

  defp match_only?(_name, nil), do: true

  defp match_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end
end

ScreenBlind.main(System.argv())
