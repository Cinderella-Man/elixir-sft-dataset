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
    GenServer.start_link(__MODULE__, %{flush_interval_ms: flush_interval_ms}, server_opts)
  end

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

  @spec pending_count(GenServer.server(), term()) :: non_neg_integer()
  def pending_count(server, key) do
    GenServer.call(server, {:pending_count, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(config) do
    {:ok, Map.put(config, :batches, %{})}
  end

  @impl GenServer
  def handle_call({:submit, key, item, flush_fn, max_batch_size}, from, state) do
    case Map.fetch(state.batches, key) do
      :error ->
        timer_ref = Process.send_after(self(), {:flush_timer, key}, state.flush_interval_ms)

        batch = %{
          items: [item],
          callers: [from],
          flush_fn: flush_fn,
          max_batch_size: max_batch_size,
          timer_ref: timer_ref
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
          | items: batch.items ++ [item],
            callers: batch.callers ++ [from]
        }

        new_state = put_in(state, [:batches, key], updated_batch)

        if length(updated_batch.items) >= updated_batch.max_batch_size do
          {:noreply, do_flush(key, new_state)}
        else
          {:noreply, new_state}
        end
    end
  end

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
      {:ok, %{items: items}} when items == [] ->
        {:noreply, do_flush(key, state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:batch_done, key, result}, state) do
    case Map.pop(state.batches, key) do
      {%{callers: callers}, new_batches} ->
        Enum.each(callers, &GenServer.reply(&1, result))
        {:noreply, %{state | batches: new_batches}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_flush(key, state) do
    batch = state.batches[key]

    if batch.timer_ref, do: Process.cancel_timer(batch.timer_ref)

    items = batch.items
    flush_fn = batch.flush_fn
    parent = self()

    flushing_batch = %{batch | items: [], timer_ref: nil}
    state = put_in(state, [:batches, key], flushing_batch)

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

      send(parent, {:batch_done, key, result})
    end)

    state
  end
end
