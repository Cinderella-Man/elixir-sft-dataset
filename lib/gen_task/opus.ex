defmodule GenTask.Opus do
  @moduledoc """
  Non-agentic LLM transport: drive the `claude` CLI as a single-shot subprocess so
  calls draw on the user's Claude subscription (see
  `docs/04-task-generation-loop.md` §11).

  `call/3` is the entry point used by the generation steps. It classifies each
  reply and drives the control flow: a subscription **usage-window pause** (log,
  record, sleep, retry the same call — indefinitely, until the window resets), a
  short exponential backoff for transient errors, a reminder-retry for truncated
  replies, and a plain error for refusals.

  The subprocess itself is behind the injectable `cfg.opus_runner` so tests can
  feed canned JSON and never touch the real CLI. `classify/2` is a pure function
  over `{stdout, exit_code}`, unit-testable on its own.
  """

  require Logger

  alias GenTask.{Config, CycleLog}

  # Strong, usage-window-specific phrases only. Deliberately excludes generic
  # phrases like "try again" / bare "resets at" that also appear in 5xx/gateway
  # bodies — a transient error must NOT be misread as a usage limit, because the
  # usage-limit branch sleeps for 15 minutes per attempt (see `do_call/5`).
  @usage_re ~r/usage limit|rate.?limit|limit reached|quota (?:exceeded|reached)|too many requests/i
  @transient_re ~r/overloaded|timeout|timed out|network|connection|econn|502|503|504|internal server|temporar|error_max_turns|max.?turns|error_during_execution/i

  @type meta :: %{
          usage: any(),
          model_usage: any(),
          stop_reason: any(),
          subtype: any(),
          cost_usd: any(),
          is_error: any(),
          api_error_status: any(),
          num_turns: any()
        }

  @doc """
  Perform one generation. Returns `{:ok, result_text, meta}` on success, or
  `{:error, reason}` on a refusal / exhausted transient retries / truncation that
  could not be recovered.
  """
  @spec call(String.t(), String.t(), Config.t()) ::
          {:ok, String.t(), meta()} | {:error, term()}
  def call(system, user, %Config{} = cfg) do
    Logger.debug("claude -p SYSTEM prompt:\n#{system}")
    Logger.debug("claude -p USER prompt:\n#{user}")
    do_call(system, user, cfg, 0, 0)
  end

  defp do_call(system, user, %Config{} = cfg, transient_n, usage_n) do
    {out, code} = run(system, user, cfg)

    case classify(out, code) do
      {:ok, text, meta} ->
        Logger.debug("claude -p RESULT (stop=#{inspect(meta.stop_reason)}):\n#{text}")
        Logger.debug("claude -p usage: #{inspect(meta.usage)}")
        {:ok, text, meta}

      {:usage_limit, _meta} ->
        attempt = usage_n + 1

        # Bound the total time we will wait on usage-limit signals. The legitimate
        # case is riding out a 5-hour subscription window; the cap (default 6h)
        # covers a full reset while ensuring a *misclassified* persistent transient
        # error can never hang the whole run indefinitely.
        if attempt * cfg.usage_wait_ms > cfg.usage_max_wait_ms do
          Logger.error(
            "usage limit persisted past the #{cfg.usage_max_wait_ms}ms cap " <>
              "(#{attempt} attempts) — giving up on this call"
          )

          {:error, {:usage_limit, :exhausted}}
        else
          Logger.warning(
            "usage limit reached on #{call_label()} — waiting #{cfg.usage_wait_ms}ms " <>
              "(attempt #{attempt})"
          )

          CycleLog.record_wait(cfg, cfg.usage_wait_ms, attempt, "usage_limit")
          Process.sleep(cfg.usage_wait_ms)
          do_call(system, user, cfg, transient_n, attempt)
        end

      {:truncated, _meta} ->
        if transient_n < cfg.transient_retries do
          Logger.warning("reply truncated (max_tokens) — retrying with a reminder")

          reminder =
            user <>
              "\n\nYour previous reply was truncated. Return ONLY the complete <file> blocks."

          do_call(system, reminder, cfg, transient_n + 1, usage_n)
        else
          {:error, :truncated}
        end

      {:transient, reason} ->
        if transient_n < cfg.transient_retries do
          backoff = 2000 * Integer.pow(2, transient_n)

          Logger.warning(
            "transient error (#{reason}) on #{call_label()} — " <>
              "retry #{transient_n + 1}/#{cfg.transient_retries} after #{backoff}ms"
          )
          Process.sleep(backoff)
          do_call(system, user, cfg, transient_n + 1, usage_n)
        else
          {:error, {:transient, reason}}
        end

      {:refusal, reason} ->
        Logger.error("claude -p refusal / content error: #{reason}")
        {:error, {:refusal, reason}}
    end
  end

  defp run(system, user, %Config{opus_runner: runner} = cfg), do: runner.(system, user, cfg)

  @doc """
  Classify a `{stdout, exit_code}` pair from `claude -p`.

  Returns one of `{:ok, text, meta}`, `{:usage_limit, meta}`, `{:truncated, meta}`,
  `{:transient, reason}`, `{:refusal, reason}`.
  """
  @spec classify(String.t(), integer()) ::
          {:ok, String.t(), meta()}
          | {:usage_limit, meta()}
          | {:truncated, meta()}
          | {:transient, String.t()}
          | {:refusal, String.t()}
  def classify(out, code) do
    case decode(out) do
      {:ok, j} ->
        m = meta(j)

        cond do
          usage_limit?(j) -> {:usage_limit, m}
          j["stop_reason"] == "max_tokens" -> {:truncated, m}
          truthy(j["is_error"]) and transient?(j) -> {:transient, signal(j)}
          truthy(j["is_error"]) -> {:refusal, signal(j)}
          code == 0 -> {:ok, j["result"] || "", m}
          true -> {:transient, "non-zero exit #{code} without error flag"}
        end

      :error ->
        # A killed (137) or crashed process yields no parseable JSON.
        {:transient, "no JSON on stdout (exit #{code})"}
    end
  end

  defp usage_limit?(j) do
    truthy(j["is_error"]) and
      (j["api_error_status"] == 429 or
         Regex.match?(@usage_re, signal(j)))
  end

  defp transient?(j) do
    j["api_error_status"] in [500, 502, 503, 504, 529] or
      Regex.match?(@transient_re, signal(j))
  end

  # The text we scan for classification: result + subtype. `.result`/`.subtype` may
  # be absent or, on some error payloads, a non-string (map/list); coerce defensively
  # so classification never crashes on `String.Chars`.
  defp signal(j), do: "#{stringify(j["subtype"])} #{stringify(j["result"])}"

  defp stringify(v) when is_binary(v), do: v
  defp stringify(nil), do: ""
  defp stringify(v), do: inspect(v)

  defp truthy(true), do: true
  defp truthy(_), do: false

  defp meta(j) do
    %{
      usage: j["usage"],
      model_usage: j["modelUsage"],
      stop_reason: j["stop_reason"],
      subtype: j["subtype"],
      cost_usd: j["total_cost_usd"],
      is_error: j["is_error"],
      api_error_status: j["api_error_status"],
      num_turns: j["num_turns"]
    }
  end

  defp decode(out) do
    trimmed = String.trim(out || "")

    with :error <- try_decode(trimmed),
         :error <- try_decode(last_json_line(trimmed)) do
      :error
    end
  end

  defp try_decode(""), do: :error

  defp try_decode(str) do
    case Jason.decode(str) do
      {:ok, %{} = j} -> {:ok, j}
      _ -> :error
    end
  end

  defp last_json_line(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find("", &String.starts_with?(&1, "{"))
  end

  # ---------------------------------------------------------------------------
  # Real subprocess runner (default cfg.opus_runner)
  # ---------------------------------------------------------------------------

  @doc """
  Default transport: write both prompts to temp files, invoke `claude -p` (with the
  user prompt on stdin via a `bash -c … < file` redirect), and return
  `{stdout, exit_code}`. `ANTHROPIC_API_KEY` is unset in the child so the CLI uses
  the subscription login.
  """
  @spec real_run(String.t(), String.t(), Config.t()) :: {String.t(), integer()}
  def real_run(system, user, %Config{} = cfg) do
    sys_path = temp_write(system, "gen_sys")
    user_path = temp_write(user, "gen_user")

    try do
      System.cmd("bash", ["-c", command(sys_path, user_path, cfg)],
        env: [{"ANTHROPIC_API_KEY", nil}],
        stderr_to_stdout: false
      )
    after
      File.rm(sys_path)
      File.rm(user_path)
    end
  end

  defp command(sys_path, user_path, %Config{} = cfg) do
    # `--max-turns` (default 2, `GEN_MAX_TURNS`): this is a NON-AGENTIC transport
    # (see @moduledoc) — a clean generation completes in one turn. But on fix/repair
    # prompts the model routinely *attempts* a (disabled) tool call first; with
    # `--max-turns 1` that fast-fails as `error_max_turns` and the transient retry
    # tends to re-sample the same behavior (observed live: 5/5 retries failed,
    # ~3.5 min wasted — docs/09 §11). Two turns lets the denied tool attempt be
    # followed by the real single-shot reply, while still bounding a runaway
    # agentic loop (20 turns used to stall ~15 min). Reminder/repair steps are
    # separate `claude -p` calls, not extra turns here.
    "timeout --signal=KILL #{cfg.call_timeout_s} " <>
      "claude -p --output-format json --model #{shell_quote(cfg.model)} " <>
      "--max-turns #{cfg.max_turns} --allowedTools '' " <>
      "--system-prompt-file #{shell_quote(sys_path)} " <>
      "--setting-sources '' --strict-mcp-config --no-session-persistence " <>
      "< #{shell_quote(user_path)}"
  end

  @doc """
  Label the current process's in-flight call (set by `GenTask.Cycle.opus/5`) so
  transport-level retry warnings say WHICH call is stalling — "fix 135_001_…" beats
  an anonymous "transient error" on the console.
  """
  @spec put_call_label(String.t()) :: :ok
  def put_call_label(label) do
    Process.put(:gen_task_call_label, label)
    :ok
  end

  defp call_label, do: Process.get(:gen_task_call_label) || "call"

  defp temp_write(content, prefix) do
    name = "#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}.txt"
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, content)
    path
  end

  defp shell_quote(str), do: "'" <> String.replace(str, "'", "'\\''") <> "'"
end
