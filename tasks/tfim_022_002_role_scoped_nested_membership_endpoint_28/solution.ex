  test "AuthPlug.init/1 returns its options unchanged" do
    assert AuthPlug.init(store: :some_store) == [store: :some_store]
    assert AuthPlug.init([]) == []
    assert AuthPlug.init(foo: 1, bar: 2) == [foo: 1, bar: 2]
  end