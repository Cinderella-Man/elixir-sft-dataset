  test "start_link registers the process under the given :name" do
    name = :lru_named_registration_test

    {:ok, _pid} = LRUCache.start_link(capacity: 3, name: name, clock: &Clock.now/0)

    :ok = LRUCache.put(name, :a, 1)
    assert {:ok, 1} = LRUCache.get(name, :a)
    assert LRUCache.size(name) == 1
  end