  test "a non-integer max_attempts raises ArgumentError" do
    ok = fn _ -> {:ok, 1} end
    undo = fn _ -> {:ok, :undone} end

    for bad <- [:lots, 2.0, nil, -1, "3"] do
      assert_raise ArgumentError, fn ->
        RetrySaga.step(RetrySaga.new(), :a, ok, undo, max_attempts: bad)
      end
    end
  end