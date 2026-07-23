# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `start_link` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir GenServer module called `BatchCollector` that collects individual items submitted under a key and flushes them as a batch to a user-supplied function, so that multiple rapid writes are coalesced into a single batch operation.

I need these functions in the public API:

- `BatchCollector.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a required `:flush_interval_ms` option (the maximum time to wait before flushing a batch, even if the count threshold hasn't been reached).

- `BatchCollector.submit(server, key, item, flush_fn, opts \\ [])` which adds `item` to the batch buffer for `key`. The caller blocks until its batch is flushed. `flush_fn` is a single-arity function that receives the list of all collected items for that key (in submission order) and returns `{:ok, result}` or `{:error, reason}`. The optional `:max_batch_size` in opts (default 10) controls the count threshold — when the buffer for a key reaches this size, it flushes immediately without waiting for the timer.

  Returns whatever `flush_fn` returns. All callers whose items are in the same batch receive the same result.

- `BatchCollector.pending_count(server, key)` which returns the number of items currently buffered for the given key (0 if no pending batch).

The lifecycle of a batch for a given key works like this:
1. The first `submit` for a key starts a timer of `flush_interval_ms` and puts the item in the buffer.
2. Subsequent `submit` calls for the same key add their items to the buffer and register as waiters.
3. When either the timer fires OR `max_batch_size` is reached (whichever comes first), the batch is flushed: `flush_fn` is called with the full list of items in a spawned Task (so the GenServer remains responsive), and all waiting callers receive the result.
4. After the flush, the key is cleared for new batches.

If `flush_fn` raises an exception, all callers in that batch should receive `{:error, {:exception, exception}}`.

If a timer fires but the batch was already flushed (because the count threshold was hit first), the timer message should be harmlessly ignored.

Different keys are completely independent — they have separate buffers, timers, and thresholds.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `start_link` missing

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

  def start_link(opts) do
    # TODO
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
    case Map.fetch(state.batches, key) do
      :error ->
        # Requirement: First submit for a key starts the flush timer
        # The batch generation rides in the message: a stale timer whose batch
        # already flushed (threshold path) can never fire a SUCCESSOR batch —
        # key-presence alone cannot tell two generations apart. The send_after
        # ref is kept separately so threshold flushes still cancel the timer.
        gen = make_ref()

        timer_ref =
          Process.send_after(self(), {:flush_timer, key, gen}, state.flush_interval_ms)

        batch = %{
          # Prepend is O(1)
          items: [item],
          callers: [from],
          flush_fn: flush_fn,
          max_batch_size: max_batch_size,
          timer_ref: timer_ref,
          gen: gen
        }

        new_state = put_in(state, [:batches, key], batch)

        if max_batch_size <= 1 do
          {:noreply, do_flush(key, new_state)}
        else
          {:noreply, new_state}
        end

      {:ok, batch} ->
        updated_batch = %{
          batch
          | # Prepend is O(1)
            items: [item | batch.items],
            callers: [from | batch.callers]
        }

        new_state = put_in(state, [:batches, key], updated_batch)

        if length(updated_batch.items) >= updated_batch.max_batch_size do
          {:noreply, do_flush(key, new_state)}
        else
          {:noreply, new_state}
        end
    end
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
  def handle_info({:flush_timer, key, gen}, state) do
    case Map.fetch(state.batches, key) do
      # Requirement: flush when the timer fires and it is THIS batch's timer.
      {:ok, %{gen: ^gen}} ->
        {:noreply, do_flush(key, state)}

      # A ref mismatch is a stale timer for an earlier, already-flushed batch
      # generation; :error means the batch flushed and no successor exists.
      # Both are ignored harmlessly.
      _ ->
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

Reply with `start_link` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
