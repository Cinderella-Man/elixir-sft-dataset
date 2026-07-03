  test "raises for invalid :max_keys" do
    assert_raise ArgumentError, fn ->
      BoundedIdempotentPayments.start_link(max_keys: 0)
    end

    assert_raise ArgumentError, fn ->
      BoundedIdempotentPayments.start_link(max_keys: :lots)
    end
  end