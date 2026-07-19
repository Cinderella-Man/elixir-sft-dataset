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
          dialyzer_gate: boolean(),
          per_fn_mutation: boolean(),
          skip_write_test: boolean(),
          skip_test_fim: boolean(),
          skip_bugfix: boolean(),
          skip_adapt: boolean(),
          skip_dedoc: boolean(),
          skip_sfim: boolean(),
          skip_tdd: boolean(),
          skip_specfim: boolean(),
          skip_bundlefim: boolean(),
          skip_variation_blind: boolean(),
          blind_rescreen: boolean(),
          semantic_floor: float() | nil,
          promise_audit: boolean(),
          audit_max_tests: pos_integer(),
          tfim_max_per_task: pos_integer(),
          max_turns: pos_integer(),
          limit: pos_integer() | nil,
          from: pos_integer() | nil,
          to: pos_integer() | nil,
          only_idea: pos_integer() | nil,
          force: boolean(),
          retry_failed: boolean(),
          skip_variations: boolean(),
          skip_fim: boolean(),
          skip_backfill: boolean(),
          only: work_scope(),
          reconcile: boolean(),
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
            # 0 = unlimited: keep retrying every usage_wait_ms until tokens return
            # (running out of the 5-hour subscription window is a normal condition).
            usage_max_wait_ms: 0,
            transient_retries: 5,
            quality_gate: true,
            # Struct default FALSE so sandbox tests (bare %Config{}) stay
            # hermetic and PLT-free; `Config.new/1` resolves it ON — the
            # promise_audit pattern.
            dialyzer_gate: false,
            per_fn_mutation: true,
            skip_write_test: false,
            skip_test_fim: false,
            skip_bugfix: false,
            skip_adapt: false,
            skip_dedoc: false,
            skip_sfim: false,
            skip_tdd: false,
            skip_specfim: false,
            skip_bundlefim: false,
            skip_variation_blind: false,
            # T1.1 (docs/12 §5.2.1): accept-time blind re-screen for bases accepted
            # after ≥1 repair. OFF until Kamil signs off the policy (STATUS).
            blind_rescreen: false,
            # T1.8 (docs/12 §5.5 row 12): accept-time semantic-mutant kill FLOOR.
            # nil = report-only (today's behavior); Kamil sets the number at the
            # §4.2 sign-off (S8 was measured at 0.714 corpus-wide, observable
            # basis; the three-way survivor framework is docs/13 §1.5.1b).
            semantic_floor: nil,
            # T1.10 (docs/17 §5): the accept-time promise audit for ROOTS — the
            # in-loop replica of the manual close_gaps + probe-proven review flow.
            # OFF (dark) until piloted; see GenTask.PromiseAudit.
            promise_audit: false,
            audit_max_tests: 6,
            # Lifted 10→30 (TD.5 cap lift, Kamil's go 2026-07-19): ~1,900
            # carvable tests sat above the old cap; per-unit gates still apply
            # and the docs/16 §4 weight (0.25) is the near-duplication
            # counterweight. Phase-3 seeds mint at the same bound (Task B).
            tfim_max_per_task: 30,
            max_turns: 2,
            limit: nil,
            from: nil,
            to: nil,
            only_idea: nil,
            force: false,
            retry_failed: false,
            exclude_seeds: [],
            skip_variations: false,
            skip_fim: false,
            skip_backfill: false,
            only: nil,
            reconcile: true,
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
  restricts the run to that one base idea (`:only_idea`). `--force` (valid ONLY
  together with such an idea number) makes the run first DELETE that idea's whole
  task family from `tasks/` + `tasks.md` so the loop regenerates it from scratch —
  see `GenTask.Force`.
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
      usage_max_wait_ms: env_int(env_fun, "GEN_USAGE_MAX_WAIT_MS", 0),
      transient_retries: env_int(env_fun, "GEN_TRANSIENT_RETRIES", 5),
      quality_gate: not env_bool(env_fun, "GEN_SKIP_QUALITY_GATE"),
      # Spec-truth at accept (docs/12 §5.5 rows 15+23). Kamil 2026-07-15:
      # quality gates are never optional — ON by default, opt-out for debugging.
      dialyzer_gate: env_bool_default(env_fun, "GEN_DIALYZER", true),
      per_fn_mutation: not env_bool(env_fun, "GEN_SKIP_PER_FN_MUTATION"),
      skip_write_test: env_bool(env_fun, "GEN_SKIP_WRITE_TEST"),
      skip_test_fim: env_bool(env_fun, "GEN_SKIP_TEST_FIM"),
      skip_bugfix: env_bool(env_fun, "GEN_SKIP_BUGFIX"),
      skip_adapt: env_bool(env_fun, "GEN_SKIP_ADAPT"),
      skip_dedoc: env_bool(env_fun, "GEN_SKIP_DEDOC"),
      skip_sfim: env_bool(env_fun, "GEN_SKIP_SFIM"),
      skip_tdd: env_bool(env_fun, "GEN_SKIP_TDD"),
      skip_specfim: env_bool(env_fun, "GEN_SKIP_SPECFIM"),
      skip_bundlefim: env_bool(env_fun, "GEN_SKIP_BUNDLEFIM"),
      skip_variation_blind: env_bool(env_fun, "GEN_SKIP_VARIATION_BLIND"),
      # Kamil, 2026-07-15: quality gates are NEVER optional — generation always
      # runs at the maximum standard. These three resolve ON by default; the env
      # switches are opt-OUT, kept for debugging only (GEN_BLIND_RESCREEN=0,
      # GEN_SEMANTIC_FLOOR=off, GEN_PROMISE_AUDIT=0). The STRUCT defaults stay
      # conservative so unit tests exercise gates explicitly, not by surprise.
      blind_rescreen: env_bool_default(env_fun, "GEN_BLIND_RESCREEN", true),
      semantic_floor: env_floor(env_fun, "GEN_SEMANTIC_FLOOR", 0.6),
      promise_audit: env_bool_default(env_fun, "GEN_PROMISE_AUDIT", true),
      audit_max_tests: env_int(env_fun, "GEN_AUDIT_MAX_TESTS", 6),
      tfim_max_per_task: env_int(env_fun, "GEN_TFIM_MAX_PER_TASK", 30),
      max_turns: env_int(env_fun, "GEN_MAX_TURNS", 2),
      limit: env_int(env_fun, "GEN_LIMIT", nil),
      from: env_int(env_fun, "GEN_FROM", nil),
      to: env_int(env_fun, "GEN_TO", nil),
      only_idea: positional_idea(argv),
      force: "--force" in argv,
      retry_failed: env_bool(env_fun, "GEN_RETRY_FAILED"),
      exclude_seeds: env_prefixes(env_fun, "GEN_EXCLUDE_SEEDS"),
      skip_variations: env_bool(env_fun, "GEN_SKIP_VARIATIONS"),
      skip_fim: env_bool(env_fun, "GEN_SKIP_FIM"),
      skip_backfill: env_bool(env_fun, "GEN_SKIP_BACKFILL"),
      only: work_scope(env_fun),
      reconcile: env_bool_default(env_fun, "GEN_RECONCILE", true),
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
      nil ->
        nil

      v ->
        case String.downcase(String.trim(v)) do
          "backfill" ->
            :backfill

          b when b in ["bases", "base"] ->
            :bases

          other ->
            # A typo like GEN_ONLY=fim used to silently mean :bases — refuse instead.
            raise ArgumentError,
                  "GEN_ONLY=#{inspect(other)} is not recognized (expected \"bases\" or \"backfill\")"
        end
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
        case Integer.parse(String.trim(v)) do
          {n, ""} ->
            n

          _ ->
            # GEN_LIMIT=5x used to silently mean 5 — a config typo should stop the run.
            raise ArgumentError, "#{key}=#{inspect(v)} is not an integer"
        end
    end
  end

  defp env_bool(env_fun, key) do
    case env_fun.(key) do
      nil -> false
      v -> String.downcase(String.trim(v)) in ["1", "true", "yes", "on"]
    end
  end

  # A kill-rate floor in [0.0, 1.0]. Unset/empty resolves to `default` (the gate
  # is ON by default — Kamil 2026-07-15: quality gates are never optional);
  # the explicit words "off"/"none" disable it (nil, debugging only). A typo
  # must stop the run, not silently change a quality gate.
  defp env_floor(env_fun, key, default) do
    case env_fun.(key) do
      nil ->
        default

      "" ->
        default

      v ->
        case String.downcase(String.trim(v)) do
          word when word in ["off", "none"] ->
            nil

          trimmed ->
            case Float.parse(trimmed) do
              {f, ""} when f >= 0.0 and f <= 1.0 ->
                f

              _ ->
                raise ArgumentError,
                      "#{key}=#{inspect(v)} is not a float in [0.0, 1.0] (or \"off\")"
            end
        end
    end
  end

  # A boolean knob that is ON unless explicitly disabled (`KEY=0/false/no/off`) —
  # for behaviors that should be opt-OUT (the default run does everything).
  defp env_bool_default(env_fun, key, default) do
    case env_fun.(key) do
      nil -> default
      v -> String.downcase(String.trim(v)) not in ["0", "false", "no", "off"]
    end
  end

  # A comma-separated list of task-id prefixes (e.g. "016_001,102_001").
  defp env_prefixes(env_fun, key) do
    case env_fun.(key) do
      nil ->
        []

      v ->
        v |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end
end
