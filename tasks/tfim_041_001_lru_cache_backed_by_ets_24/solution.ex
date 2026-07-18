  test "child_spec uses the name option as the child id" do
    name = unique_name()
    spec = LRUCache.child_spec(name: name, max_size: 2)

    assert %{id: ^name, start: {LRUCache, :start_link, [start_opts]}} = spec
    assert start_opts[:name] == name
    assert start_opts[:max_size] == 2
  end