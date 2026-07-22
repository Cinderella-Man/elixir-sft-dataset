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

  test "flush_fn receives items in submission order, not value order" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 60_000)

    ff = fn items -> {:ok, items} end

    # Each item is only submitted once the previous one is confirmed buffered,
    # so submission order is fixed: 3, then 1, then 2. The values are chosen so
    # that sorted, reversed, and submission order are all different lists.
    t1 = Task.async(fn -> BatchCollector.submit(bc, :seq, 3, ff, max_batch_size: 3) end)
    assert await_pending(bc, :seq, 1) == 1

    t2 = Task.async(fn -> BatchCollector.submit(bc, :seq, 1, ff, max_batch_size: 3) end)
    assert await_pending(bc, :seq, 2) == 2

    # The third item reaches the threshold and flushes the batch.
    t3 = Task.async(fn -> BatchCollector.submit(bc, :seq, 2, ff, max_batch_size: 3) end)

    results = Task.await_many([t1, t2, t3], 5_000)

    assert Enum.all?(results, &(&1 == {:ok, [3, 1, 2]}))
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

  test "short flush_interval_ms fires the batch automatically without any threshold hit" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 25)
    parent = self()

    ff = fn items ->
      send(parent, {:auto_flushed, items})
      {:ok, items}
    end

    task = Task.async(fn -> BatchCollector.submit(bc, :auto, :solo, ff, max_batch_size: 500) end)

    # Nothing but the interval timer can flush a 1-item batch under a 500 threshold.
    assert_receive {:auto_flushed, [:solo]}, 2_000
    assert Task.await(task, 5_000) == {:ok, [:solo]}
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

  test "no second flush occurs after the count threshold triggers a flush" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 200)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, length(items)})
      {:ok, items}
    end

    t1 = Task.async(fn -> BatchCollector.submit(bc, :once, :a, ff, max_batch_size: 2) end)
    t2 = Task.async(fn -> BatchCollector.submit(bc, :once, :b, ff, max_batch_size: 2) end)

    [r1, r2] = Task.await_many([t1, t2], 1_000)
    assert {:ok, items} = r1
    assert length(items) == 2
    assert r1 == r2

    assert_receive {:flushed, 2}, 1_000
    # The 200ms timer deadline passes here; it must not cause a second flush.
    refute_receive {:flushed, _}, 600
  end

  test "default max_batch_size threshold is 10" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 60_000)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, length(items)})
      {:ok, items}
    end

    for i <- 1..9 do
      Task.async(fn -> BatchCollector.submit(bc, :d, i, ff) end)
    end

    buffered =
      Enum.reduce_while(1..200_000, 0, fn _, _ ->
        case BatchCollector.pending_count(bc, :d) do
          9 -> {:halt, 9}
          _ -> {:cont, 0}
        end
      end)

    assert buffered == 9
    # 9 < default 10: no flush from the (60s) timer nor from the threshold.
    refute_receive {:flushed, _}, 100

    Task.async(fn -> BatchCollector.submit(bc, :d, 10, ff) end)
    assert_receive {:flushed, 10}, 1_000
  end

  test "keys apply their own max_batch_size thresholds independently" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 60_000)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, hd(items), length(items)})
      {:ok, items}
    end

    Task.async(fn -> BatchCollector.submit(bc, :b, :b1, ff, max_batch_size: 3) end)
    Task.async(fn -> BatchCollector.submit(bc, :b, :b2, ff, max_batch_size: 3) end)
    Task.async(fn -> BatchCollector.submit(bc, :a, :a1, ff, max_batch_size: 2) end)
    Task.async(fn -> BatchCollector.submit(bc, :a, :a2, ff, max_batch_size: 2) end)

    buffered_b =
      Enum.reduce_while(1..200_000, 0, fn _, _ ->
        case BatchCollector.pending_count(bc, :b) do
          2 -> {:halt, 2}
          _ -> {:cont, 0}
        end
      end)

    assert buffered_b == 2
    # :a hits its own threshold of 2 and flushes...
    assert_receive {:flushed, aa, 2}, 1_000
    assert aa in [:a1, :a2]
    # ...while :b (threshold 3) stays buffered and must not flush.
    refute_receive {:flushed, _bb, _}, 300

    # Drain :b via its own threshold so no callers block forever.
    Task.async(fn -> BatchCollector.submit(bc, :b, :b3, ff, max_batch_size: 3) end)
    assert_receive {:flushed, cc, 3}, 1_000
    assert cc in [:b1, :b2]
  end

  test "pending_count reports one item while a batch is buffered" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 300)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, items})
      {:ok, items}
    end

    task = Task.async(fn -> BatchCollector.submit(bc, :pc, :only, ff, max_batch_size: 5) end)

    observed =
      Enum.reduce_while(1..200_000, 0, fn _, _ ->
        case BatchCollector.pending_count(bc, :pc) do
          0 -> {:cont, 0}
          n -> {:halt, n}
        end
      end)

    assert observed == 1
    assert_receive {:flushed, [:only]}, 1_000
    assert Task.await(task, 1_000) == {:ok, [:only]}
    assert BatchCollector.pending_count(bc, :pc) == 0
  end

  # Polls pending_count until the key holds at least `target` items, so that a
  # subsequent submit is guaranteed to be buffered after the earlier ones.
  defp await_pending(bc, key, target) do
    Enum.reduce_while(1..200_000, 0, fn _, _ ->
      case BatchCollector.pending_count(bc, key) do
        n when n >= target -> {:halt, n}
        _ -> {:cont, 0}
      end
    end)
  end

  test "a stale timer never flushes the key's successor batch early" do
    # Batch 1 for "k" flushes via the size threshold, but its timer message is
    # engineered to already be in flight. Batch 2 (same key) must keep
    # coalescing until ITS OWN timer/threshold — the stale message may not
    # flush it early with a single item.
    test_pid = self()
    flush_fn = fn items -> send(test_pid, {:flushed, items}) end

    {:ok, co} = BatchCollector.start_link(flush_interval_ms: 60)

    # Fill batch 1 to the threshold exactly as its timer nears firing.
    t1 = Task.async(fn -> BatchCollector.submit(co, "k", :a1, flush_fn, max_batch_size: 2) end)
    Process.sleep(55)
    t2 = Task.async(fn -> BatchCollector.submit(co, "k", :a2, flush_fn, max_batch_size: 2) end)
    assert_receive {:flushed, batch1}, 500
    assert Enum.sort(batch1) == [:a1, :a2]
    Task.await(t1)
    Task.await(t2)

    # Immediately open batch 2; the stale batch-1 timer fires ~now.
    t3 = Task.async(fn -> BatchCollector.submit(co, "k", :b1, flush_fn, max_batch_size: 10) end)

    # Within the stale window nothing may flush; batch 2's own 60ms timer
    # eventually flushes exactly [:b1].
    refute_receive {:flushed, _}, 40
    assert_receive {:flushed, [:b1]}, 500
    Task.await(t3)
  end
end
