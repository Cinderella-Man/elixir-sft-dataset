  test "failure at index 0 is reported with index 0" do
    assert {:error, {0, _reason}} =
             FailFastMap.pmap([:bad, 2, 3], fn
               :bad -> raise "nope"
               x -> x
             end, 3)
  end