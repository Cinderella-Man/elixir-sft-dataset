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
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    flush_fn = fn items ->
      Agent.update(counter, &(&1 + 1))
      {:ok, Enum.sum(items)}
    end

    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          BatchCollector.submit(bc, :sum, i, flush_fn)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    # All callers get the same result
    assert Enum.all?(results, &(&1 == {:ok, 15}))

    # flush_fn was called exactly once
    assert Agent.get(counter, & &1) == 1
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
              BatchCollector.submit(bc, :fast, i, fn items -> {:ok, items} end,
                max_batch_size: 3
              )
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
        BatchCollector.submit(bc, :fast, :item, fn items -> {:ok, items} end,
          max_batch_size: 1
        )
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
