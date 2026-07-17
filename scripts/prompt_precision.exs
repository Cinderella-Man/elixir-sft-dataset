# prompt_precision.exs — the T2.6 PROMPT-PRECISION instrument (STATUS queue,
# built 2026-07-17 on Kamil's go; lineage: the 2026-07-15 hand pilot that raised
# the 015 family to contract precision and the retro_audit.exs skeleton).
#
# For each `_01` root, ONE editor call proposes a precision-raised prompt.md:
# promises must equal tested behavior — add the observable contracts the
# harness pins but the prompt leaves unsaid (return values, literal message
# substrings, boundary rules, documented trigger seams), soften or drop
# promises nothing tests, and change as little prose as possible while keeping
# the task's framing and register. The proposal is then MACHINE-VETTED:
#
#   1. structural: the reply is a single fenced block (or `ALREADY PRECISE`);
#      every API token the old prompt named (`Mod.fun`, `fun/arity`) survives;
#      the new prompt is not suspiciously short.
#   2. blind verify: one independent prompt-only solve of the NEW prompt must
#      go green against the CURRENT harness (the same S6 gate the hand pilot
#      used; the evidence row is appended in the screen ledger's schema so the
#      freshness gate stays green after the write).
#
# Only then is prompt.md replaced (old prompt backed up first). A red blind
# solve DISCARDS the proposal (saved for review) and ledgers `needs_triage`.
# Child embeds are NOT cascaded here — run the standing resync gates after a
# batch (the summary names the commands), exactly like retro_audit.exs.
#
# Ledger: logs/prompt_precision.jsonl — one row per root per content+gate sha
# (HOW-WE-WORK rules 2 and 7: resumable; a repaired tool re-opens verdicts).
#
#   mix run scripts/prompt_precision.exs -- --self-test        # no LLM calls
#   mix run scripts/prompt_precision.exs -- --dry-run          # plan only
#   mix run scripts/prompt_precision.exs -- --limit 3          # PILOT (rule 9)
#   mix run scripts/prompt_precision.exs -- --only "006_*"     # scope by glob
#
# NEVER run concurrently with the nightly sweep or another prompt-writing tool.

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Prompts}

defmodule PromptPrecision do
  @moduledoc false

  @ledger "prompt_precision.jsonl"
  @backup_root "logs/prompt_precision_backup"
  @candidates_root "logs/prompt_precision_candidates"

  @persona """
  You are a contract-precision editor for an Elixir SFT dataset. You receive a
  task prompt, its reference solution, and its test harness. Rewrite ONLY the
  prompt so that its promises exactly match the tested contract:

  - ADD the observable behaviors the harness pins but the prompt leaves
    unsaid: return values and their exact shapes, literal message substrings,
    boundary rules (inclusive/exclusive, before/after counts), and any message
    or option the harness sends to the process.
  - SOFTEN or DROP promises that nothing tests and the solution does not keep.
  - NEVER describe implementation internals the harness cannot observe, never
    change the task's framing, register, or voice, and change as little prose
    as possible — surgical sentences, not a rewrite.
  - An independent solver must be able to pass the harness from your prompt
    alone. That is the bar your output is judged against.

  Reply with EXACTLY ONE file block and nothing else. To propose an edit,
  return the COMPLETE replacement prompt:

  <file path="prompt.md">
  ...full prompt.md content...
  </file>

  If the prompt already meets the bar and you have no surgical improvement,
  return instead:

  <file path="verdict.txt">
  ALREADY PRECISE
  </file>
  """

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [limit: :integer, only: :string, dry_run: :boolean, self_test: :boolean]
      )

    if opts[:self_test] do
      self_test()
    else
      run(opts)
    end
  end

  defp run(opts) do
    cfg = Config.new([])
    done = ledger_keys(cfg)

    {todo, skipped} =
      roots(cfg, opts[:only])
      |> Enum.map(&classify(&1, done))
      |> Enum.split_with(&(elem(&1, 0) == :todo))

    todo = if opts[:limit], do: Enum.take(todo, opts[:limit]), else: todo

    IO.puts(
      "prompt precision: #{length(todo)} root(s) to edit, " <>
        "#{Enum.count(skipped, &(elem(&1, 0) == :done))} already done at this " <>
        "content+gate, #{Enum.count(skipped, &(elem(&1, 0) == :bundle))} bundle-skipped" <>
        if(opts[:dry_run], do: " [DRY-RUN]", else: "")
    )

    if opts[:dry_run] do
      Enum.each(todo, fn {:todo, dir, _, _} -> IO.puts("  would edit: #{dir}") end)
    else
      results = Enum.map(todo, fn {:todo, dir, files, key} -> edit_root(dir, files, key, cfg) end)
      IO.puts("\nprompt precision summary: #{inspect(Enum.frequencies(results))}")

      if :improved in results do
        IO.puts("""
        IMPROVED prompts need their child embeds cascaded — run:
          mix run scripts/resync_embeds.exs -- --wt-all --apply
          mix run scripts/resync_bugfix_embeds.exs -- --apply
          mix run scripts/resync_tfim_embeds.exs -- --apply
          mix run scripts/resync_adapt_embeds.exs -- --apply
          elixir scripts/check_embeds.exs
        (prompt-only edits: no pair invalidation, no module-FIM gold impact).
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Enumeration + resume (retro_audit.exs skeleton)
  # ---------------------------------------------------------------------------

  defp roots(cfg, only) do
    "#{cfg.tasks_dir}/*_01"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(fn dir ->
      base = Path.basename(dir)

      match?({_n, ""}, Integer.parse(hd(String.split(base, "_")))) and
        (only == nil or matches_only?(base, only))
    end)
    |> Enum.sort()
  end

  defp matches_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end

  defp classify(dir, done) do
    files =
      for f <- ["prompt.md", "solution.ex", "test_harness.exs"],
          path = Path.join(dir, f),
          File.regular?(path),
          into: %{},
          do: {f, File.read!(path)}

    cond do
      map_size(files) < 3 -> {:incomplete, dir}
      EvalTask.Bundle.bundle?(files["solution.ex"]) -> {:bundle, dir}
      MapSet.member?(done, row_key(files)) -> {:done, dir}
      true -> {:todo, dir, files, row_key(files)}
    end
  end

  # Content shas + the gate sha (this script's own bytes + the modules whose
  # behavior the verdict depends on) — rule-7 corollary: editing this tool
  # re-opens every verdict it wrote.
  defp row_key(files) do
    CycleLog.content_sha(files["prompt.md"] <> files["solution.ex"] <> files["test_harness.exs"]) <>
      ":" <> gate_sha()
  end

  defp gate_sha do
    script = CycleLog.content_sha(File.read!(__ENV__.file))
    modules = CycleLog.gate_sha([Prompts, GenTask.Evaluator, GenTask.Reply])
    CycleLog.content_sha(script <> modules)
  end

  defp ledger_keys(cfg) do
    path = Path.join(cfg.logs_dir, @ledger)

    if File.regular?(path) do
      path
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, %{"key" => key, "outcome" => o}} when o != "error" -> [key]
          _ -> []
        end
      end)
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  # ---------------------------------------------------------------------------
  # Per-root cycle: propose → vet → blind-verify → write
  # ---------------------------------------------------------------------------

  defp edit_root(dir, files, key, cfg) do
    id = Path.basename(dir)
    IO.puts("\n=== #{id}")

    user = """
    ## The task prompt (prompt.md)

    #{files["prompt.md"]}

    ## The reference solution (solution.ex)

    ```elixir
    #{files["solution.ex"]}
    ```

    ## The test harness (test_harness.exs)

    ```elixir
    #{files["test_harness.exs"]}
    ```
    """

    case Cycle.generate(cfg, id, "prompt_precision", @persona, user, &validate_reply/1) do
      {:ok, %{"verdict.txt" => _}} ->
        record(cfg, id, key, "unchanged", "editor reports ALREADY PRECISE")
        IO.puts("  unchanged — already precise")
        :unchanged

      {:ok, %{"prompt.md" => raw}} ->
        new_prompt = String.trim_trailing(raw) <> "\n"

        case vet_structure(files["prompt.md"], new_prompt) do
          :ok ->
            blind_verify_and_write(dir, id, key, files, new_prompt, cfg)

          {:error, why} ->
            record(cfg, id, key, "needs_triage", "structural vet failed: #{why}")
            IO.puts("  REJECTED (structure): #{why}")
            :needs_triage
        end

      {:error, reason} ->
        record(cfg, id, key, "error", "editor call failed: #{inspect(reason)}")
        IO.puts("  ERROR: #{inspect(reason)}")
        :error
    end
  end

  @doc false
  # Reply contract (Cycle.generate hands validators the PARSED file map): one
  # `prompt.md` block with the full replacement, or a `verdict.txt` block
  # containing ALREADY PRECISE. Exposed for the self-test.
  def validate_reply(files) when is_map(files) do
    cond do
      String.trim(files["verdict.txt"] || "") == "ALREADY PRECISE" ->
        :ok

      is_binary(files["prompt.md"]) and String.trim(files["prompt.md"]) != "" ->
        :ok

      true ->
        {:error, "reply must be one prompt.md file block or a verdict.txt ALREADY PRECISE block"}
    end
  end

  @doc false
  # Structural vetting, LLM-free. Exposed for the self-test.
  def vet_structure(old_prompt, new_prompt) do
    old_tokens = api_tokens(old_prompt)
    missing = Enum.reject(old_tokens, &String.contains?(new_prompt, &1))

    cond do
      String.trim(new_prompt) == "" ->
        {:error, "empty prompt"}

      byte_size(new_prompt) < (byte_size(old_prompt) * 6) |> div(10) ->
        {:error, "suspiciously short (#{byte_size(new_prompt)}B vs #{byte_size(old_prompt)}B)"}

      missing != [] ->
        {:error, "dropped API tokens: #{Enum.join(Enum.take(missing, 5), ", ")}"}

      new_prompt == old_prompt ->
        {:error, "reply is byte-identical to the old prompt (should be ALREADY PRECISE)"}

      true ->
        :ok
    end
  end

  # `Mod.fun/arity`, `Mod.fun`, and `fun/arity` tokens the old prompt names —
  # the contract surface that must survive an edit. (The self-test bit on the
  # first version of this regex, which missed the dotted+arity form.)
  defp api_tokens(prompt) do
    Regex.scan(
      ~r/`((?:[A-Z]\w*(?:\.\w+[?!]?)+(?:\/\d+)?)|(?:\w+[?!]?\/\d+))`/,
      prompt,
      capture: :all_but_first
    )
    |> List.flatten()
    |> Enum.uniq()
  end

  defp blind_verify_and_write(dir, id, key, files, new_prompt, cfg) do
    shape = if EvalTask.Bundle.bundle?(files["solution.ex"]), do: :multifile, else: :single
    {system, user} = Prompts.base_solve(new_prompt, shape)

    case Cycle.generate(
           cfg,
           id,
           "precision_verify",
           system,
           user,
           &GenTask.Reply.validate_answer/1
         ) do
      {:ok, %{"solution.ex" => candidate}} when is_binary(candidate) ->
        case grade_candidate(dir, cfg, candidate) do
          {:green, grade} ->
            write!(dir, id, new_prompt, grade, cfg)
            record(cfg, id, key, "improved", "blind-verified green; prompt replaced")

            IO.puts(
              "  IMPROVED — blind solve green (#{grade["tests_passed"]}/#{grade["tests_total"]})"
            )

            :improved

          {:red, why} ->
            save_candidate(id, new_prompt, cfg)
            record(cfg, id, key, "needs_triage", "blind solve RED on proposal: #{why}")
            IO.puts("  REJECTED (blind red): #{why}")
            :needs_triage
        end

      {:ok, other} ->
        record(
          cfg,
          id,
          key,
          "error",
          "solver reply lacked solution.ex: #{inspect(Map.keys(other))}"
        )

        IO.puts("  ERROR (solver reply shape)")
        :error

      {:error, reason} ->
        record(cfg, id, key, "error", "blind solver call failed: #{inspect(reason)}")
        IO.puts("  ERROR (solver): #{inspect(reason)}")
        :error
    end
  end

  defp grade_candidate(dir, cfg, candidate) do
    path =
      Path.join(
        System.tmp_dir!(),
        "precision_#{System.pid()}_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, candidate)

    try do
      case Evaluator.grade(dir, cfg, path) do
        {:ok, json} ->
          if Evaluator.green?(json) do
            {:green, json}
          else
            {:red, first_failure(json) || "not green"}
          end

        :timeout_or_crash ->
          {:red, "eval timed out or crashed"}
      end
    after
      File.rm(path)
    end
  end

  defp first_failure(json) do
    case json["test_failures"] do
      [%{"test" => t} | _] -> t
      _ -> nil
    end
  end

  defp write!(dir, id, new_prompt, grade, cfg) do
    backup = Path.join(@backup_root, id)
    File.mkdir_p!(backup)
    File.cp!(Path.join(dir, "prompt.md"), Path.join(backup, "prompt.md"))
    File.write!(Path.join(dir, "prompt.md"), new_prompt)

    # S6 evidence in the screen ledger's schema — the blind verify above IS a
    # prompt-only solve against the current harness, so the freshness gate
    # stays green for the new prompt sha.
    entry = %{
      task: id,
      sha: CycleLog.content_sha(new_prompt),
      harness_sha: CycleLog.content_sha(File.read!(Path.join(dir, "test_harness.exs"))),
      green: true,
      compiled: true,
      tests_passed: grade["tests_passed"],
      tests_failed: 0,
      tests_total: grade["tests_total"],
      first_failure: nil,
      model: cfg.model,
      source: "prompt_precision",
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(
      Path.join(cfg.logs_dir, "screen_blind.jsonl"),
      Jason.encode!(entry) <> "\n",
      [:append]
    )
  end

  defp save_candidate(id, new_prompt, _cfg) do
    File.mkdir_p!(@candidates_root)
    File.write!(Path.join(@candidates_root, "#{id}.md"), new_prompt)
  end

  defp record(cfg, id, key, outcome, detail) do
    row = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      task: id,
      key: key,
      gate_sha: gate_sha(),
      outcome: outcome,
      detail: detail
    }

    File.write!(Path.join(cfg.logs_dir, @ledger), Jason.encode!(row) <> "\n", [:append])
  end

  # ---------------------------------------------------------------------------
  # Self-test — prove the vetting layer is non-vacuous. No LLM calls.
  # ---------------------------------------------------------------------------

  defp self_test do
    old = """
    Write me a module called `Widget` with `Widget.run/1` and `Widget.stop/0`.
    Call `Widget.run(x)` to start.
    """

    checks = [
      {"ALREADY PRECISE verdict block accepted",
       validate_reply(%{"verdict.txt" => "ALREADY PRECISE\n"}) == :ok},
      {"prompt.md block accepted", validate_reply(%{"prompt.md" => "new prompt\n"}) == :ok},
      {"empty parse rejected", match?({:error, _}, validate_reply(%{}))},
      {"dropped API token rejected",
       match?(
         {:error, "dropped API tokens:" <> _},
         vet_structure(old, String.replace(old, "`Widget.stop/0`", "`stop`") <> "x")
       )},
      {"short prompt rejected",
       match?(
         {:error, "suspiciously short" <> _},
         vet_structure(old, "`Widget.run/1` `Widget.stop/0`")
       )},
      {"byte-identical rejected",
       match?({:error, "reply is byte-identical" <> _}, vet_structure(old, old))},
      {"good edit passes", vet_structure(old, old <> "It returns `:ok`.\n") == :ok}
    ]

    failed = Enum.reject(checks, fn {_, ok} -> ok end)

    Enum.each(checks, fn {name, ok} ->
      IO.puts("  self-test #{if ok, do: "ok ", else: "FAIL"} — #{name}")
    end)

    if failed == [] do
      IO.puts("self-test OK ✓ (#{length(checks)}/#{length(checks)})")
    else
      IO.puts("self-test FAILED (#{length(failed)} of #{length(checks)})")
      System.halt(1)
    end
  end
end

unless System.get_env("SCRIPTS_NO_AUTORUN"), do: PromptPrecision.main(System.argv())
