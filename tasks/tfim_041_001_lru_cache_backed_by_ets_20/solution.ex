  test "a max_size of one is a legal start-up option" do
    name = unique_name()
    assert {:ok, pid} = LRUCache.start_link(name: name, max_size: 1)
    assert is_pid(pid)
    assert :ok = LRUCache.put(name, :a, 1)
    assert {:ok, 1} = LRUCache.get(name, :a)
  end