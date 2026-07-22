defmodule ReconcilerConcurrentTest do
  use ExUnit.Case, async: false

  test "single partition via reconcile/3" do
    left = [%{id: 1, v: 1}, %{id: 2, v: 2}]
    right = [%{id: 1, v: 9}, %{id: 3, v: 3}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert length(r.matched) == 1
    assert hd(r.matched).differences == %{v: %{left: 1, right: 9}}
    assert Enum.map(r.only_in_left, & &1.id) == [2]
    assert Enum.map(r.only_in_right, & &1.id) == [3]
  end

  test "reconcile_all processes each partition independently" do
    partitions = [
      %{id: :a, left: [%{id: 1, v: 1}], right: [%{id: 1, v: 2}]},
      %{id: :b, left: [%{id: 1}], right: []},
      %{id: :c, left: [], right: [%{id: 7}]}
    ]

    out = Reconciler.reconcile_all(partitions, key_fields: [:id])

    assert out.results |> Map.keys() |> Enum.sort() == [:a, :b, :c]
    assert hd(out.results[:a].matched).differences == %{v: %{left: 1, right: 2}}
    assert Enum.map(out.results[:b].only_in_left, & &1.id) == [1]
    assert Enum.map(out.results[:c].only_in_right, & &1.id) == [7]
  end

  test "partitions do not cross-match" do
    partitions = [
      %{id: 1, left: [%{id: 1, v: "a"}], right: [%{id: 2, v: "b"}]},
      %{id: 2, left: [%{id: 2, v: "b"}], right: [%{id: 1, v: "a"}]}
    ]

    out = Reconciler.reconcile_all(partitions, key_fields: [:id])

    assert out.results[1].matched == []
    assert out.results[2].matched == []
    assert out.summary == %{matched: 0, only_in_left: 2, only_in_right: 2}
  end

  test "summary rolls up totals across partitions" do
    partitions = [
      %{id: 1, left: [%{id: 1}, %{id: 2}], right: [%{id: 1}]},
      %{id: 2, left: [%{id: 3}], right: [%{id: 3}, %{id: 4}]}
    ]

    out = Reconciler.reconcile_all(partitions, key_fields: [:id])
    assert out.summary == %{matched: 2, only_in_left: 1, only_in_right: 1}
  end

  test "results are deterministic regardless of concurrency level" do
    partitions =
      Enum.map(1..20, fn n ->
        %{id: n, left: [%{id: n, v: n}], right: [%{id: n, v: n + 1}]}
      end)

    out1 = Reconciler.reconcile_all(partitions, key_fields: [:id], max_concurrency: 1)
    out8 = Reconciler.reconcile_all(partitions, key_fields: [:id], max_concurrency: 8)

    assert out1 == out8
    assert out1.summary.matched == 20
  end

  test "empty partition list yields empty results and zero summary" do
    out = Reconciler.reconcile_all([], key_fields: [:id])
    assert out.results == %{}
    assert out.summary == %{matched: 0, only_in_left: 0, only_in_right: 0}
  end

  test "compare_fields is applied within each partition" do
    partitions = [
      %{id: :p, left: [%{id: 1, name: "A", ref: "old"}], right: [%{id: 1, name: "A", ref: "new"}]}
    ]

    out = Reconciler.reconcile_all(partitions, key_fields: [:id], compare_fields: [:name])
    assert hd(out.results[:p].matched).differences == %{}
  end

  test "composite keys within partitions" do
    partitions = [
      %{
        id: :p,
        left: [%{org: 1, uid: 1, v: 1}, %{org: 1, uid: 2, v: 2}],
        right: [%{org: 1, uid: 1, v: 1}, %{org: 2, uid: 1, v: 9}]
      }
    ]

    out = Reconciler.reconcile_all(partitions, key_fields: [:org, :uid])
    res = out.results[:p]

    assert length(res.matched) == 1
    assert hd(res.matched).differences == %{}
    assert length(res.only_in_left) == 1
    assert length(res.only_in_right) == 1
  end

  test "missing compared field diffed as nil" do
    r = Reconciler.reconcile([%{id: 1, score: 42}], [%{id: 1}], key_fields: [:id])
    assert hd(r.matched).differences == %{score: %{left: 42, right: nil}}
  end

  test "reconcile/3 raises when key_fields missing" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], [])
    end
  end
end