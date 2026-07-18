  test "custom :key option is honored" do
    base = [%{sku: "a", qty: 1}]
    ours = [%{sku: "a", qty: 2}]
    theirs = [%{sku: "a", qty: 1}]

    assert RecordMerge.merge(base, ours, theirs, key: :sku) ==
             %{merged: [%{sku: "a", qty: 2}], conflicts: []}
  end