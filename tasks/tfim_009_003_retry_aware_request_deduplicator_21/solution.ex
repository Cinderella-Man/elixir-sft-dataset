  test "registers under the :name option and is reachable by that name" do
    name = :retry_dedup_name_promise_srv
    {:ok, _} = RetryDedup.start_link(name: name)

    assert {:ok, 7} = RetryDedup.execute(name, "k", fn -> {:ok, 7} end)
  end