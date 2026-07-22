Implement the private `do_flush/2` function. It takes a `key` and the current `state`
and performs the batch flush for that key, returning the updated state.

It should:

- Remove the batch for `key` from `state.batches` (use `Map.pop/2`), capturing both the
  batch and the remaining batches map. Removing it immediately clears the key so new
  submissions start a fresh batch and can't join the one being flushed.
- If the batch has a `timer_ref`, cancel it with `Process.cancel_timer/1` (the flush may
  have been triggered by the count threshold before the timer fired).
- Reverse the accumulated `items` (they were prepended for O(1) inserts) so `flush_fn`
  receives them in submission order.
- Spawn a `Task` (so the GenServer stays responsive) that calls `flush_fn` with the
  ordered items inside a `try/rescue`:
    - `{:ok, _}` and `{:error, _}` results are passed through unchanged.
    - Any other return value is wrapped as `{:ok, other}`.
    - If `flush_fn` raises, the result becomes `{:error, {:exception, exception}}`.
  After computing the result, the Task sends `{:batch_done, callers, result}` back to the
  GenServer (captured as `parent`) so it can reply to every waiting caller.
- Return the state with the batch removed (`%{state | batches: new_batches}`).

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
    # TODO
  end
end
```