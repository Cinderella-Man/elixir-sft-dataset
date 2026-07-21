# keep_land.exs — the KEEP PATH (STATUS build item; docs/17 §6.3's missing half).
#
# Two situations produce a verified-but-blind-red unit that today dead-ends:
#   * a keep-class ROOT with a queued improvement (a candidate prompt that is
#     strictly more precise, but the root's blind solves are unreliable — e.g.
#     110_002's expiry hard spot), and
#   * an in-loop QUARANTINE (`logs/quarantine/<id>` — the accept path refused
#     to promote after a red blind re-screen).
#
# The sanctioned exception route (the 49 historical keeps) is: the TRIAGE JUDGE
# answers the entailment question, a HUMAN (Kamil) reviews, and a keep
# resolution row closes the gap. This tool mechanizes that route WITHOUT ever
# landing anything on its own authority:
#
#   --candidate <root> --prompt <file>
#       Stage the candidate prompt over the root's current files, run ONE blind
#       solve (the screen ledger gets the S6 evidence row either way).
#       GREEN → the candidate lands immediately (backup kept) — no keep needed.
#       RED   → the triage judge decides entailment vs the CANDIDATE prompt:
#               entailed     → a review packet is written to
#                              logs/keep_review/<root>/ and the row is
#                              `pending_kamil` — NOTHING lands;
#               not entailed → `rejected_gap` (the candidate itself is
#                              under-specified; packet saved for reference).
#
#   --approve <root>
#       Kamil's decision. Lands the packet's candidate prompt (backup kept),
#       appends the KEEP resolution row to logs/screen_triage.jsonl
#       ({task, sha, entailed, resolution: "kamil_keep_landed"}), and prints
#       the standing cascade commands.
#
#   --quarantine-sweep [--only "glob"]
#       Judge every logs/quarantine/<id> unit (prompt from the quarantined
#       files, failure from grade.json/reason.txt) → packet + `pending_kamil`.
#
#   --approve-quarantine <id>
#       Promotes the quarantined files (Cycle.promote — refuses if the dir
#       exists), appends the keep resolution row, removes the quarantine dir
#       (unblocking the idea), and prints the cascade commands.
#
#   --self-test    structural proof, no LLM: packet round-trip, approve landing,
#                  resolution row, ledger keying.
#
# Ledger: logs/keep_land.jsonl — one row per (root, candidate sha, gate sha).
# NEVER run concurrently with another prompt-writing tool.

alias GenTask.{Base, Config, Cycle, CycleLog, Evaluator}

defmodule KeepLand do
  @moduledoc false

  @ledger "keep_land.jsonl"
  @review_root "logs/keep_review"
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
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          candidate: :string,
          prompt: :string,
          approve: :string,
          quarantine_sweep: :boolean,
          approve_quarantine: :string,
          only: :string,
          self_test: :boolean,
          rescreen: :string
        ]
      )

    cfg = Config.new([])

    cond do
      opts[:self_test] -> self_test()
      opts[:candidate] -> candidate(cfg, opts[:candidate], opts[:prompt])
      opts[:rescreen] -> rescreen(cfg, opts[:rescreen])
      opts[:approve] -> approve(cfg, opts[:approve])
      opts[:quarantine_sweep] -> quarantine_sweep(cfg, opts[:only])
      opts[:approve_quarantine] -> approve_quarantine(cfg, opts[:approve_quarantine])
      true -> IO.puts("usage: see the header of scripts/keep_land.exs")
    end
  end

  # ── rescreen flow (S6 freshness for a hand-strengthened harness) ────────────

  # The candidate flow stages a NEW prompt; this stages nothing — the harness
  # changed (e.g. a hand-landed close_gaps candidate whose blind gate was
  # overruled by hand-read) and the current (prompt, harness) pair needs its
  # OWN blind evidence row. GREEN appends the S6 row and nothing lands; RED
  # goes through the same triage judge: entailed → keep packet (pending_kamil,
  # the sanctioned exception route), not entailed → the current prompt itself
  # under-specifies the failing demand — that family belongs in the prompt-fix
  # queue.
  defp rescreen(cfg, root) do
    dir = Path.join(cfg.tasks_dir, root)
    File.dir?(dir) || raise ArgumentError, "no such root: #{dir}"

    current = read_triplet(dir)
    prompt = current["prompt.md"]
    key = row_key(root, current)

    IO.puts("keep_land: #{root} — rescreen of the CURRENT pair (1 solver call)")

    case GenTask.Variations.blind_solution(root, prompt, cfg, "keep_land_rescreen") do
      {:error, reason} ->
        record(cfg, key, "error", "blind call failed: #{inspect(reason)}")
        IO.puts("  ERROR — blind call failed: #{inspect(reason)}")

      {:ok, blind_src} ->
        stage = Path.join(cfg.staging_dir, "keep_land_" <> root)
        Evaluator.stage!(stage, Map.put(current, "solution.ex", blind_src))
        grade = Evaluator.grade(stage, cfg)
        row = Base.screen_row(root, prompt, current["test_harness.exs"], grade, cfg.model)
        append_jsonl(Path.join(cfg.logs_dir, "screen_blind.jsonl"), row)

        case row do
          %{green: true} ->
            record(cfg, key, "rescreen_green", "blind solve green vs the current harness")
            IO.puts("  GREEN — S6 evidence row appended; nothing to land.")

          _ ->
            failing = row[:first_failure] || row["first_failure"] || "solver failed"
            IO.puts("  RED — #{first_line(failing)}")
            judge_and_packet(cfg, root, prompt, prompt, failing, key)
        end
    end
  end

  # ── candidate flow ──────────────────────────────────────────────────────────

  defp candidate(cfg, root, prompt_file) do
    prompt_file || raise ArgumentError, "--candidate needs --prompt <file>"
    dir = Path.join(cfg.tasks_dir, root)
    File.dir?(dir) || raise ArgumentError, "no such root: #{dir}"

    candidate_prompt = File.read!(prompt_file)
    current = read_triplet(dir)

    if candidate_prompt == current["prompt.md"],
      do: raise(ArgumentError, "candidate is byte-identical to the current prompt")

    files = Map.put(current, "prompt.md", candidate_prompt)
    key = row_key(root, files)

    IO.puts("keep_land: #{root} — blind-verifying the candidate prompt (1 solver call)")

    case GenTask.Variations.blind_solution(root, candidate_prompt, cfg, "keep_land_blind") do
      {:error, reason} ->
        record(cfg, key, "error", "blind call failed: #{inspect(reason)}")
        IO.puts("  ERROR — blind call failed: #{inspect(reason)}")

      {:ok, blind_src} ->
        stage = Path.join(cfg.staging_dir, "keep_land_" <> root)
        Evaluator.stage!(stage, Map.put(files, "solution.ex", blind_src))
        grade = Evaluator.grade(stage, cfg)
        row = Base.screen_row(root, candidate_prompt, files["test_harness.exs"], grade, cfg.model)
        append_jsonl(Path.join(cfg.logs_dir, "screen_blind.jsonl"), row)

        case row do
          %{green: true} ->
            land!(cfg, root, candidate_prompt)
            record(cfg, key, "landed_green", "blind solve green — no keep needed")
            IO.puts("  GREEN — candidate LANDED (backup kept). Run the cascade + commit.")
            print_cascade()

          _ ->
            failing = row[:first_failure] || row["first_failure"] || "solver failed"
            IO.puts("  RED — #{first_line(failing)}")
            judge_and_packet(cfg, root, candidate_prompt, current["prompt.md"], failing, key)
        end
    end
  end

  defp judge_and_packet(cfg, root, candidate_prompt, current_prompt, failing, key) do
    IO.puts("  judging entailment vs the CANDIDATE prompt (1 judge call)")

    case judge(cfg, root, candidate_prompt, failing) do
      {:error, reason} ->
        record(cfg, key, "error", "judge call failed: #{inspect(reason)}")
        IO.puts("  ERROR — judge call failed: #{inspect(reason)}")

      {:ok, verdict} ->
        packet = write_packet(root, candidate_prompt, current_prompt, failing, verdict)

        if verdict["entailed"] do
          record(cfg, key, "pending_kamil", "entailed keep candidate; packet #{packet}")

          IO.puts("""
            ENTAILED — the failing demand IS in the candidate prompt (judge quote:
            #{inspect(verdict["quote"])}). This is keep-class hardness, not a gap.
            Review packet: #{packet}
            To land: mix run scripts/keep_land.exs -- --approve #{root}
          """)
        else
          record(cfg, key, "rejected_gap", "judge: not entailed — #{verdict["reason"]}")

          IO.puts("""
            NOT ENTAILED — the candidate itself under-specifies this demand:
            #{verdict["reason"]}
            Missing contract: #{verdict["missing_contract"]}
            Packet saved for reference: #{packet}. Nothing landed.
          """)
        end
    end
  end

  # ── approve (Kamil) ─────────────────────────────────────────────────────────

  defp approve(cfg, root) do
    packet = Path.join(@review_root, root)
    verdict = Jason.decode!(File.read!(Path.join(packet, "verdict.json")))
    candidate_prompt = File.read!(Path.join(packet, "candidate_prompt.md"))

    verdict["entailed"] ||
      raise "packet verdict is NOT entailed — approving would land an under-specified prompt"

    land!(cfg, root, candidate_prompt)
    sha = CycleLog.content_sha(candidate_prompt)

    append_jsonl(Path.join(cfg.logs_dir, @triage_ledger), %{
      task: root,
      sha: sha,
      entailed: true,
      quote: verdict["quote"],
      reason: verdict["reason"],
      resolution: "kamil_keep_landed",
      resolved_by: "keep_land --approve",
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    record(cfg, %{root: root, sha: sha, gate_sha: gate_sha()}, "landed_keep", "Kamil approved")
    IO.puts("LANDED as a Kamil keep (resolution row appended). Run the cascade + commit:")
    print_cascade()
  end

  # ── quarantine flow ─────────────────────────────────────────────────────────

  defp quarantine_sweep(cfg, only) do
    dirs =
      Path.join([cfg.logs_dir, "quarantine", "*"])
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn d -> only == nil or matches_only?(Path.basename(d), only) end)

    IO.puts("keep_land quarantine sweep: #{length(dirs)} unit(s)")

    Enum.each(dirs, fn qdir ->
      id = Path.basename(qdir)
      prompt = File.read!(Path.join(qdir, "prompt.md"))
      failing = quarantine_failure(qdir)
      key = %{root: "quarantine_" <> id, sha: CycleLog.content_sha(prompt), gate_sha: gate_sha()}

      if done?(cfg, key) do
        IO.puts("  #{id}: already triaged at this sha")
      else
        case judge(cfg, id, prompt, failing) do
          {:error, reason} ->
            record(cfg, key, "error", "judge call failed: #{inspect(reason)}")

          {:ok, verdict} ->
            packet = write_packet("quarantine_" <> id, prompt, nil, failing, verdict)
            status = if verdict["entailed"], do: "pending_kamil", else: "rejected_gap"
            record(cfg, key, status, "packet #{packet}")

            IO.puts(
              "  #{id}: #{if verdict["entailed"], do: "ENTAILED (keep candidate)", else: "NOT entailed (template gap)"} — #{packet}"
            )
        end
      end
    end)
  end

  defp approve_quarantine(cfg, id) do
    packet = Path.join(@review_root, "quarantine_" <> id)
    verdict = Jason.decode!(File.read!(Path.join(packet, "verdict.json")))
    verdict["entailed"] || raise "packet verdict is NOT entailed — fix the generator instead"

    qdir = Path.join([cfg.logs_dir, "quarantine", id])
    files = read_triplet(qdir)
    {:ok, _} = Cycle.promote(cfg, id, files, nil)

    append_jsonl(Path.join(cfg.logs_dir, @triage_ledger), %{
      task: id,
      sha: CycleLog.content_sha(files["prompt.md"]),
      entailed: true,
      quote: verdict["quote"],
      reason: verdict["reason"],
      resolution: "kamil_keep_promoted_from_quarantine",
      resolved_by: "keep_land --approve-quarantine",
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    File.rm_rf!(qdir)
    IO.puts("PROMOTED from quarantine as a Kamil keep; quarantine dir removed (idea unblocked).")
    print_cascade()
  end

  # ── judge ───────────────────────────────────────────────────────────────────

  defp judge(cfg, id, prompt, failing) do
    user = """
    ## Task prompt (what the blind solver saw — the ONLY specification)

    #{prompt}

    ## Blind-solve failure (first failing test against the official harness)

    ```
    #{failing}
    ```

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

    case Cycle.generate(cfg, id, "keep_land_judge", @judge_persona, user, &validate_verdict/1) do
      {:ok, %{"verdict.json" => json}} -> {:ok, Jason.decode!(json)}
      {:error, reason} -> {:error, reason}
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

  # ── packet / landing plumbing ───────────────────────────────────────────────

  @doc false
  def write_packet(name, candidate_prompt, current_prompt, failing, verdict) do
    dir = Path.join(@review_root, name)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "candidate_prompt.md"), candidate_prompt)
    if current_prompt, do: File.write!(Path.join(dir, "current_prompt.md"), current_prompt)
    File.write!(Path.join(dir, "first_failure.txt"), failing <> "\n")
    File.write!(Path.join(dir, "verdict.json"), Jason.encode!(verdict) <> "\n")
    dir
  end

  defp land!(cfg, root, candidate_prompt) do
    dir = Path.join(cfg.tasks_dir, root)
    backup = Path.join([cfg.logs_dir, "keep_land_backup", root])
    File.mkdir_p!(backup)
    File.cp!(Path.join(dir, "prompt.md"), Path.join(backup, "prompt.md"))
    File.write!(Path.join(dir, "prompt.md"), candidate_prompt)
  end

  defp quarantine_failure(qdir) do
    grade =
      case File.read(Path.join(qdir, "grade.json")) do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, json} -> json |> Map.get("test_failures", []) |> List.first()
            _ -> nil
          end

        _ ->
          nil
      end

    cond do
      is_map(grade) -> "#{grade["test"]}: #{grade["message"]}"
      true -> File.read!(Path.join(qdir, "reason.txt"))
    end
  end

  defp read_triplet(dir) do
    for f <- ["prompt.md", "solution.ex", "test_harness.exs", "manifest.exs"],
        path = Path.join(dir, f),
        File.regular?(path),
        into: %{},
        do: {f, File.read!(path)}
  end

  defp print_cascade do
    IO.puts("""
      mix run scripts/resync_embeds.exs -- --wt-all --apply
      mix run scripts/resync_bugfix_embeds.exs -- --apply
      mix run scripts/resync_tfim_embeds.exs -- --apply
      mix run scripts/resync_adapt_embeds.exs -- --apply
      mix run scripts/resync_dedoc_embeds.exs -- --apply
      elixir scripts/check_embeds.exs
    """)
  end

  # ── ledger (rules 2 + 7) ────────────────────────────────────────────────────

  defp row_key(root, files) do
    %{
      root: root,
      sha: CycleLog.content_sha(files["prompt.md"] <> (files["test_harness.exs"] || "")),
      gate_sha: gate_sha()
    }
  end

  defp gate_sha do
    CycleLog.content_sha(
      File.read!(__ENV__.file) <> CycleLog.gate_sha([GenTask.Evaluator, GenTask.Prompts])
    )
  end

  defp done?(cfg, key) do
    case File.read(Path.join(cfg.logs_dir, @ledger)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.any?(fn line ->
          case Jason.decode(line) do
            {:ok, row} ->
              row["root"] == key.root and row["sha"] == key.sha and
                row["gate_sha"] == key.gate_sha and row["status"] != "error"

            _ ->
              false
          end
        end)

      _ ->
        false
    end
  end

  defp record(cfg, key, status, detail) do
    append_jsonl(
      Path.join(cfg.logs_dir, @ledger),
      Map.merge(key, %{
        status: status,
        detail: String.slice(detail, 0, 2000),
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    )
  end

  defp append_jsonl(path, row) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(row) <> "\n", [:append])
  end

  defp matches_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end

  defp first_line(text),
    do: text |> String.split("\n", trim: true) |> List.first() |> Kernel.||("")

  # ── self-test (structural, no LLM) ──────────────────────────────────────────

  defp self_test do
    root = Path.join(System.tmp_dir!(), "keep_land_st_#{System.unique_integer([:positive])}")
    tasks = Path.join(root, "tasks")
    logs = Path.join(root, "logs")
    task_dir = Path.join(tasks, "001_001_widget_01")
    File.mkdir_p!(task_dir)
    File.mkdir_p!(logs)

    File.write!(Path.join(task_dir, "prompt.md"), "OLD PROMPT\n")
    File.write!(Path.join(task_dir, "solution.ex"), "defmodule W do\nend\n")
    File.write!(Path.join(task_dir, "test_harness.exs"), "defmodule WT do\nend\n")

    cfg = %Config{tasks_dir: tasks, logs_dir: logs}

    verdict = %{
      "entailed" => true,
      "quote" => "the prompt says so",
      "reason" => "clearly entailed",
      "missing_contract" => ""
    }

    # Packet round-trip (into a sandboxed review root via cwd isolation is not
    # possible for the module attribute, so exercise the write into the REAL
    # @review_root under a throwaway name, then clean up).
    packet_name = "self_test_#{System.unique_integer([:positive])}"
    packet = write_packet(packet_name, "NEW PROMPT\n", "OLD PROMPT\n", "test x failed", verdict)

    checks = [
      {"packet holds all four files",
       Enum.sort(File.ls!(packet)) ==
         ["candidate_prompt.md", "current_prompt.md", "first_failure.txt", "verdict.json"]},
      {"packet verdict round-trips",
       Jason.decode!(File.read!(Path.join(packet, "verdict.json")))["entailed"] == true},
      {"landing writes the prompt and keeps a backup",
       (
         land!(cfg, "001_001_widget_01", File.read!(Path.join(packet, "candidate_prompt.md")))

         File.read!(Path.join(task_dir, "prompt.md")) == "NEW PROMPT\n" and
           File.read!(Path.join([logs, "keep_land_backup", "001_001_widget_01", "prompt.md"])) ==
             "OLD PROMPT\n"
       )},
      {"ledger keying: record then done?",
       (
         key = %{root: "001_001_widget_01", sha: "abc", gate_sha: gate_sha()}
         record(cfg, key, "pending_kamil", "test")
         done?(cfg, key) and not done?(cfg, %{key | sha: "other"})
       )},
      {"error rows do not close the key",
       (
         key = %{root: "err_root", sha: "abc", gate_sha: gate_sha()}
         record(cfg, key, "error", "boom")
         not done?(cfg, key)
       )}
    ]

    File.rm_rf!(packet)
    File.rm_rf!(root)

    for {label, ok?} <- checks,
        do: IO.puts("  #{if ok?, do: "ok ✓", else: "FAIL ✗"}  #{label}")

    if Enum.all?(checks, &elem(&1, 1)) do
      IO.puts("\nkeep_land self-test: OK ✓ (#{length(checks)} checks)")
    else
      IO.puts("\nkeep_land SELF-TEST FAILED")
      System.halt(1)
    end
  end
end

KeepLand.main(System.argv())
