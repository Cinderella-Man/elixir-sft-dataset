defmodule RollingRateCircuitBreaker do
  @moduledoc """
  A circuit breaker that trips on the **error rate over a rolling window** of recent
  call outcomes, rather than on a count of consecutive failures.

  A consecutive-failure breaker never trips on a service that alternates success and
  failure 50/50, even though such a service is plainly unhealthy: a single success in
  the middle of a stream of failures wipes the failure record. This breaker instead
  keeps the most recent `:window_size` outcomes and trips when there is enough evidence
  (`:min_calls_in_window` outcomes) and the observed error rate meets or exceeds
  `:error_rate_threshold` — the approach taken by Netflix Hystrix and similar
  production breakers.

  ## States

    * `:closed` — calls execute normally and their outcomes feed the rolling window.
    * `:open` — calls fail fast with `{:error, :circuit_open}`; nothing is executed.
    * `:half_open` — up to `:half_open_max_probes` probes are admitted; each probe
      immediately resolves the breaker to `:closed` (success) or `:open` (failure).

  ## Time

  The module keeps **no timers**. The single time source is the injected `:clock`
  function, and the open → half-open expiry is evaluated lazily at the top of every
  `call/2` and `state/1`. A breaker whose reset timeout has elapsed but which nobody
  has touched is therefore still internally open; the very next request performs the
  transition.

  ## Invariants

  Every state transition empties the outcome window — trip, probe success, probe
  failure and manual `reset/1` alike. A breaker that has just changed state needs a
  fresh `:min_calls_in_window` outcomes before it can trip again.
  """

  use GenServer

  @type outcome :: :success | :failure
  @type breaker_state :: :closed | :open | :half_open

  @default_window_size 20
  @default_error_rate_threshold 0.5
  @default_min_calls_in_window 10
  @default_reset_timeout_ms 30_000
  @default_half_open_max_probes 1

  defstruct state: :closed,
            window: [],
            window_size: @default_window_size,
            error_rate_threshold: @default_error_rate_threshold,
            min_calls_in_window: @default_min_calls_in_window,
            reset_timeout_ms: @default_reset_timeout_ms,
            half_open_max_probes: @default_half_open_max_probes,
            clock: nil,
            opened_at: nil,
            probes_in_flight: 0

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a breaker and registers it under the required `:name` option.

  Options:

    * `:name` — **required** registration name; a missing key raises `KeyError`.
    * `:window_size` — outcomes retained in the rolling window (default `20`).
    * `:error_rate_threshold` — float in `(0.0, 1.0]` (default `0.5`).
    * `:min_calls_in_window` — evidence floor before the rate is evaluated (default `10`).
    * `:reset_timeout_ms` — time the breaker stays open (default `30_000`).
    * `:half_open_max_probes` — probes admitted while half-open (default `1`).
    * `:clock` — zero-arity function returning milliseconds (default monotonic time).

  Unknown options are ignored. The breaker starts `:closed` with an empty window.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Runs `func` through the breaker.

  Returns `{:ok, value}` / `{:error, reason}` verbatim when `func` returns such a tuple,
  `{:error, {:unexpected_return, other}}` for any other return value, `{:error, exception}`
  when `func` raises, and `{:error, :circuit_open}` when the breaker refuses to execute.
  """
  @spec call(GenServer.server(), (-> any())) :: {:ok, any()} | {:error, any()}
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func}, :infinity)
  end

  @doc """
  Returns the current breaker state, performing the lazy open → half-open expiry check.

  Never executes a probe and never consumes a probe slot.
  """
  @spec state(GenServer.server()) :: breaker_state()
  def state(name) do
    GenServer.call(name, :state, :infinity)
  end

  @doc """
  Forces the breaker back to `:closed` from any state.

  Empties the outcome window, clears the open timestamp and zeroes the probe counter.
  Not a no-op on a closed breaker: accumulated failures are discarded. Idempotent.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(name) do
    GenServer.call(name, :reset, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    breaker = %__MODULE__{
      window_size: Keyword.get(opts, :window_size, @default_window_size),
      error_rate_threshold:
        Keyword.get(opts, :error_rate_threshold, @default_error_rate_threshold),
      min_calls_in_window: Keyword.get(opts, :min_calls_in_window, @default_min_calls_in_window),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, @default_reset_timeout_ms),
      half_open_max_probes:
        Keyword.get(opts, :half_open_max_probes, @default_half_open_max_probes),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    }

    {:ok, breaker}
  end

  @impl GenServer
  def handle_call({:call, func}, _from, breaker) do
    breaker
    |> maybe_half_open()
    |> handle_execution(func)
  end

  def handle_call(:state, _from, breaker) do
    breaker = maybe_half_open(breaker)
    {:reply, breaker.state, breaker}
  end

  def handle_call(:reset, _from, breaker) do
    {:reply, :ok, close(breaker)}
  end

  # ---------------------------------------------------------------------------
  # Execution per state
  # ---------------------------------------------------------------------------

  defp handle_execution(%__MODULE__{state: :open} = breaker, _func) do
    {:reply, {:error, :circuit_open}, breaker}
  end

  defp handle_execution(%__MODULE__{state: :closed} = breaker, func) do
    {outcome, reply} = execute(func)
    breaker = breaker |> record(outcome) |> maybe_trip()
    {:reply, reply, breaker}
  end

  defp handle_execution(%__MODULE__{state: :half_open} = breaker, func) do
    if breaker.probes_in_flight >= breaker.half_open_max_probes do
      {:reply, {:error, :circuit_open}, breaker}
    else
      breaker = %{breaker | probes_in_flight: breaker.probes_in_flight + 1}
      {outcome, reply} = execute(func)

      breaker =
        case outcome do
          :success -> close(breaker)
          :failure -> open(breaker)
        end

      {:reply, reply, breaker}
    end
  end

  # ---------------------------------------------------------------------------
  # Outcome classification
  # ---------------------------------------------------------------------------

  @spec execute((-> any())) :: {outcome(), {:ok, any()} | {:error, any()}}
  defp execute(func) do
    case func.() do
      {:ok, _value} = ok -> {:success, ok}
      {:error, _reason} = error -> {:failure, error}
      other -> {:failure, {:error, {:unexpected_return, other}}}
    end
  rescue
    exception -> {:failure, {:error, exception}}
  end

  # ---------------------------------------------------------------------------
  # Window and state transitions
  # ---------------------------------------------------------------------------

  defp record(breaker, outcome) do
    window = Enum.take([outcome | breaker.window], breaker.window_size)
    %{breaker | window: window}
  end

  defp maybe_trip(breaker) do
    total = length(breaker.window)
    errors = Enum.count(breaker.window, &(&1 == :failure))

    if total > 0 and total >= breaker.min_calls_in_window and
         errors / total >= breaker.error_rate_threshold do
      open(breaker)
    else
      breaker
    end
  end

  defp maybe_half_open(%__MODULE__{state: :open, opened_at: opened_at} = breaker)
       when is_integer(opened_at) or is_float(opened_at) do
    if now(breaker) - opened_at >= breaker.reset_timeout_ms do
      %{breaker | state: :half_open, window: [], probes_in_flight: 0}
    else
      breaker
    end
  end

  defp maybe_half_open(breaker), do: breaker

  defp open(breaker) do
    %{breaker | state: :open, opened_at: now(breaker), window: [], probes_in_flight: 0}
  end

  defp close(breaker) do
    %{breaker | state: :closed, opened_at: nil, window: [], probes_in_flight: 0}
  end

  defp now(breaker), do: breaker.clock.()
end