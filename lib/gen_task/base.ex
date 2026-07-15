defmodule GenTask.Base do
  @moduledoc """
  The base generator (see `docs/04-task-generation-loop.md` §8).

  For one todo idea it runs two blind `claude -p` calls — **Step A** turns the idea
  into `prompt.md` + `test_harness.exs`, **Step B** solves that prompt (seeing the
  prompt *only*, never the tests) into `solution.ex` — then drives the shared cycle
  (`GenTask.Cycle`) and, if accepted, promotes the triplet to
  `tasks/NNN_001_slug_01/` behind the safety guard.

  `run/2` returns a single outcome map (see `GenTask.Cycle.outcome/1`); when accepted
  its `:seed` is a task reference the caller uses to chain variations and FIM.
  """

  require Logger

  alias GenTask.{Catalog, Config, Cycle, CycleLog, Evaluator, GateLog, Reply, Prompts, Variations}

  @type seed :: %{
          num: pos_integer(),
          name: String.t(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Generate, cycle, and (if accepted) promote the base task for `idea`."
  @spec run(Catalog.Idea.t(), Config.t()) :: map()
  def run(%Catalog.Idea{} = idea, %Config{} = cfg) do
    if quarantined?(cfg, idea.task_id) do
      Logger.warning("BASE #{idea.task_id}: quarantined, awaiting triage — skipping")

      Cycle.outcome(
        id: idea.task_id,
        kind: :base,
        num: idea.num,
        name: idea.name,
        status: :skipped,
        reason: "quarantined by the accept-time blind re-screen — triage logs/quarantine/ first"
      )
    else
      do_run(idea, cfg)
    end
  end

  defp do_run(%Catalog.Idea{} = idea, %Config{} = cfg) do
    handle = CycleLog.open(cfg, idea.task_id)
    Logger.info("BASE #{idea.task_id}: #{idea.name}")

    outcome =
      try do
        generate(idea, cfg)
      rescue
        e ->
          Logger.error(
            "base #{idea.task_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__)
          )

          Cycle.outcome(
            id: idea.task_id,
            kind: :base,
            num: idea.num,
            name: idea.name,
            status: :error,
            reason: Exception.message(e)
          )
      end

    CycleLog.close(handle, close_of(outcome.status))
    outcome
  end

  defp generate(idea, cfg) do
    {sys_a, user_a} = Prompts.base_task(%{num: idea.num, name: idea.name, desc: idea.desc})

    with {:ok, task_files} <-
           gen(cfg, idea.task_id, "base_task", sys_a, user_a, &Reply.validate_task/1),
         {sys_b, user_b} = Prompts.base_solve(task_files["prompt.md"]),
         {:ok, answer} <-
           gen(cfg, idea.task_id, "base_solve", sys_b, user_b, &Reply.validate_answer/1) do
      files = %{
        "prompt.md" => task_files["prompt.md"],
        "test_harness.exs" => task_files["test_harness.exs"],
        "solution.ex" => answer["solution.ex"]
      }

      ctx = %{
        dir: Path.join(cfg.staging_dir, idea.task_id),
        mutant_dir: Path.join(cfg.staging_dir, idea.task_id <> "_mut"),
        id: idea.task_id
      }

      result = Cycle.run(files, ctx, cfg)
      stats = Cycle.grade_stats(result.grade)

      if result.status == :accepted do
        case blind_rescreen(idea, result, cfg) do
          :promote ->
            _ = Cycle.promote(cfg, idea.task_id, result.files, :base)
            base_outcome(idea, :accepted, result, stats, seed(idea, result.files))

          {:quarantine, why} ->
            base_outcome(idea, :quarantined, result, stats, nil, why)

          {:error, reason} ->
            base_outcome(idea, :error, result, stats, nil, reason)
        end
      else
        base_outcome(
          idea,
          :rejected,
          result,
          stats,
          nil,
          result.reason || Cycle.reason_for(result.grade)
        )
      end
    else
      {:error, reason} ->
        Logger.error("base #{idea.task_id}: generation failed: #{inspect(reason)}")

        Cycle.outcome(
          id: idea.task_id,
          kind: :base,
          num: idea.num,
          name: idea.name,
          status: :error,
          reason: inspect(reason)
        )
    end
  end

  defp base_outcome(idea, status, result, stats, seed, reason \\ nil) do
    Cycle.outcome(
      id: idea.task_id,
      kind: :base,
      num: idea.num,
      name: idea.name,
      status: status,
      attempts: result.attempts,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      mutant_failed: result.mutant_failed,
      mutation: result.mutation,
      reason: reason,
      seed: seed
    )
  end

  defp seed(idea, files) do
    %{num: idea.num, name: idea.name, slug: idea.slug, b: 1, task_id: idea.task_id, files: files}
  end

  # Generate + parse + contract-validate, with one reminder retry on a contract miss
  # (shared shape — see Cycle.generate/7).
  defp gen(cfg, id, step, system, user, validator) do
    Cycle.generate(cfg, id, step, system, user, validator)
  end

  defp close_of(:accepted), do: :ok
  defp close_of(_), do: :error

  # ------------------------------------------------------------------
  # T1.1 — §5.2.1 accept-time blind re-screen (behind GEN_BLIND_RESCREEN)
  # ------------------------------------------------------------------
  #
  # A base accepted with attempts > 1 was fixed by a model that SAW the harness
  # failure report, so acceptance proves nothing about the prompt alone (6 of 22
  # retro-screened repaired accepts had shipped prompt↔harness gaps — docs/15,
  # 2026-07-13). One independent blind re-solve of the FINAL prompt against the
  # FINAL harness runs before promotion: GREEN promotes with an S6 evidence row;
  # RED quarantines the whole triplet for triage — never silent promotion.
  # Attempt-1 accepts are already blind by construction (Step B never sees the
  # harness), so they promote directly with no extra call.

  @doc "Whether an accepted base must pass the blind re-screen before promotion."
  @spec rescreen?(Config.t(), non_neg_integer()) :: boolean()
  def rescreen?(%Config{blind_rescreen: false}, _attempts), do: false
  def rescreen?(%Config{}, attempts), do: attempts > 1

  defp blind_rescreen(idea, result, cfg) do
    cond do
      not cfg.blind_rescreen ->
        GateLog.skip(
          cfg,
          idea.task_id,
          :base,
          :blind_rescreen,
          "GEN_BLIND_RESCREEN=0 — gate DARK (T1.1 built, awaiting Kamil's sign-off; " <>
            "docs/12 §5.5 row 10)"
        )

        :promote

      result.attempts == 1 ->
        GateLog.pass(
          cfg,
          idea.task_id,
          :base,
          :blind_rescreen,
          "not required — an attempt-1 accept is blind by construction " <>
            "(the solver never saw the harness)"
        )

        :promote

      true ->
        GateLog.applying(
          cfg,
          idea.task_id,
          :base,
          :blind_rescreen,
          "accepted after #{result.attempts} attempts — one independent prompt-only solve"
        )

        outcome = run_rescreen(idea, result, cfg)

        case outcome do
          :promote ->
            GateLog.pass(
              cfg,
              idea.task_id,
              :base,
              :blind_rescreen,
              "independent blind solve went green against the final harness"
            )

          {:quarantine, why} ->
            GateLog.fail(cfg, idea.task_id, :base, :blind_rescreen, why)

          {:error, reason} ->
            GateLog.skip(
              cfg,
              idea.task_id,
              :base,
              :blind_rescreen,
              "environmental failure, no verdict (F7 rule): " <> reason
            )
        end

        outcome
    end
  end

  defp run_rescreen(idea, result, cfg) do
    prompt = result.files["prompt.md"]
    harness = result.files["test_harness.exs"]

    case Variations.blind_solution(idea.task_id, prompt, cfg, "base_blind_rescreen") do
      {:ok, blind_src} ->
        dir =
          Evaluator.stage!(Path.join(cfg.staging_dir, idea.task_id <> "_rescreen"), %{
            "prompt.md" => prompt,
            "test_harness.exs" => harness,
            "solution.ex" => blind_src
          })

        grade = Evaluator.grade(dir, cfg)
        row = screen_row(idea.task_id, prompt, harness, grade, cfg.model)
        append_screen_row(cfg, row)

        case row do
          %{green: true} ->
            Logger.info("BASE #{idea.task_id}: accept-time blind re-screen GREEN")
            :promote

          %{green: nil} ->
            # F7: an environmental failure says nothing about the prompt — it
            # must never become a verdict. The base errors and re-runs later.
            {:error, "blind re-screen environmental: " <> (row[:error] || "unknown")}

          %{green: false} ->
            why =
              "accept-time blind re-screen RED: " <>
                (row[:first_failure] || "blind solve failed the final harness")

            quarantine!(cfg, idea.task_id, result.files, blind_src, grade, why)
            {:quarantine, why}
        end

      {:error, reason} ->
        # The transport already rode out token windows and retried transients;
        # a hard failure here errors the base (idea re-runs on a later pass).
        {:error, "blind re-screen call failed: " <> inspect(reason)}
    end
  end

  # An S6 evidence row in the EXACT screen_blind.jsonl schema (task + prompt
  # `sha` + `harness_sha` keys — check_screen_freshness matches on the pair),
  # with `source` marking in-loop provenance. Environmental failures record
  # `green: nil` (the F7 rule), mirroring scripts/screen_blind_solve.exs.
  @doc false
  @spec screen_row(String.t(), String.t(), String.t(), term(), String.t()) :: map()
  def screen_row(task_id, prompt, harness, grade, model) do
    base = %{
      task: task_id,
      sha: CycleLog.content_sha(prompt),
      harness_sha: CycleLog.content_sha(harness),
      model: model,
      source: "accept_time_rescreen",
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case grade do
      {:ok, json} ->
        entry =
          Map.merge(base, %{
            green: Evaluator.green?({:ok, json}),
            compiled: json["compiled"] == true,
            tests_passed: json["tests_passed"] || 0,
            tests_failed: json["tests_failed"] || 0,
            tests_total: json["tests_total"] || 0,
            first_failure: first_failure(json)
          })

        if environmental?(entry.first_failure),
          do: Map.merge(base, %{green: nil, error: "environmental: " <> entry.first_failure}),
          else: entry

      :timeout_or_crash ->
        Map.merge(base, %{
          green: false,
          compiled: false,
          first_failure: "eval timed out or crashed"
        })
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

  defp append_screen_row(cfg, row) do
    File.mkdir_p!(cfg.logs_dir)

    File.write!(
      Path.join(cfg.logs_dir, "screen_blind.jsonl"),
      Jason.encode!(row) <> "\n",
      [:append]
    )
  end

  # The full evidence a triager needs, in one dir: the accepted triplet, the
  # blind candidate, its grade, and the reason. The quarantine dir also blocks
  # the idea from re-entering the loop (see `run/2`) until it is triaged away.
  @doc false
  @spec quarantine!(Config.t(), String.t(), map(), String.t(), term(), String.t()) :: :ok
  def quarantine!(cfg, task_id, files, blind_src, grade, why) do
    dir = Path.join([cfg.logs_dir, "quarantine", task_id])
    File.mkdir_p!(dir)

    for {name, body} <- files, do: File.write!(Path.join(dir, name), body)
    File.write!(Path.join(dir, "blind_candidate.ex"), blind_src)
    File.write!(Path.join(dir, "reason.txt"), why <> "\n")

    grade_body =
      case grade do
        {:ok, json} -> Jason.encode!(json)
        other -> inspect(other)
      end

    File.write!(Path.join(dir, "grade.json"), grade_body <> "\n")
    Logger.warning("BASE #{task_id}: QUARANTINED — #{why}")
    :ok
  end

  defp quarantined?(cfg, task_id),
    do: File.dir?(Path.join([cfg.logs_dir, "quarantine", task_id]))
end
