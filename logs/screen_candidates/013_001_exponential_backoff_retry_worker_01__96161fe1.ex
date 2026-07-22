defmodule RetryWorker do
  @moduledoc """
  A `GenServer` that executes zero-arity functions, retrying failures with
  exponential backoff plus random jitter.

  ## Behaviour

  A caller invokes `execute/3` with a zero-arity function. The function is run
  inside the server process:

    * if it returns `{:ok, result}`, the caller receives `{:ok, result}`;
    * if it returns `{:error, reason}`, a retry is scheduled with
      `Process.send_after/3` and the caller keeps blocking;
    * when the retry budget is exhausted, the caller receives
      `{:error, :max_retries_exceeded, reason}` carrying the *last* error reason.

  Waiting is never done by sleeping inside the server: retries are scheduled as
  timers and callers are answered asynchronously with `GenServer.reply/2`. That
  means many `execute/3` calls can be in flight at once, each with its own
  independent backoff schedule, and replies are delivered in completion order
  rather than call order.

  ## Backoff

  For the retry with attempt number `k` (the first retry is attempt `1`), with
  `n = k - 1`:

      delay  = min(base_delay_ms * 2 ** n, max_delay_ms)
      jitter = random.(delay)          # only when delay > 0, otherwise 0
      wait   = delay + jitter

  The doubling exponent saturates at `50` so that a long retry chain can never
  produce an astronomically large integer. Because jitter is added *after* the
  clamp, the effective wait may exceed `:max_delay_ms`; with a random function
  honouring `0..delay-1` it lies within `delay..(2 * delay - 1)`.

  ## Injection

  Both the clock and the randomness source are injectable at `start_link/1`
  time, which makes tests fully deterministic (e.g. `random: fn _ -> 0 end`).
  The clock is only a hook held in the process state — actual waiting is
  realised by the timer, so injecting a clock does not change wait times.
  """

  use GenServer

  @default_max_retries 3
  @default_base_delay_ms 100
  @default_max_delay_ms 10_000

  # Upper bound for the doubling exponent, so `2 ** n` stays a sane integer.
  @max_shift 50

  @typedoc "Zero-arity function returning `{:ok, result}` or `{:error, reason}`."
  @type task_fun :: (-> {:ok, term()} | {:error, term()})

  @typedoc "Options accepted by `execute/3`."
  @type execute_opt ::
          {:max_retries, integer()}
          | {:base_delay_ms, non_neg_integer()}
          | {:max_delay_ms, non_neg_integer()}

  @typedoc "Options accepted by `start_link/1`."
  @type start_opt ::
          {:clock, (-> integer())}
          | {:random, (pos_integer() -> non_neg_integer())}
          | {:name, GenServer.name() | nil}

  @typedoc "Result returned by `execute/3`."
  @type result :: {:ok, term()} | {:error, :max_retries_exceeded, term()}

  @doc """
  Starts the retry worker.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:random` — one-arity function taking a positive integer `max` and
      returning an integer in `0..max-1`. Defaults to
      `fn max -> :rand.uniform(max) - 1 end`.
    * `:name` — optional name to register the process under. When absent or
      `nil` the process is started unregistered.

  Unknown options are ignored. Returns whatever `GenServer.start_link/3`
  returns, i.e. `{:ok, pid}` or `{:error, {:already_started, pid}}`.
  """
  @spec start_link([start_opt()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    clock = Keyword.get(opts, :clock) || (&default_clock/0)
    random = Keyword.get(opts, :random) || (&default_random/1)

    server_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, %{clock: clock, random: random}, server_opts)
  end

  @doc """
  Executes `func` on `server`, retrying failures with exponential backoff.

  The call blocks the caller until some attempt succeeds or the retry budget is
  exhausted; it never times out on its own.

  ## Options

    * `:max_retries` — number of retries *after* the initial attempt
      (default `#{@default_max_retries}`). The function is invoked at most
      `max_retries + 1` times. Values `<= 0` mean a single attempt.
    * `:base_delay_ms` — base backoff delay in milliseconds (default
      `#{@default_base_delay_ms}`).
    * `:max_delay_ms` — clamp for the pre-jitter delay in milliseconds
      (default `#{@default_max_delay_ms}`).

  Returns `{:ok, result}` when an attempt returns `{:ok, result}`, or
  `{:error, :max_retries_exceeded, reason}` where `reason` comes from the last
  failing attempt. `func` is expected to return only those two shapes; anything
  else (including raising) is not handled and will take the server down.
  """
  @spec execute(GenServer.server(), task_fun(), [execute_opt()]) :: result()
  def execute(server, func, opts \\ []) when is_function(func, 0) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:execute, func, opts}, from, state) do
    attempt(func, opts, 0, from, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:retry, func, opts, attempt, from}, state) do
    attempt(func, opts, attempt, from, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Runs one attempt and either replies to the caller or schedules the next try.
  # All the context needed to resume (func, attempt, opts, caller) travels with
  # the scheduled message, so the server keeps no per-execution bookkeeping.
  @spec attempt(task_fun(), keyword(), non_neg_integer(), GenServer.from(), map()) :: :ok
  defp attempt(func, opts, attempt, from, state) do
    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, reason} ->
        max_retries = Keyword.get(opts, :max_retries, @default_max_retries)

        if attempt < max_retries do
          schedule_retry(func, opts, attempt + 1, from, state)
        else
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
        end
    end

    :ok
  end

  @spec schedule_retry(task_fun(), keyword(), pos_integer(), GenServer.from(), map()) :: :ok
  defp schedule_retry(func, opts, next_attempt, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, @default_base_delay_ms)
    max_delay = Keyword.get(opts, :max_delay_ms, @default_max_delay_ms)

    delay = backoff_delay(base_delay, max_delay, next_attempt - 1)
    jitter = jitter(delay, state.random)

    Process.send_after(self(), {:retry, func, opts, next_attempt, from}, delay + jitter)

    :ok
  end

  # min(base * 2^n, max), with a saturating exponent.
  @spec backoff_delay(integer(), integer(), non_neg_integer()) :: integer()
  defp backoff_delay(base_delay, max_delay, exponent) do
    shift = min(exponent, @max_shift)
    min(base_delay * Bitwise.bsl(1, shift), max_delay)
  end

  # The random function is only consulted for a strictly positive delay.
  @spec jitter(integer(), (pos_integer() -> non_neg_integer())) :: integer()
  defp jitter(delay, random) when delay > 0, do: random.(delay)
  defp jitter(_delay, _random), do: 0

  @spec default_clock() :: integer()
  defp default_clock, do: System.monotonic_time(:millisecond)

  @spec default_random(pos_integer()) :: non_neg_integer()
  defp default_random(max), do: :rand.uniform(max) - 1
end