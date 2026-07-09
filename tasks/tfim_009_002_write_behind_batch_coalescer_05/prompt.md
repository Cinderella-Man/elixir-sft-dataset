# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
        timer_ref = Process.send_after(self(), {:flush_timer, key}, state.flush_interval_ms)

        batch = %{
          # Prepend is O(1)
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

## Test harness — implement the `# TODO` test

```elixir
defmodule BatchCollectorTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = BatchCollector.start_link(flush_interval_ms: 500)
    %{bc: pid}
  end

  # -------------------------------------------------------
  # Basic submission and flushing
  # -------------------------------------------------------

  test "single item flushes after timer", %{bc: bc} do
    result =
      BatchCollector.submit(bc, :k, :item1, fn items ->
        {:ok, items}
      end)

    assert result == {:ok, [:item1]}
  end

  test "flush_fn result is returned to caller", %{bc: bc} do
    assert {:ok, 42} =
             BatchCollector.submit(bc, :k, :ignored, fn _items -> {:ok, 42} end)
  end

  test "error result is returned to caller", %{bc: bc} do
    assert {:error, :boom} =
             BatchCollector.submit(bc, :k, :ignored, fn _items -> {:error, :boom} end)
  end

  # -------------------------------------------------------
  # Batching — multiple items collected before flush
  # -------------------------------------------------------

  test "concurrent submitters are batched together", %{bc: bc} do
    # TODO
  end

  test "items arrive in submission order", %{bc: bc} do
    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          BatchCollector.submit(bc, :order, i, fn items -> {:ok, items} end)
        end)
      end

    Process.sleep(50)

    results = Task.await_many(tasks, 5_000)

    {:ok, items} = hd(results)
    assert items == Enum.sort(items)
  end

  # -------------------------------------------------------
  # Count threshold flush
  # -------------------------------------------------------

  test "batch flushes immediately when max_batch_size is reached", %{bc: bc} do
    {elapsed, results} =
      :timer.tc(fn ->
        tasks =
          for i <- 1..3 do
            Task.async(fn ->
              BatchCollector.submit(bc, :fast, i, fn items -> {:ok, items} end, max_batch_size: 3)
            end)
          end

        Task.await_many(tasks, 5_000)
      end)

    # Should flush well before the 500ms timer
    assert elapsed < 300_000

    assert Enum.all?(results, fn {:ok, items} -> length(items) == 3 end)
  end

  # -------------------------------------------------------
  # Timer flush
  # -------------------------------------------------------

  test "batch flushes on timer when count threshold not reached" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 100)

    {elapsed, result} =
      :timer.tc(fn ->
        BatchCollector.submit(bc, :timer_test, :item, fn items -> {:ok, items} end,
          max_batch_size: 100
        )
      end)

    assert result == {:ok, [:item]}
    assert elapsed >= 80_000
    assert elapsed < 300_000
  end

  # -------------------------------------------------------
  # Independent keys
  # -------------------------------------------------------

  test "different keys have independent batches", %{bc: bc} do
    {:ok, counter} = Agent.start_link(fn -> %{} end)

    flush_fn = fn items ->
      key = hd(items)

      Agent.update(counter, fn map ->
        Map.update(map, key, 1, &(&1 + 1))
      end)

      {:ok, key}
    end

    tasks =
      for key <- [:a, :b, :c] do
        Task.async(fn ->
          BatchCollector.submit(bc, key, key, flush_fn)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    assert {:ok, :a} in results
    assert {:ok, :b} in results
    assert {:ok, :c} in results

    counts = Agent.get(counter, & &1)
    assert counts[:a] == 1
    assert counts[:b] == 1
    assert counts[:c] == 1
  end

  # -------------------------------------------------------
  # Error broadcasting
  # -------------------------------------------------------

  test "error result is broadcast to all callers in the batch", %{bc: bc} do
    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          BatchCollector.submit(bc, :err, :item, fn _items -> {:error, :fail} end)
        end)
      end

    results = Task.await_many(tasks, 5_000)
    assert Enum.all?(results, &(&1 == {:error, :fail}))
  end

  test "exception in flush_fn is broadcast as {:error, {:exception, _}}", %{bc: bc} do
    tasks =
      for _ <- 1..3 do
        Task.async(fn ->
          BatchCollector.submit(bc, :raise, :item, fn _items -> raise "kaboom" end)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:error, {:exception, %RuntimeError{message: "kaboom"}}} -> true
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # Key clearing after flush
  # -------------------------------------------------------

  test "key is cleared after flush, allowing a new batch", %{bc: bc} do
    assert {:ok, [:first]} =
             BatchCollector.submit(bc, :k, :first, fn items -> {:ok, items} end)

    assert {:ok, [:second]} =
             BatchCollector.submit(bc, :k, :second, fn items -> {:ok, items} end)
  end

  test "key is cleared after error, allowing a new batch", %{bc: bc} do
    assert {:error, :oops} =
             BatchCollector.submit(bc, :k, :item, fn _ -> {:error, :oops} end)

    assert {:ok, :recovered} =
             BatchCollector.submit(bc, :k, :item, fn _ -> {:ok, :recovered} end)
  end

  # -------------------------------------------------------
  # pending_count
  # -------------------------------------------------------

  test "pending_count returns 0 for unknown key", %{bc: bc} do
    assert BatchCollector.pending_count(bc, :nothing) == 0
  end

  # -------------------------------------------------------
  # GenServer responsiveness
  # -------------------------------------------------------

  test "GenServer is not blocked during flush", %{bc: bc} do
    slow_task =
      Task.async(fn ->
        BatchCollector.submit(bc, :slow, :item, fn _items ->
          Process.sleep(500)
          {:ok, :slow_done}
        end)
      end)

    Process.sleep(50)

    {elapsed, result} =
      :timer.tc(fn ->
        BatchCollector.submit(bc, :fast, :item, fn items -> {:ok, items} end, max_batch_size: 1)
      end)

    assert result == {:ok, [:item]}
    assert elapsed < 200_000

    Task.await(slow_task, 5_000)
  end

  # -------------------------------------------------------
  # Named registration
  # -------------------------------------------------------

  test "named process registration works" do
    {:ok, _pid} = BatchCollector.start_link(flush_interval_ms: 100, name: :my_batcher)

    assert {:ok, [:hello]} =
             BatchCollector.submit(:my_batcher, :k, :hello, fn items -> {:ok, items} end)
  end
end
```
