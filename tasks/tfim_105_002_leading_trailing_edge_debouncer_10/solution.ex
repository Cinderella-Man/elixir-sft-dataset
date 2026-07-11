  test "invalid edge raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      EdgeDebouncer.call("k", 100, notify(:x), edge: :bogus)
    end
  end