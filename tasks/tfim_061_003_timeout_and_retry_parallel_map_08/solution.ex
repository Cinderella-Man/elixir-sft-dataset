  test "a crash in one element does not affect the others" do
    results =
      RetryMap.pmap([1, 2, 3], fn
        2 -> raise "only me"
        x -> x * 10
      end, max_concurrency: 3, timeout: 1000, max_attempts: 2)

    assert Enum.at(results, 0) == {:ok, 10}
    assert match?({:error, {:exception, _}}, Enum.at(results, 1))
    assert Enum.at(results, 2) == {:ok, 30}
  end