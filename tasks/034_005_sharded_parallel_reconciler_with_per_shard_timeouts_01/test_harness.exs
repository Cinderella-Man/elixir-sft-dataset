defmodule ParallelReconcilerTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  # A record's shard index, mirroring the documented partitioning rule.
  defp shard_of(key_tuple, shards), do: :erlang.phash2(key_tuple, shards)

  defp setify(r) do
    {
      r.matched |> Enum.map(fn m -> {m.left.id, m.differences} end) |> Enum.sort(),
      r.only_in_left |> Enum.map(& &1.id) |> Enum.sort(),
      r.only_in_right |> Enum.map(& &1.id) |> Enum.sort(),
      r.timed_out_shards,
      r.failed_shards
    }
  end

  # ---------------------------------------------------------------------------
  # Basic matching / result shape
  # ---------------------------------------------------------------------------

  test "matched, only-left, and only-right are classified correctly" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 3, name: "Carol"}]

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)

    assert Enum.map(r.matched, & &1.left.id) == [1]
    assert r.only_in_left == [%{id: 2, name: "Bob"}]
    assert r.only_in_right == [%{id: 3, name: "Carol"}]
    assert r.timed_out_shards == []
    assert r.failed_shards == []
  end

  test "both lists empty yields empty everything" do
    r = ParallelReconciler.reconcile_parallel([], [], key_fields: [:id])

    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []
    assert r.timed_out_shards == []
    assert r.failed_shards == []
  end

  test "identical matched records have an empty differences map" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alice", age: 30}]

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)
    [entry] = r.matched
    assert entry.differences == %{}
  end

  test "differing fields are reported with left/right values" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 31}]

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)
    [entry] = r.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             age: %{left: 30, right: 31}
           }
  end

  test "matched entry carries the full original left and right records" do
    left = [%{id: 1, name: "Alice", role: "admin"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)
    [entry] = r.matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alice", role: "user"}
  end

  test "a field missing from one record is diffed as nil vs present value" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)
    [entry] = r.matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  # ---------------------------------------------------------------------------
  # compare_fields
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are diffed but keeps full records" do
    left = [%{id: 1, name: "Alice", internal_ref: "old"}]
    right = [%{id: 1, name: "Alice", internal_ref: "new"}]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: 1,
        compare_fields: [:name]
      )

    [entry] = r.matched
    assert entry.differences == %{}
    assert entry.left == %{id: 1, name: "Alice", internal_ref: "old"}
    assert entry.right == %{id: 1, name: "Alice", internal_ref: "new"}
  end

  test "omitting compare_fields compares all non-key fields" do
    left = [%{id: 1, a: 1, b: 2}]
    right = [%{id: 1, a: 9, b: 2}]

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)
    [entry] = r.matched
    assert entry.differences == %{a: %{left: 1, right: 9}}
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key matches only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:org_id, :user_id],
        shards: 3
      )

    assert Enum.map(r.matched, & &1.left.name) == ["Alice"]
    assert length(r.only_in_left) == 1
    assert length(r.only_in_right) == 1
    assert r.timed_out_shards == []
    assert r.failed_shards == []
  end

  # ---------------------------------------------------------------------------
  # Custom :compare callback
  # ---------------------------------------------------------------------------

  test "a custom compare that deems values equal suppresses the difference" do
    ci = fn _f, a, b ->
      down = fn x -> if is_binary(x), do: String.downcase(x), else: x end
      down.(a) == down.(b)
    end

    left = [%{id: 1, name: "ALICE"}]
    right = [%{id: 1, name: "alice"}]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: 1,
        compare: ci
      )

    [entry] = r.matched
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # Aggregation across shards (default shards & timeout, default compare)
  # ---------------------------------------------------------------------------

  test "results aggregate correctly across the default shard count" do
    left = for k <- 1..50, do: %{id: k, v: k}
    right = for k <- 25..75, do: %{id: k, v: if(rem(k, 2) == 0, do: k, else: k + 1000)}

    r = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id])

    assert Enum.map(r.matched, & &1.left.id) |> Enum.sort() == Enum.to_list(25..50)
    assert Enum.map(r.only_in_left, & &1.id) |> Enum.sort() == Enum.to_list(1..24)
    assert Enum.map(r.only_in_right, & &1.id) |> Enum.sort() == Enum.to_list(51..75)
    assert r.timed_out_shards == []
    assert r.failed_shards == []

    # odd ids in 25..49 differ, even ids don't
    diffed = for m <- r.matched, m.differences != %{}, do: m.left.id
    assert Enum.sort(diffed) == 25..49 |> Enum.filter(&(rem(&1, 2) == 1))
  end

  # ---------------------------------------------------------------------------
  # Per-shard timeout & worker kill
  # ---------------------------------------------------------------------------

  test "a shard that exceeds :timeout is recorded and its worker is killed" do
    test_pid = self()

    slow = fn _f, _a, _b ->
      send(test_pid, {:worker, self()})
      Process.sleep(10_000)
      true
    end

    left = [%{id: 1, v: 1}]
    right = [%{id: 1, v: 2}]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: 1,
        timeout: 100,
        compare: slow
      )

    assert r.timed_out_shards == [0]
    assert r.failed_shards == []
    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []

    assert_receive {:worker, worker_pid}, 500
    ref = Process.monitor(worker_pid)
    assert_receive {:DOWN, ^ref, :process, ^worker_pid, _reason}, 1000
  end

  # ---------------------------------------------------------------------------
  # Callback failure isolation
  # ---------------------------------------------------------------------------

  test "a raising :compare crashes only its shard and does not crash the call" do
    boom = fn _f, _a, _b -> raise "boom" end

    left = [%{id: 1, v: 1}]
    right = [%{id: 1, v: 2}]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: 1,
        compare: boom
      )

    assert r.failed_shards == [0]
    assert r.timed_out_shards == []
    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []
  end

  test "a crash in one shard leaves other shards' results intact" do
    shards = 4
    boom_id = 0
    sb = shard_of({boom_id}, shards)

    goods =
      1..500
      |> Enum.filter(fn k -> shard_of({k}, shards) != sb end)
      |> Enum.take(3)

    left = [%{id: boom_id, v: :boom} | Enum.map(goods, &%{id: &1, v: :x})]
    right = [%{id: boom_id, v: :other} | Enum.map(goods, &%{id: &1, v: :y})]

    compare = fn _f, a, b ->
      if a == :boom or b == :boom, do: raise("boom"), else: a == b
    end

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: shards,
        compare: compare
      )

    assert r.failed_shards == [sb]
    assert r.timed_out_shards == []
    assert Enum.map(r.matched, & &1.left.id) |> Enum.sort() == Enum.sort(goods)
    assert r.only_in_left == []
    assert r.only_in_right == []

    for m <- r.matched do
      assert m.differences == %{v: %{left: :x, right: :y}}
    end
  end

  # The shard indexes recorded when workers crash are derived from
  # `:erlang.phash2(key, shards)` using the DEFAULT shard count (4). Spreading
  # many raising keys across the whole key space forces every default shard to
  # crash, so `:failed_shards` must be exactly [0, 1, 2, 3]. A different default
  # (3 or 5) would yield [0, 1, 2] or [0, 1, 2, 3, 4] respectively.
  test "failed shard indexes reflect the default shard count of four" do
    boom = fn _f, _a, _b -> raise "boom" end
    recs = for k <- 1..300, do: %{id: k, v: k}

    r =
      ParallelReconciler.reconcile_parallel(recs, recs,
        key_fields: [:id],
        compare: boom
      )

    assert r.failed_shards == [0, 1, 2, 3]
    assert r.timed_out_shards == []
    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  test "missing :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], [])
    end
  end

  test "nil :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: nil)
    end
  end

  test "non-list :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: :id)
    end
  end

  test "empty :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: [])
    end
  end

  test "non-atom element in :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: ["id"])
    end
  end

  test "non-positive :shards raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: [:id], shards: 0)
    end
  end

  # Validation of :shards happens BEFORE any work, so `shards: 0` must raise even
  # when there is nothing to reconcile. With empty inputs no `phash2/2` is ever
  # called, so this isolates the `shards > 0` guard from any incidental error a
  # zero shard count might otherwise trigger downstream.
  test "zero :shards raises ArgumentError even with empty inputs" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([], [], key_fields: [:id], shards: 0)
    end
  end

  test "non-integer :shards raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: [:id], shards: :x)
    end
  end

  test "non-positive :timeout raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelReconciler.reconcile_parallel([%{id: 1}], [%{id: 1}], key_fields: [:id], timeout: 0)
    end
  end

  # 1 is a valid (positive integer) timeout and must be accepted, not rejected.
  # Empty inputs finish immediately, so no shard can time out and the call must
  # return the empty result map rather than raising.
  test "a :timeout of 1 millisecond is accepted at the positive boundary" do
    r = ParallelReconciler.reconcile_parallel([], [], key_fields: [:id], timeout: 1)

    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []
    assert r.timed_out_shards == []
    assert r.failed_shards == []
  end

  # ---------------------------------------------------------------------------
  # Partition invariance (property)
  # ---------------------------------------------------------------------------

  property "the result set is invariant to the shard count" do
    check all(
            ids <- uniq_list_of(integer(1..30), max_length: 12),
            shards <- integer(1..6),
            max_runs: 25
          ) do
      left = Enum.map(ids, fn k -> %{id: k, v: rem(k, 3)} end)

      right =
        ids
        |> Enum.filter(fn k -> rem(k, 2) == 0 end)
        |> Enum.map(fn k -> %{id: k, v: rem(k, 3) + 1} end)

      base = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: 1)
      par = ParallelReconciler.reconcile_parallel(left, right, key_fields: [:id], shards: shards)

      assert setify(base) == setify(par)
    end
  end

  test "a timeout in one shard leaves other shards' results intact" do
    shards = 4
    slow_id = 0
    ss = shard_of({slow_id}, shards)

    goods =
      1..500
      |> Enum.filter(fn k -> shard_of({k}, shards) != ss end)
      |> Enum.take(3)

    left = [%{id: slow_id, v: :slow} | Enum.map(goods, &%{id: &1, v: :x})]
    right = [%{id: slow_id, v: :slow2} | Enum.map(goods, &%{id: &1, v: :y})]

    compare = fn _f, a, b ->
      if a == :slow or b == :slow or a == :slow2 or b == :slow2 do
        Process.sleep(10_000)
        true
      else
        a == b
      end
    end

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: shards,
        timeout: 200,
        compare: compare
      )

    assert r.timed_out_shards == [ss]
    assert r.failed_shards == []
    assert Enum.map(r.matched, & &1.left.id) |> Enum.sort() == Enum.sort(goods)
    assert r.only_in_left == []
    assert r.only_in_right == []
  end

  test "multiple timed-out shards are listed once each in ascending order" do
    slow = fn _f, _a, _b ->
      Process.sleep(10_000)
      true
    end

    recs = for k <- 1..300, do: %{id: k, v: k}

    r =
      ParallelReconciler.reconcile_parallel(recs, recs,
        key_fields: [:id],
        timeout: 150,
        compare: slow
      )

    assert r.timed_out_shards == [0, 1, 2, 3]
    assert r.failed_shards == []
    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []
  end

  test "compare_fields set to nil compares every non-key field" do
    left = [%{id: 1, a: 1, b: 2}]
    right = [%{id: 1, a: 9, b: 8}]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: 1,
        compare_fields: nil
      )

    [entry] = r.matched
    assert entry.differences == %{a: %{left: 1, right: 9}, b: %{left: 2, right: 8}}
  end

  test "the default :timeout lets a shard slower than a fraction of it complete" do
    slowish = fn _f, a, b ->
      Process.sleep(200)
      a == b
    end

    left = [%{id: 1, v: 1}]
    right = [%{id: 1, v: 2}]

    r =
      ParallelReconciler.reconcile_parallel(left, right,
        key_fields: [:id],
        shards: 1,
        compare: slowish
      )

    assert r.timed_out_shards == []
    assert Enum.map(r.matched, & &1.left.id) == [1]
  end
end
