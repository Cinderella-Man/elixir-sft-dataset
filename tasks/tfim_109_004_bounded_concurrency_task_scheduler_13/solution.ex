  test "invalid max_concurrency raises" do
    assert_raise ArgumentError, fn ->
      BoundedRunner.start_link(name: :bad, max_concurrency: 0)
    end
  end