  test "custom :key option uses a different identifier field" do
    old = [%{sku: "a"}, %{sku: "b"}, %{sku: "c"}]
    new = [%{sku: "c"}, %{sku: "a"}, %{sku: "b"}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new, key: :sku)

    assert moved == [%{sku: "c", from: 2, to: 0}]
  end