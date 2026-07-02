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
          mutant_failed: boolean()
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
    Enum.reduce_while(0..cfg.max_retries, {files, :timeout_or_crash}, fn attempt, {files, _} ->
      Evaluator.stage!(ctx.dir, files)
      grade = Evaluator.grade(ctx.dir, cfg)

      case accept?(grade, ctx, files, cfg) do
        :accept ->
          Logger.info("cycle #{ctx.id}: ACCEPTED on attempt #{attempt}")
          {:halt, mk(:accepted, files, grade, attempt + 1)}

        {:reject, reason} ->
          cond do
            attempt >= cfg.max_retries ->
              Logger.info("cycle #{ctx.id}: REJECTED after #{attempt + 1} attempt(s)")
              {:halt, mk(:rejected, files, grade, attempt + 1)}

            true ->
              case repair(files, reason, ctx, cfg) do
                {:ok, files} -> {:cont, {files, grade}}
                :error -> {:halt, mk(:rejected, files, grade, attempt + 1)}
              end
          end
      end
    end)
  end

  defp mk(:accepted, files, grade, attempts),
    do: %{status: :accepted, files: files, grade: grade, attempts: attempts, mutant_failed: true}

  defp mk(:rejected, files, grade, attempts),
    do: %{status: :rejected, files: files, grade: grade, attempts: attempts, mutant_failed: false}

  defp accept?(:timeout_or_crash, _ctx, _files, _cfg), do: {:reject, :timeout_or_crash}

  defp accept?({:ok, _} = grade, ctx, files, cfg) do
    if Evaluator.green?(grade) do
      case Mutation.gate_base(ctx.mutant_dir, files, cfg) do
        :killed -> :accept
        :survived -> {:reject, {:vacuous, grade}}
      end
    else
      {:reject, {:failed, grade}}
    end
  end

  defp repair(files, reason, ctx, cfg) do
    report = Evaluator.repair_report(reason)
    Logger.info("cycle #{ctx.id}: repairing — #{report}")
    {system, user} = Prompts.fix(files, report, :task)

    case opus(cfg, ctx.id, "fix", system, user) do
      {:ok, text, _meta} ->
        upd = Reply.parse(text)

        case Reply.validate_fix(upd) do
          :ok ->
            {:ok, Map.merge(files, upd)}

          {:error, msg} ->
            Logger.warning("cycle #{ctx.id}: fix contract violation (attempt consumed): #{msg}")
            {:ok, files}
        end

      {:error, reason} ->
        Logger.error("cycle #{ctx.id}: fix call failed: #{inspect(reason)}")
        :error
    end
  end

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
        reason: nil,
        seed: nil
      },
      Map.new(fields)
    )
  end
end
