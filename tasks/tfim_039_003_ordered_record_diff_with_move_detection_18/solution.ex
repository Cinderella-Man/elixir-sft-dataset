  test "changed entries key their id under the custom :key option field" do
    old = [%{sku: "a", v: 1}, %{sku: "b", v: 2}]
    new = [%{sku: "a", v: 1}, %{sku: "b", v: 22}]

    %{changed: changed, moved: moved} = OrderedRecordDiff.diff(old, new, key: :sku)

    assert changed == [%{sku: "b", changes: %{v: {2, 22}}}]
    assert moved == []
  end