  test "identical data yields identical etag; different data differs", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, e1} = ConditionalObjectStorage.put_object(os, "b", "k", "same")
    {:ok, e2} = ConditionalObjectStorage.put_object(os, "b", "k", "same")
    {:ok, e3} = ConditionalObjectStorage.put_object(os, "b", "k", "different")
    assert e1 == e2
    assert e1 != e3
  end