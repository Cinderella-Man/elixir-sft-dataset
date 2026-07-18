  test "non-integer max_concurrency raises" do
    assert_raise ArgumentError, fn ->
      BoundedRunner.start_link(name: :bad_float, max_concurrency: 2.0)
    end
  end