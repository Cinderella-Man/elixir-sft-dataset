Implement the GenServer `init/1` callback. It receives the keyword list of options
passed to `start_link/1`. It must read two configurable injection points from the
options and store them in the initial state:

- `:clock` — a zero-arity function returning the current time in milliseconds. If the
  option is absent, default to `fn -> System.monotonic_time(:millisecond) end`.
- `:random` — a one-arity function that takes a max integer and returns a random
  integer in `0..max-1`. If the option is absent, default to
  `fn max -> :rand.uniform(max) - 1 end`.

Return `{:ok, state}` where `state` is a map holding both functions under the keys
`:clock` and `:random`.

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
    # TODO
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