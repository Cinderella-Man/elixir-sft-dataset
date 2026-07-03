Implement the private `schedule_retry/5` function. It takes the zero-arity function
`func`, the `next_attempt` number, the `opts` keyword list, the `from` reference of
the blocked caller, and the GenServer `state`. It should read `:base_delay_ms`
(default `100`) and `:max_delay_ms` (default `10_000`) from `opts`. Treating the
first retry (`next_attempt == 1`) as exponent `N = 0`, compute
`N = next_attempt - 1`, clamp it with `shift = min(N, 50)` to avoid overflow, and
calculate the capped backoff delay as `min(base_delay_ms <<< shift, max_delay_ms)`
(i.e. `min(base_delay_ms * 2^N, max_delay_ms)`). Then add jitter: if the delay is
greater than `0`, obtain jitter by calling the injected random function
`state.random.(delay)` (which returns an integer in `0..delay-1`); otherwise use `0`.
The actual wait is `delay + jitter`. Finally, schedule the retry with
`Process.send_after/3`, sending `{:retry, func, next_attempt, opts, from}` to `self()`
after the computed wait so the GenServer stays free to serve other callers.

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
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, state)
        end
    end
  end

  defp schedule_retry(func, next_attempt, opts, from, state) do
    # TODO
  end
end
```