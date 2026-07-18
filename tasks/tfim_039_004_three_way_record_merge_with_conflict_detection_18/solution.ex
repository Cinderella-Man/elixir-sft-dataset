  test "conflict descriptors are keyed by the custom :key option field" do
    base = []
    ours = [%{sku: "a", qty: 1}]
    theirs = [%{sku: "a", qty: 2}]

    assert RecordMerge.merge(base, ours, theirs, key: :sku) ==
             %{
               merged: [],
               conflicts: [
                 %{
                   sku: "a",
                   type: :add_add,
                   ours: %{sku: "a", qty: 1},
                   theirs: %{sku: "a", qty: 2}
                 }
               ]
             }
  end