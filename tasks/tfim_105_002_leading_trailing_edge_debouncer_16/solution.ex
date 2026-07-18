  test "the :both trailing func runs exactly once when the burst settles" do
    EdgeDebouncer.call("k", 100, notify(:x), edge: :both)
    EdgeDebouncer.call("k", 100, notify(:x), edge: :both)

    # Leading, then exactly one trailing — never a third execution.
    assert_receive :x, 200
    assert_receive :x, 500
    refute_receive :x, 300
  end