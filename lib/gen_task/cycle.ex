defmodule GenTask.Cycle do
  @moduledoc """
  The shared task cycle (see `docs/04-task-generation-loop.md` §6).

  A base task and each variation are full tasks that flow through one scaffold:
  stage the triplet, grade it, and accept only when it is **green AND** a raise-mutant
  makes the harness fail (the mutation gate). On rejection, build a repair report and
  ask the (injectable) fixer to edit `solution.ex` and/or `test_harness.exs` — never
  `prompt.md` — then re-grade, up to `cfg.max_retries` times.

  This module also hosts the small pieces of *generation plumbing* shared by
  `GenTask.Base`, `GenTask.Variations`, and `GenTask.Fim`: the usage-logged Opus
  call (`opus/5`), the safety-guarded promotion (`promote/3`), and helpers that turn a
  grade into terminal/ledger fields (`grade_stats/1`, `reason_for/1`, `outcome/1`).
  """

  require Logger

  alias GenTask.{Config, CycleLog, Evaluator, Mutation, Prompts, Reply}

  @type files :: %{String.t() => String.t()}
  @type ctx :: %{dir: String.t(), mutant_dir: String.t(), id: String.t()}
  @type result :: %{
          status: :accepted | :rejected,
          files: files(),
          grade: Evaluator.grade(),
          attempts: pos_integer(),
          mutant_failed: boolean(),
          mutation: String.t() | nil,
          reason: String.t() | nil
        }

  # ---------------------------------------------------------------------------
  # The cycle
  # ---------------------------------------------------------------------------

  @doc """
  Run the stage → grade → accept → repair loop for `files` staged at `ctx.dir`.

  Returns a result map whose `:status` is `:accepted` (green + mutant killed) or
  `:rejected` (exhausted retries), carrying the final `:files`, `:grade`, and the
  number of grade `:attempts` performed.
  """
  @spec run(files(), ctx(), Config.t()) :: result()
  def run(files, ctx, %Config{} = cfg) do
    CycleLog.reset_attempts(cfg, ctx.id)

    # Canonical formatting is applied BEFORE grading (and re-applied after every
    # repair merge below) so the bytes that pass the gates are the bytes promoted —
    # the corpus stays `Code.format_string!`-canonical without spending repair
    # attempts on cosmetics (docs/10 R6).
    files = Evaluator.autoformat(files)

    Enum.reduce_while(0..cfg.max_retries, {files, nil}, fn attempt, {files, cached} ->
      # A fix that returned byte-identical files (contract violation, rejected harness
      # edit) has a deterministic grade AND gate decision — reuse them instead of
      # burning an eval subprocess (and a per-fn mutation sweep) on identical input.
      {grade, decision} =
        case cached do
          nil ->
            Evaluator.stage!(ctx.dir, files)
            grade = Evaluator.grade(ctx.dir, cfg)
            {grade, accept?(grade, ctx, files, cfg)}

          {grade, decision} ->
            {grade, decision}
        end

      case decision do
        {:accept, mode} ->
          CycleLog.record_attempt(cfg, ctx.id, attempt, files, grade, :accepted, nil)
          progress(attempt, "#{grade_line(grade)} — all gates passed")
          Logger.info("cycle #{ctx.id}: ACCEPTED on attempt #{attempt}")
          {:halt, mk(:accepted, files, grade, attempt + 1, nil, mode)}

        {:reject, reason} ->
          report = Evaluator.repair_report(reason)
          why = reason_text(reason)

          cond do
            attempt >= cfg.max_retries ->
              CycleLog.record_attempt(cfg, ctx.id, attempt, files, grade, :rejected_final, report)
              progress(attempt, "#{why} — retries exhausted")
              Logger.info("cycle #{ctx.id}: REJECTED after #{attempt + 1} attempt(s)")
              {:halt, mk(:rejected, files, grade, attempt + 1, why)}

            true ->
              CycleLog.record_attempt(cfg, ctx.id, attempt, files, grade, :rejected, report)
              progress(attempt, "#{why} — asking for a fix")

              case repair(files, report, ctx, cfg) do
                :error ->
                  progress(attempt, "the fix call itself failed — giving up")
                  {:halt, mk(:rejected, files, grade, attempt + 1, why <> "; repair call failed")}

                {:ok, new_files} when new_files == files ->
                  progress(attempt, "fix changed nothing usable — re-asking without regrade")
                  {:cont, {files, {grade, decision}}}

                {:ok, new_files} ->
                  case Evaluator.autoformat(new_files) do
                    # formats to the same bytes we already graded — cosmetic-only fix
                    ^files -> {:cont, {files, {grade, decision}}}
                    formatted -> {:cont, {formatted, nil}}
                  end
              end
          end
      end
    end)
  end

  defp mk(:accepted, files, grade, attempts, _reason, mode),
    do: %{
      status: :accepted,
      files: files,
      grade: grade,
      attempts: attempts,
      mutant_failed: true,
      mutation: Atom.to_string(mode),
      reason: nil
    }

  defp mk(:rejected, files, grade, attempts, reason),
    do: %{
      status: :rejected,
      files: files,
      grade: grade,
      attempts: attempts,
      mutant_failed: false,
      mutation: nil,
      reason: reason
    }

  # One indented terminal line per graded attempt — the console used to show nothing
  # between the task header and the final verdict, so a 4-attempt cycle looked hung
  # and the verdict could not say WHICH gate rejected.
  defp progress(attempt, msg) do
    IO.puts("    · attempt #{attempt}: #{shorten(msg)}")
  end

  defp shorten(msg) do
    one_line = msg |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(one_line) > 160, do: String.slice(one_line, 0, 157) <> "…", else: one_line
  end

  defp grade_line(grade) do
    s = grade_stats(grade)
    "green (#{s.tests_passed}/#{s.tests_total})"
  end

  @doc """
  Human text for a reject reason — the SPECIFIC gate and detail, unlike
  `reason_for/1` which only sees the grade (and so mislabels a quality-gate or
  fix-transport failure as "vacuous harness").
  """
  @spec reason_text(term()) :: String.t()
  def reason_text(:timeout_or_crash), do: "evaluation timed out or crashed"
  def reason_text({:quality, shortfall}), do: "house style: " <> shortfall
  def reason_text({:vacuous, why}), do: "mutation gate: " <> why
  def reason_text({:warnings, n}), do: "compile warnings: #{n}"
  def reason_text({:flaky, seed}), do: "stability confirmation failed (seed #{seed})"

  def reason_text({:failed, grade}) do
    s = grade_stats(grade)

    case reason_for(grade) do
      "tests failed" -> "tests failed (#{s.tests_passed}/#{s.tests_total} passed)"
      other -> other
    end
  end

  defp accept?(:timeout_or_crash, _ctx, _files, _cfg), do: {:reject, :timeout_or_crash}

  defp accept?({:ok, json} = grade, ctx, files, cfg) do
    if Evaluator.green?(grade) do
      accept_green(json, ctx, files, cfg)
    else
      {:reject, {:failed, grade}}
    end
  end

  # Green: apply the house-style/zero-warning/harness-standard quality gate (unless
  # disabled), then the mutation gate, then a stability re-grade at a derived seed.
  # Ordering fails fast — the cheap JSON/text checks run before the expensive
  # per-function mutation grades, and the confirmation eval runs only once, on accept.
  defp accept_green(json, ctx, files, cfg) do
    shortfall = if cfg.quality_gate, do: Evaluator.quality_shortfall(json, files), else: nil

    cond do
      shortfall ->
        {:reject, {:quality, shortfall}}

      true ->
        case Mutation.gate_base(ctx.mutant_dir, files, cfg) do
          {:survived, why} ->
            {:reject, {:vacuous, why}}

          :killed ->
            case confirm_stability(ctx, cfg) do
              :ok -> {:accept, Mutation.base_mode(files["solution.ex"], cfg)}
              {:flaky, seed} -> {:reject, {:flaky, seed}}
            end
        end
    end
  end

  # Stability confirmation (docs/12 §5.1 item 6): re-grade the already-staged, already-
  # green accepted files ONE more time at a DERIVED deterministic nonzero seed. The
  # evaluator pins ExUnit `seed: 0` and staging is byte-deterministic, so a same-seed
  # re-eval is a no-op; a different seed breaks the pinned test order and surfaces
  # order-dependence/timing flakiness BEFORE promotion. The seed is derived from the
  # task id (no wall-clock randomness), so the confirmation is itself reproducible.
  #
  # A failed confirmation is flake evidence: it is appended to `logs/flaky.jsonl` (the
  # ledger `validate.exs` reads) and the accept is turned into a reject → the normal
  # repair/reject path. `ctx.dir` still holds exactly the graded files (the mutation
  # gate stages into `ctx.mutant_dir`, never `ctx.dir`).
  defp confirm_stability(ctx, cfg) do
    seed = confirmation_seed(ctx.id)
    grade = Evaluator.grade(ctx.dir, cfg, "solution.ex", seed)

    if Evaluator.green?(grade) do
      :ok
    else
      Logger.warning("cycle #{ctx.id}: stability confirmation FAILED at seed #{seed} — flake")
      CycleLog.record_flake(cfg, ctx.id, grade, seed)
      {:flaky, seed}
    end
  end

  @doc """
  A deterministic, nonzero ExUnit seed derived from `id` — reproducible (no wall-clock
  randomness) yet different from the evaluator's pinned `0`, so it breaks the pinned
  test order for the stability-confirmation re-grade (docs/12 §5.1 item 6).
  """
  @spec confirmation_seed(String.t()) :: pos_integer()
  def confirmation_seed(id), do: 1 + :erlang.phash2(id, 2_000_000_000)

  defp repair(files, report, ctx, cfg) do
    Logger.info("cycle #{ctx.id}: repairing — #{report}")
    {system, user} = Prompts.fix(files, report, :task)

    case opus(cfg, ctx.id, "fix", system, user) do
      {:ok, text, _meta} ->
        upd = Reply.parse(text)

        with :ok <- Reply.validate_fix(upd),
             :ok <- guard_test_deletion(files, upd, ctx) do
          {:ok, Map.merge(files, upd)}
        else
          {:error, msg} ->
            Logger.warning("cycle #{ctx.id}: fix contract violation (attempt consumed): #{msg}")
            {:ok, files}
        end

      {:error, reason} ->
        Logger.error("cycle #{ctx.id}: fix call failed: #{inspect(reason)}")
        :error
    end
  end

  # The fixer's path of least resistance for a failing edge-case test is deleting it —
  # which passes green AND the mutation gate (that only requires each public function
  # killed by SOME test), silently weakening the accepted harness. A harness edit that
  # reduces the test count is rejected wholesale; the (re-)ask must fix code or tests,
  # not remove them. Counts `test`/`property` at any nesting so a flat→describe
  # restructuring is not miscounted as deletion.
  @doc false
  def guard_test_deletion(files, upd, ctx) do
    case upd["test_harness.exs"] do
      nil ->
        :ok

      new_harness ->
        old_count = count_tests(files["test_harness.exs"] || "")
        new_count = count_tests(new_harness)

        if new_count < old_count do
          Logger.warning(
            "cycle #{ctx.id}: fix DELETED tests (#{old_count} → #{new_count}) — rejected"
          )

          {:error,
           "the fix removed tests from test_harness.exs (#{old_count} → #{new_count}); " <>
             "deleting a failing test is not a repair — fix the code or the test instead"}
        else
          :ok
        end
    end
  end

  defp count_tests(harness), do: length(Regex.scan(~r/^\s*(?:test|property)\s+"/m, harness))

  # ---------------------------------------------------------------------------
  # Shared generation plumbing
  # ---------------------------------------------------------------------------

  @doc """
  Call the injectable Opus transport (`cfg.opus.call/3`) and append a
  `logs/usage.jsonl` line. Returns whatever `call/3` returns.
  """
  @spec opus(Config.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def opus(%Config{} = cfg, id, step, system, user) do
    GenTask.Opus.put_call_label("#{step} (#{id})")
    started = System.monotonic_time(:millisecond)

    case cfg.opus.call(system, user, cfg) do
      {:ok, _text, meta} = ok ->
        CycleLog.record_usage(cfg, %{
          id: id,
          step: step,
          model: cfg.model,
          in_tokens: usage_field(meta, "input_tokens"),
          out_tokens: usage_field(meta, "output_tokens"),
          stop_reason: safe(meta[:stop_reason]),
          cost_usd: meta[:cost_usd],
          elapsed_ms: System.monotonic_time(:millisecond) - started
        })

        ok

      other ->
        other
    end
  end

  defp usage_field(%{usage: usage}, key) when is_map(usage), do: usage[key]
  defp usage_field(_meta, _key), do: nil

  @doc """
  Generate + parse + contract-validate, with one reminder retry on a contract miss.
  The shared shape used by every single-reply generation step (base task/solve,
  variation blind solve, the blind-solve screen). Returns `{:ok, files}` or
  `{:error, reason}` (`{:contract, step}` when retries are exhausted).
  """
  @spec generate(
          Config.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          (files() -> :ok | {:error, String.t()})
        ) :: {:ok, files()} | {:error, term()}
  def generate(cfg, id, step, system, user, validator, left \\ 2)

  def generate(_cfg, _id, step, _system, _user, _validator, 0), do: {:error, {:contract, step}}

  def generate(cfg, id, step, system, user, validator, left) do
    case opus(cfg, id, step, system, user) do
      {:ok, text, _meta} ->
        files = Reply.parse(text)

        case validator.(files) do
          :ok ->
            {:ok, files}

          {:error, msg} ->
            Logger.warning("#{step} (#{id}): contract violation: #{msg} — reminding")

            reminder =
              user <> "\n\nReminder: return ONLY the requested <file> blocks and nothing else."

            generate(cfg, id, step, system, reminder, validator, left - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe(v) when is_binary(v) or is_number(v) or is_nil(v), do: v
  defp safe(v), do: inspect(v)

  @doc """
  Promote `files` to `tasks/<task_id>/` — the ONE write into the protected tree.

  Refuses (logs + `{:skipped, :exists}`) if the target already exists, honouring the
  safety invariant. Under `cfg.dry_run` nothing is written (`{:dry_run, target}`).
  """
  @spec promote(Config.t(), String.t(), files()) ::
          {:ok, String.t()} | {:skipped, :exists} | {:dry_run, String.t()}
  def promote(%Config{} = cfg, task_id, files) do
    target = Path.join(cfg.tasks_dir, task_id)

    cond do
      File.exists?(target) ->
        Logger.warning(
          "promotion refused: #{target} already exists — skipping (safety invariant)"
        )

        {:skipped, :exists}

      cfg.dry_run ->
        Logger.info("dry-run: would promote #{task_id} (#{map_size(files)} files) — not writing")
        {:dry_run, target}

      true ->
        guard_under_tasks!(cfg, target)
        File.mkdir_p!(target)

        Enum.each(files, fn {rel, body} ->
          full = safe_child_path!(target, rel)
          File.mkdir_p!(Path.dirname(full))
          File.write!(full, body)
        end)

        Logger.info("promoted #{task_id} -> #{target}")
        {:ok, target}
    end
  end

  defp guard_under_tasks!(%Config{tasks_dir: tasks_dir}, target) do
    t = Path.expand(target)
    root = Path.expand(tasks_dir)

    unless t == root or String.starts_with?(t, root <> "/") do
      raise ArgumentError, "promotion target escapes the tasks dir: #{target}"
    end
  end

  # Join an untrusted (model-supplied) relative key onto `base`, refusing any key
  # that resolves outside `base` (a `../…` or absolute path). Without this a fix
  # reply carrying an extra `<file path="../other_task/solution.ex">` block could
  # overwrite an existing task, violating the safety invariant.
  defp safe_child_path!(base, rel) do
    full = Path.join(base, rel)
    expanded = Path.expand(full)
    root = Path.expand(base)

    unless String.starts_with?(expanded, root <> "/") do
      raise ArgumentError, "unsafe file path escapes the target dir: #{inspect(rel)}"
    end

    full
  end

  # ---------------------------------------------------------------------------
  # Grade → terminal / ledger helpers
  # ---------------------------------------------------------------------------

  @doc "Compile/test counts extracted from a grade (for the terminal line and ledger)."
  @spec grade_stats(Evaluator.grade()) :: %{
          compiled: boolean(),
          tests_passed: non_neg_integer(),
          tests_failed: non_neg_integer(),
          tests_total: non_neg_integer()
        }
  def grade_stats(:timeout_or_crash),
    do: %{compiled: false, tests_passed: 0, tests_failed: 0, tests_total: 0}

  def grade_stats({:ok, json}) do
    %{
      compiled: json["compiled"] == true,
      tests_passed: json["tests_passed"] || 0,
      tests_failed: json["tests_failed"] || 0,
      tests_total: json["tests_total"] || 0
    }
  end

  @doc "A short human reason a grade did not accept (for the terminal line)."
  @spec reason_for(Evaluator.grade()) :: String.t()
  def reason_for(:timeout_or_crash), do: "timeout or crash"

  def reason_for({:ok, json}) do
    cond do
      json["compiled"] != true -> "compile failed"
      (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0 -> "tests failed"
      (json["tests_total"] || 0) == 0 -> "no tests"
      true -> "vacuous harness (mutant survived)"
    end
  end

  @doc """
  Build a complete outcome map (every field present) from a keyword/enumerable of
  overrides. Used by the generators so `GenTask.CLI` can print and record uniformly.
  """
  @spec outcome(Enumerable.t()) :: map()
  def outcome(fields) do
    Map.merge(
      %{
        id: nil,
        kind: nil,
        num: nil,
        name: nil,
        status: :error,
        attempts: nil,
        compiled: false,
        tests_passed: 0,
        tests_failed: 0,
        tests_total: 0,
        mutant_failed: false,
        mutation: nil,
        reason: nil,
        seed: nil
      },
      Map.new(fields)
    )
  end
end
