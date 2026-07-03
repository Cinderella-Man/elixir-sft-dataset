Implement the private `schedule_retry/6` function. It is called when an attempt
returns a transient error and there is still retry budget remaining. Its arguments
are `(func, next_attempt, opts, from, reason, state)`, where `next_attempt` is the
upcoming 1-indexed retry number, `reason` is the error reason from the failed
attempt, `from` is the original `GenServer.call` caller, and `state` holds the
injected `clock` and `random` functions.

It should read `:base_delay_ms` (default `100`), `:max_delay_ms` (default `10_000`),
and the optional `:on_retry` callback from `opts`. Compute the backoff for the
0-indexed attempt `n = next_attempt - 1` as `min(base_delay_ms * 2^n, max_delay_ms)`,
using a left bit shift for the power of two (clamp the shift amount to `50` to avoid
runaway shifts). Then add random jitter: if the delay is greater than `0`, obtain
`jitter` by calling `state.random` with the delay (yielding a value in `0..delay-1`),
otherwise use `0`; the total wait is `delay + jitter`.

If an `:on_retry` callback was provided, invoke it as `on_retry.(next_attempt, reason,
total_wait)` before scheduling. Finally, schedule the retry by sending a
`{:retry, func, next_attempt, opts, from}` message to `self()` after `total_wait`
milliseconds using `Process.send_after/3`, so the GenServer stays free to serve other
callers while waiting.

```elixir
defmodule ClassifiedRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff,
  classifying errors as transient (retryable) or permanent (non-retryable),
  with an optional on_retry callback.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()}
          | {:error, :permanent, any()}
          | {:error, :retries_exhausted, any()}
  def execute(server, func, opts \\ []) do
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

      {:error, :permanent, reason} ->
        GenServer.reply(from, {:error, :permanent, reason})

      {:error, :transient, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :retries_exhausted, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, reason, state)
        end
    end
  end

  defp schedule_retry(func, next_attempt, opts, from, reason, state) do
    # TODO
  end
end
```