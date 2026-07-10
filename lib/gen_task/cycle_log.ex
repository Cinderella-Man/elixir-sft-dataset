defmodule GenTask.CycleLog do
  @moduledoc """
  Per-cycle logging (see `docs/04-task-generation-loop.md` §14).

  Each generated task gets its own text log at `logs/<task_id>.log`, captured by a
  single fresh global `:logger_std_h` file handler (the loop is sequential, so one
  handler suffices). On success the file stays in `logs/`; on failure it is moved to
  `logs/errors/`.

  Console hygiene: `startup/1` raises the default console handler's level so full
  prompts/responses land only in the file — terminal progress is printed with
  `IO.puts` by the caller, not `Logger`.

  Three append-only JSONL ledgers (`runs`, `usage`, `waits`) are written with
  fsync-per-line so a killed run leaves a consistent trail.
  """

  alias GenTask.Config

  @handler_id :gen_task_cycle
  @format "$time [$level] $message\n"

  @type handle :: %{task_id: String.t(), path: String.t(), logs_dir: String.t()}

  @doc """
  One-time run setup: force `:debug` globally, raise the console handler to
  `:warning` so verbose cycle logging goes to files only, and ensure the log
  directories exist.
  """
  @spec startup(Config.t()) :: :ok
  def startup(%Config{logs_dir: logs_dir}) do
    Logger.configure(level: :debug)
    :logger.update_handler_config(:default, :level, :warning)
    File.mkdir_p!(logs_dir)
    File.mkdir_p!(Path.join(logs_dir, "errors"))
    :ok
  end

  @doc """
  Open a fresh per-cycle log for `task_id`. Truncates the file, removes any prior
  cycle handler, and attaches a new `:logger_std_h` at `:debug` writing to it.
  """
  @spec open(Config.t(), String.t()) :: handle()
  def open(%Config{logs_dir: logs_dir}, task_id) do
    File.mkdir_p!(logs_dir)
    path = Path.join(logs_dir, "#{task_id}.log")
    File.write!(path, "")

    _ = :logger.remove_handler(@handler_id)

    :ok =
      :logger.add_handler(@handler_id, :logger_std_h, %{
        level: :debug,
        config: %{file: String.to_charlist(path)},
        formatter: Logger.Formatter.new(format: @format)
      })

    %{task_id: task_id, path: path, logs_dir: logs_dir}
  end

  @doc """
  Close the current cycle log. Flushes and detaches the handler; on a non-`:ok`
  outcome the file is moved to `logs/errors/<task_id>.log`.
  """
  @spec close(handle(), :ok | :error | {:error, term()}) :: :ok
  def close(%{path: path, logs_dir: logs_dir, task_id: task_id}, outcome) do
    _ = :logger_std_h.filesync(@handler_id)
    _ = :logger.remove_handler(@handler_id)

    if outcome == :ok do
      # Success: drop any stale error log left by a prior failed attempt (or a
      # rejected candidate that reused this subtask index), so logs/errors/
      # reflects only current failures.
      _ = File.rm(Path.join([logs_dir, "errors", "#{task_id}.log"]))
    else
      errors_dir = Path.join(logs_dir, "errors")
      File.mkdir_p!(errors_dir)
      File.rename!(path, Path.join(errors_dir, "#{task_id}.log"))
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # JSONL ledgers
  # ---------------------------------------------------------------------------

  @doc "Append one line to `logs/runs.jsonl` (one per generated task)."
  @spec record_run(Config.t(), map()) :: :ok
  def record_run(%Config{logs_dir: logs_dir}, entry) do
    append_jsonl(Path.join(logs_dir, "runs.jsonl"), Map.put_new(entry, :ts, ts()))
  end

  @doc "Append one line to `logs/usage.jsonl` (one per `claude -p` call)."
  @spec record_usage(Config.t(), map()) :: :ok
  def record_usage(%Config{logs_dir: logs_dir}, entry) do
    append_jsonl(Path.join(logs_dir, "usage.jsonl"), Map.put_new(entry, :ts, ts()))
  end

  @doc """
  Append a stability-confirmation flake to `logs/flaky.jsonl` — the same ledger
  `scripts/validate.exs` writes (docs/12 §5.1 item 6), reusing its entry shape
  (`task`, `ts`, `detail`, `failures[]`) so a repeat offender aggregates across both
  sources. `grade` is the (non-green) confirmation grade at ExUnit `seed`.
  """
  @spec record_flake(Config.t(), String.t(), term(), integer()) :: :ok
  def record_flake(%Config{logs_dir: logs_dir}, task_id, grade, seed) do
    json = grade_map(grade)

    failures =
      for f <- json["test_failures"] || [] do
        %{
          test: f["test"],
          module: f["module"],
          message: String.slice(f["message"] || "", 0, 300)
        }
      end

    append_jsonl(Path.join(logs_dir, "flaky.jsonl"), %{
      task: task_id,
      ts: ts(),
      detail: "stability-confirmation re-grade failed at ExUnit seed #{seed}",
      failures: failures
    })
  end

  @doc "Append one line to `logs/waits.jsonl` (one per usage-window pause)."
  @spec record_wait(Config.t(), non_neg_integer(), pos_integer(), String.t()) :: :ok
  def record_wait(%Config{logs_dir: logs_dir}, waited_ms, attempt, signal) do
    append_jsonl(Path.join(logs_dir, "waits.jsonl"), %{
      ts: ts(),
      waited_ms: waited_ms,
      attempt: attempt,
      signal: signal
    })
  end

  @doc """
  Record a permanently-rejected FIM target (`prefix` = the parent `_01` id without the
  `_01` suffix; `target` = the `name/arity`). These are candidates whose function the
  parent harness does not cover — unfixable without editing the parent harness — so
  they must not be re-selected on later runs.
  """
  @spec record_fim_rejected(Config.t(), String.t(), String.t()) :: :ok
  def record_fim_rejected(%Config{logs_dir: logs_dir}, prefix, target) do
    append_jsonl(Path.join(logs_dir, "fim_rejected.jsonl"), %{
      ts: ts(),
      prefix: prefix,
      target: target
    })
  end

  @doc """
  Record a permanently-rejected tfim target (`prefix` = parent `_01` id without the
  suffix; `name` = the test-block name; `sha` = SHA-256 of the parent harness the
  verdict was computed against). Gate verdicts are deterministic for fixed content
  (fixed eval seed, immutable tasks), so re-gating the same block on every backfill
  pass is pure waste — but keying on the harness hash means a hand-edited parent
  harness automatically invalidates its old rejections.
  """
  @spec record_tfim_rejected(Config.t(), String.t(), String.t(), String.t()) :: :ok
  def record_tfim_rejected(%Config{logs_dir: logs_dir}, prefix, name, sha) do
    append_jsonl(Path.join(logs_dir, "tfim_rejected.jsonl"), %{
      ts: ts(),
      prefix: prefix,
      name: name,
      harness_sha: sha
    })
  end

  @doc "Previously-rejected tfim block names for `prefix` at harness hash `sha`, as a MapSet."
  @spec rejected_tfim_targets(Config.t(), String.t(), String.t()) :: MapSet.t(String.t())
  def rejected_tfim_targets(%Config{logs_dir: logs_dir}, prefix, sha) do
    path = Path.join(logs_dir, "tfim_rejected.jsonl")

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, %{"prefix" => ^prefix, "harness_sha" => ^sha, "name" => n}} -> [n]
            _ -> []
          end
        end)
        |> MapSet.new()

      {:error, _} ->
        MapSet.new()
    end
  end

  @doc "SHA-256 hex of a file body, for content-keyed reject ledgers."
  @spec content_sha(String.t()) :: String.t()
  def content_sha(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  @doc "Record a backfill seed's vacuous-harness self-check verdict, keyed by content hash."
  @spec record_seed_verdict(Config.t(), String.t(), String.t(), map()) :: :ok
  def record_seed_verdict(%Config{logs_dir: logs_dir}, task_id, sha, verdict) do
    append_jsonl(Path.join(logs_dir, "seed_verdicts.jsonl"), %{
      ts: ts(),
      task_id: task_id,
      sha: sha,
      verdict: verdict
    })
  end

  @doc "Cached self-check verdict for `task_id` at content hash `sha` (last one wins)."
  @spec cached_seed_verdict(Config.t(), String.t(), String.t()) :: {:ok, map()} | :miss
  def cached_seed_verdict(%Config{logs_dir: logs_dir}, task_id, sha) do
    path = Path.join(logs_dir, "seed_verdicts.jsonl")

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(:miss, fn line, acc ->
          case Jason.decode(line) do
            {:ok, %{"task_id" => ^task_id, "sha" => ^sha, "verdict" => v}} -> {:ok, v}
            _ -> acc
          end
        end)

      {:error, _} ->
        :miss
    end
  end

  @doc "Previously-rejected FIM targets for `prefix` (from `fim_rejected.jsonl`), as a list."
  @spec rejected_fim_targets(Config.t(), String.t()) :: [String.t()]
  def rejected_fim_targets(%Config{logs_dir: logs_dir}, prefix) do
    path = Path.join(logs_dir, "fim_rejected.jsonl")

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, %{"prefix" => ^prefix, "target" => t}} -> [t]
            _ -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  # ---------------------------------------------------------------------------
  # Attempt capture (docs/07 §4.2, docs/08)
  # ---------------------------------------------------------------------------

  @doc """
  Drop any prior captured attempts for `id` (from an earlier run or a retried
  candidate), so `logs/attempts/<id>/` holds exactly one cycle's history.
  """
  @spec reset_attempts(Config.t(), String.t()) :: :ok
  def reset_attempts(%Config{logs_dir: logs_dir}, id) do
    File.rm_rf!(attempts_dir(logs_dir, id))
    :ok
  end

  @doc """
  Persist one graded attempt of a repair cycle under
  `logs/attempts/<id>/attempt_<NN>/`:

    * `files/` — the exact candidate files that were staged and graded
    * `grade.json` — the full evaluator JSON (or `{"timeout_or_crash": true}`)
    * `meta.json` — `id`, `attempt`, `status` (`accepted` / `rejected` /
      `rejected_final`), the human `repair_report` shown to the fixer, and a
      timestamp

  This is the loop's most valuable byproduct: a rejected attempt N plus the
  accepted attempt M>N is a verified bug→diagnosis→fix pair, and the chain is a
  ready-made multi-turn repair conversation. Without capture, each `stage!` of
  the next attempt physically destroys the previous candidate.
  """
  @spec record_attempt(
          Config.t(),
          String.t(),
          non_neg_integer(),
          %{String.t() => String.t()},
          term(),
          :accepted | :rejected | :rejected_final,
          String.t() | nil
        ) :: :ok
  def record_attempt(%Config{logs_dir: logs_dir}, id, attempt, files, grade, status, report) do
    dir = Path.join(attempts_dir(logs_dir, id), "attempt_#{pad2(attempt)}")
    files_dir = Path.join(dir, "files")
    File.mkdir_p!(files_dir)

    Enum.each(files, fn {rel, body} ->
      File.write!(Path.join(files_dir, Path.basename(rel)), body)
    end)

    File.write!(Path.join(dir, "grade.json"), Jason.encode!(grade_map(grade)))

    File.write!(
      Path.join(dir, "meta.json"),
      Jason.encode!(%{
        id: id,
        attempt: attempt,
        status: status,
        repair_report: report,
        ts: ts()
      })
    )

    :ok
  end

  defp attempts_dir(logs_dir, id), do: Path.join([logs_dir, "attempts", id])

  defp grade_map({:ok, json}) when is_map(json), do: json
  defp grade_map(:timeout_or_crash), do: %{"timeout_or_crash" => true}
  defp grade_map(other), do: %{"unrecognized_grade" => inspect(other)}

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp append_jsonl(path, map) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, io} = :file.open(String.to_charlist(path), [:append, :raw, :binary])

    try do
      :ok = :file.write(io, [Jason.encode!(map), "\n"])
      :ok = :file.sync(io)
    after
      :file.close(io)
    end

    :ok
  end

  defp ts, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
