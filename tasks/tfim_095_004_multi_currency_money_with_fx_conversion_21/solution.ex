  test "total/3 raises when any element uses an unknown currency" do
    assert_raise ArgumentError, fn ->
      Money.total([Money.new(1, :USD), Money.new(1, :JPY)], :USD, @rates)
    end
  end