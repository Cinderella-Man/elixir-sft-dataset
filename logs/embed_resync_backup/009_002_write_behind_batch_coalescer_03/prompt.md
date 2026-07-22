Implement the `handle_call/3` clause that handles the `{:submit, key, item, flush_fn, max_batch_size}` message (the one used by `BatchCollector.submit/5`).

This clause registers a new item into the per-key batch buffer and blocks the caller until the batch is eventually flushed. Because the reply is sent later (when the batch flushes), this clause must always return `{:noreply, new_state}` — never reply directly.

Look up the current batch for `key` in `state.batches`:

- If there is **no existing batch** for the key (`Map.fetch/2` returns `:error`), this is the first submit for the key, so start the flush timer with `Process.send_after(self(), {:flush_timer, key}, state.flush_interval_ms)` and build a fresh batch map containing: `items: [item]`, `callers: [from]`, `flush_fn`, `max_batch_size`, and `timer_ref`. Store the batch in `state.batches` under `key`. Then, if `max_batch_size <= 1`, the single item already meets the threshold, so flush immediately via `do_flush(key, new_state)` and return its state; otherwise return the new state and wait for the timer or later submits.

- If there **is an existing batch** (`{:ok, batch}`), prepend the new `item` onto `batch.items` and the `from` onto `batch.callers` (prepend is O(1); `do_flush/2` reverses to restore submission order), and store the updated batch. If the number of buffered items now reaches `updated_batch.max_batch_size` (`length(updated_batch.items) >= updated_batch.max_batch_size`), flush immediately via `do_flush(key, new_state)`; otherwise return the new state and keep waiting.

In every case the return value is `{:noreply, ...}` because the waiting callers are answered from `do_flush/2`'s spawned task via the `{:batch_done, callers, result}` message.

```elixir
defmodule BatchCollector do
  @moduledoc """
  A GenServer that collects individual items submitted under a key and
  flushes them as a batch to a user-supplied function.

  Items accumulate in a per-key buffer. The buffer flushes when either:
    - the number of items reaches `:max_batch_size` (default 10), or
    - the `:flush_interval_ms` timer fires (whichever comes first).

  All callers whose items are in the same batch block until the flush
  completes and receive the same result from `flush_fn`.

  ## Example

      {:ok, pid} = BatchCollector.start_link(flush_interval_ms: 500)

      tasks = for i <- 1..3 do
        Task.async(fn ->
          BatchCollector.submit(pid, :writes, i, fn items ->
            {:ok, Enum.sum(items)}
          end)
        end)
      end

      results = Task.await_many(tasks)
      # All get {:ok, 6}
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    flush_interval_ms = Keyword.fetch!(opts, :flush_interval_ms)
    server_opts = Keyword.take(opts, [:name])
    # Initializing state with an empty batches map
    GenServer.start_link(
      __MODULE__,
      %{flush_interval_ms: flush_interval_ms, batches: %{}},
      server_opts
    )
  end

  @doc """
  Submits an item to the buffer for a specific key.
  The caller blocks until the batch is flushed.
  """
  @spec submit(
          GenServer.server(),
          term(),
          term(),
          (list() -> {:ok, term()} | {:error, term()}),
          keyword()
        ) :: {:ok, term()} | {:error, term()}
  def submit(server, key, item, flush_fn, opts \\ []) when is_function(flush_fn, 1) do
    max_batch_size = Keyword.get(opts, :max_batch_size, 10)
    GenServer.call(server, {:submit, key, item, flush_fn, max_batch_size}, :infinity)
  end

  @doc "Returns the number of items currently buffered for the given key."
  @spec pending_count(GenServer.server(), term()) :: non_neg_integer()
  def pending_count(server, key) do
    GenServer.call(server, {:pending_count, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:submit, key, item, flush_fn, max_batch_size}, from, state) do
    # TODO
  end

  @impl GenServer
  def handle_call({:pending_count, key}, _from, state) do
    count =
      case Map.fetch(state.batches, key) do
        {:ok, batch} -> length(batch.items)
        :error -> 0
      end

    {:reply, count, state}
  end

  @impl GenServer
  def handle_info({:flush_timer, key}, state) do
    case Map.fetch(state.batches, key) do
      # Requirement: Flush when timer fires and batch exists
      {:ok, _batch} ->
        {:noreply, do_flush(key, state)}

      # Ignore if already flushed via max_batch_size threshold
      :error ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:batch_done, callers, result}, state) do
    # Requirement: All callers in the same batch receive the same result
    Enum.each(callers, &GenServer.reply(&1, result))
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_flush(key, state) do
    # Requirement: After flush, the key is cleared immediately for new batches.
    # Popping now prevents race conditions where new items join a "dying" batch.
    {batch, new_batches} = Map.pop(state.batches, key)

    if batch.timer_ref, do: Process.cancel_timer(batch.timer_ref)

    # Submission order requires reversing since we used O(1) prepending
    items = Enum.reverse(batch.items)
    callers = batch.callers
    flush_fn = batch.flush_fn
    parent = self()

    # Requirement: flush_fn must be called in a spawned Task
    Task.start(fn ->
      result =
        try do
          case flush_fn.(items) do
            {:ok, _} = ok -> ok
            {:error, _} = err -> err
            other -> {:ok, other}
          end
        rescue
          exception -> {:error, {:exception, exception}}
        end

      send(parent, {:batch_done, callers, result})
    end)

    %{state | batches: new_batches}
  end
end
```