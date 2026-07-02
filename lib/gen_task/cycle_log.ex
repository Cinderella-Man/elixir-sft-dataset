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

  require Logger

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
