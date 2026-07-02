defmodule GenTask.Config do
  @moduledoc """
  Resolved configuration for a task-generation run.

  Built from environment variables plus a few CLI positionals (see
  `docs/04-task-generation-loop.md` §15). Every knob has a default; nothing here
  performs I/O beyond reading `System.get_env/1`, so the struct is a pure snapshot
  of the run's parameters.

  The struct also carries the **injectable LLM transport**: `:opus` is the module
  whose `call/3` performs a generation (default `GenTask.Opus`), and
  `:opus_runner` is the lower-level subprocess function used *inside* `GenTask.Opus`
  (default `&GenTask.Opus.real_run/3`). Tests override these to avoid real
  `claude` calls.
  """

  @type work_scope :: :bases | :backfill | nil

  @type t :: %__MODULE__{
          model: String.t(),
          max_retries: non_neg_integer(),
          fim_max_per_task: pos_integer(),
          eval_timeout_s: pos_integer(),
          call_timeout_s: pos_integer(),
          usage_wait_ms: non_neg_integer(),
          usage_max_wait_ms: non_neg_integer(),
          transient_retries: non_neg_integer(),
          quality_gate: boolean(),
          per_fn_mutation: boolean(),
          limit: pos_integer() | nil,
          from: pos_integer() | nil,
          to: pos_integer() | nil,
          only_idea: pos_integer() | nil,
          retry_failed: boolean(),
          skip_variations: boolean(),
          skip_fim: boolean(),
          skip_backfill: boolean(),
          only: work_scope(),
          dry_run: boolean(),
          tasks_dir: String.t(),
          tasks_md: String.t(),
          staging_dir: String.t(),
          logs_dir: String.t(),
          opus: module(),
          opus_runner: (String.t(), String.t(), t() -> {String.t(), integer()})
        }

  defstruct model: "opus",
            max_retries: 3,
            fim_max_per_task: 3,
            eval_timeout_s: 120,
            call_timeout_s: 900,
            usage_wait_ms: 900_000,
            usage_max_wait_ms: 21_600_000,
            transient_retries: 5,
            quality_gate: true,
            per_fn_mutation: true,
            limit: nil,
            from: nil,
            to: nil,
            only_idea: nil,
            retry_failed: false,
            skip_variations: false,
            skip_fim: false,
            skip_backfill: false,
            only: nil,
            dry_run: false,
            tasks_dir: "tasks",
            tasks_md: "tasks/tasks.md",
            staging_dir: ".gen_staging",
            logs_dir: "logs",
            opus: GenTask.Opus,
            opus_runner: &GenTask.Opus.real_run/3

  @doc """
  Build a config from the process environment and CLI `argv`.

  A single positional integer argument (e.g. `mix run scripts/generate.exs 80`)
  restricts the run to that one base idea (`:only_idea`).
  """
  @spec new([String.t()], (String.t() -> String.t() | nil)) :: t()
  def new(argv \\ [], env_fun \\ &System.get_env/1) do
    %__MODULE__{
      model: env_str(env_fun, "GEN_MODEL", "opus"),
      max_retries: env_int(env_fun, "GEN_MAX_RETRIES", 3),
      fim_max_per_task: env_int(env_fun, "GEN_FIM_MAX_PER_TASK", 3),
      eval_timeout_s: env_int(env_fun, "GEN_EVAL_TIMEOUT_S", 120),
      call_timeout_s: env_int(env_fun, "GEN_CALL_TIMEOUT_S", 900),
      usage_wait_ms: env_int(env_fun, "GEN_USAGE_WAIT_MS", 900_000),
      usage_max_wait_ms: env_int(env_fun, "GEN_USAGE_MAX_WAIT_MS", 21_600_000),
      transient_retries: env_int(env_fun, "GEN_TRANSIENT_RETRIES", 5),
      quality_gate: not env_bool(env_fun, "GEN_SKIP_QUALITY_GATE"),
      per_fn_mutation: not env_bool(env_fun, "GEN_SKIP_PER_FN_MUTATION"),
      limit: env_int(env_fun, "GEN_LIMIT", nil),
      from: env_int(env_fun, "GEN_FROM", nil),
      to: env_int(env_fun, "GEN_TO", nil),
      only_idea: positional_idea(argv),
      retry_failed: env_bool(env_fun, "GEN_RETRY_FAILED"),
      skip_variations: env_bool(env_fun, "GEN_SKIP_VARIATIONS"),
      skip_fim: env_bool(env_fun, "GEN_SKIP_FIM"),
      skip_backfill: env_bool(env_fun, "GEN_SKIP_BACKFILL"),
      only: work_scope(env_fun),
      dry_run: env_bool(env_fun, "GEN_DRY_RUN")
    }
  end

  # ---------------- helpers ----------------

  defp positional_idea(argv) do
    Enum.find_value(argv, fn arg ->
      case Integer.parse(arg) do
        {n, ""} when n > 0 -> n
        _ -> nil
      end
    end)
  end

  defp work_scope(env_fun) do
    case env_fun.("GEN_ONLY") do
      nil -> nil
      v -> if String.downcase(v) =~ ~r/backfill/, do: :backfill, else: :bases
    end
  end

  defp env_str(env_fun, key, default) do
    case env_fun.(key) do
      nil -> default
      "" -> default
      v -> v
    end
  end

  defp env_int(env_fun, key, default) do
    case env_fun.(key) do
      nil ->
        default

      v ->
        case Integer.parse(v) do
          {n, _} -> n
          :error -> default
        end
    end
  end

  defp env_bool(env_fun, key) do
    case env_fun.(key) do
      nil -> false
      v -> String.downcase(String.trim(v)) in ["1", "true", "yes", "on"]
    end
  end
end
