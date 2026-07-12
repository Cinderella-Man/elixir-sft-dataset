# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir GenServer module called `RetryWorker` that executes a function with exponential backoff and jitter on failure.

I need these functions in the public API:

- `RetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, default to `fn max -> :rand.uniform(max) - 1 end`. It should also accept a `:name` option for process registration.

- `RetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. If `func` returns `{:ok, result}`, return `{:ok, result}` immediately. If `func` returns `{:error, reason}`, schedule a retry with exponential backoff. The opts keyword list must support: `:max_retries` (integer, default 3), `:base_delay_ms` (integer, default 100), and `:max_delay_ms` (integer, default 10_000). The call should block the caller until the function eventually succeeds or all retries are exhausted. When all retries are exhausted return `{:error, :max_retries_exceeded, reason}` where reason is the last error reason.

The backoff delay for attempt N (0-indexed, so first retry is attempt 1) should be calculated as `min(base_delay_ms * 2^N, max_delay_ms)`. Then add random jitter in the range `0..delay-1` on top, so the actual wait is `delay + jitter` where jitter is obtained by calling the injected `:random` function with `delay` as the argument. Retries must be scheduled using `Process.send_after` so the GenServer doesn't block other callers while waiting.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts retries.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The buggy module

```elixir
defmodule RetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff and jitter upon failure.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @doc """
  Starts the RetryWorker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Executes a function with exponential backoff. Returns `{:ok, result}` or
  `{:error, :max_retries_exceeded, last_reason}`.
  """
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :max_retries_exceeded, any()}
  def execute(server, func, opts \\ []) do
    # Use :infinity because retries can take a long time
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    # Attempt 0 is the initial call
    do_execute(func, 0, opts, from, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, attempt, opts, from}, state) do
    do_execute(func, attempt, opts, from, state)
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp do_execute(func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, reason} ->
        if attempt > max_retries do
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, state)
        end
    end
  end

  defp schedule_retry(func, next_attempt, opts, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    # N=0 for the first retry (next_attempt 1) to get base_delay * 1
    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    Process.send_after(self(), {:retry, func, next_attempt, opts, from}, total_wait)
  end
end
```

## Failing test report

```
3 of 12 test(s) failed:

  * test returns error when all retries are exhausted
      
      
      Assertion with == failed
      code:  assert Counter.get() == 4
      left:  5
      right: 4
      

  * test max_retries of 0 means no retries at all
      
      
      Assertion with == failed
      code:  assert Counter.get() == 1
      left:  2
      right: 1
      

  * test returns the last error reason on exhaustion
      
      
      Assertion with == failed
      code:  assert last_reason == :fail_3
      left:  :fail_4
      right: :fail_3
```
