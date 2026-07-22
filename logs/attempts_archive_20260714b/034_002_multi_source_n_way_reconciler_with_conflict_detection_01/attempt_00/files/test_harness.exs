defmodule MultiSourceReconcilerTest do
  use ExUnit.Case, async: false

  test "one entry per distinct key across all sources" do
    sources = %{
      crm: [%{id: 1, email: "a@x.com"}, %{id: 2, email: "b@x.com"}],
      billing: [%{id: 1, email: "a@x.com"}, %{id: 3, email: "c@x.com"}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])

    keys = entries |> Enum.map(& &1.key) |> MapSet.new()
    assert keys == MapSet.new([%{id: 1}, %{id: 2}, %{id: 3}])
    assert length(entries) == 3
  end

  test "present_in and missing_from reflect source membership" do
    sources = %{
      crm: [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}],
      billing: [%{id: 1, name: "Alice"}, %{id: 3, name: "Carol"}],
      support: [%{id: 1, name: "Alice"}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])

    e1 = Enum.find(entries, &(&1.key == %{id: 1}))
    assert MapSet.new(e1.present_in) == MapSet.new([:crm, :billing, :support])
    assert e1.missing_from == []

    e2 = Enum.find(entries, &(&1.key == %{id: 2}))
    assert e2.present_in == [:crm]
    assert MapSet.new(e2.missing_from) == MapSet.new([:billing, :support])

    e3 = Enum.find(entries, &(&1.key == %{id: 3}))
    assert e3.present_in == [:billing]
    assert MapSet.new(e3.missing_from) == MapSet.new([:crm, :support])
  end

  test "records map carries the full original record for each present source" do
    sources = %{
      crm: [%{id: 1, name: "Alice", plan: "pro"}],
      billing: [%{id: 1, name: "Alice", plan: "pro", balance: 0}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
    [e1] = entries

    assert e1.records[:crm] == %{id: 1, name: "Alice", plan: "pro"}
    assert e1.records[:billing] == %{id: 1, name: "Alice", plan: "pro", balance: 0}
    refute Map.has_key?(e1.records, :support)
  end

  test "agreeing sources produce an empty conflicts map" do
    sources = %{
      crm: [%{id: 1, name: "Alice", plan: "pro"}],
      billing: [%{id: 1, name: "Alice", plan: "pro"}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
    [e1] = entries
    assert e1.conflicts == %{}
  end

  test "a disagreement records every present source's value for that field" do
    sources = %{
      crm: [%{id: 1, email: "a@x.com", plan: "pro"}],
      billing: [%{id: 1, email: "a@x.com", plan: "pro"}],
      support: [%{id: 1, email: "a@X.com", plan: "pro"}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
    [e1] = entries

    assert e1.conflicts == %{
             email: %{crm: "a@x.com", billing: "a@x.com", support: "a@X.com"}
           }
  end

  test "a field missing from one present source conflicts with nil recorded" do
    sources = %{
      crm: [%{id: 1, score: 42}],
      billing: [%{id: 1}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
    [e1] = entries

    assert e1.conflicts == %{score: %{crm: 42, billing: nil}}
  end

  test "compare_fields restricts which fields are checked for conflicts" do
    sources = %{
      crm: [%{id: 1, name: "Alice", internal_ref: "old"}],
      billing: [%{id: 1, name: "Alice", internal_ref: "new"}]
    }

    entries =
      MultiSourceReconciler.reconcile(sources,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [e1] = entries
    assert e1.conflicts == %{}
  end

  test "composite key matches only when all key fields are equal" do
    sources = %{
      crm: [
        %{org_id: 1, user_id: 10, role: "admin"},
        %{org_id: 1, user_id: 20, role: "user"}
      ],
      billing: [
        %{org_id: 1, user_id: 10, role: "admin"},
        %{org_id: 2, user_id: 10, role: "user"}
      ]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:org_id, :user_id])

    both = Enum.find(entries, &(&1.key == %{org_id: 1, user_id: 10}))
    assert MapSet.new(both.present_in) == MapSet.new([:crm, :billing])

    only_crm = Enum.find(entries, &(&1.key == %{org_id: 1, user_id: 20}))
    assert only_crm.present_in == [:crm]

    only_billing = Enum.find(entries, &(&1.key == %{org_id: 2, user_id: 10}))
    assert only_billing.present_in == [:billing]
  end

  test "duplicate key within one source: last occurrence wins" do
    sources = %{
      crm: [%{id: 1, name: "Old"}, %{id: 1, name: "New"}],
      billing: [%{id: 1, name: "New"}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
    [e1] = entries

    assert e1.records[:crm] == %{id: 1, name: "New"}
    assert e1.conflicts == %{}
  end

  test "default compare uses union of all fields minus key fields" do
    sources = %{
      crm: [%{id: 1, a: 1, b: 2}],
      billing: [%{id: 1, a: 1, c: 9}]
    }

    entries = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
    [e1] = entries

    # :a agrees; :b present only in crm (nil in billing); :c present only in billing
    refute Map.has_key?(e1.conflicts, :a)
    refute Map.has_key?(e1.conflicts, :id)
    assert e1.conflicts[:b] == %{crm: 2, billing: nil}
    assert e1.conflicts[:c] == %{crm: nil, billing: 9}
  end
end
