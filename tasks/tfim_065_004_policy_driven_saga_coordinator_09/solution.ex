  test "invalid on_error policy raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      PolicySaga.step(PolicySaga.new(), :a, fn _ -> {:ok, 1} end, fn _ -> :ok end,
        on_error: :explode
      )
    end
  end