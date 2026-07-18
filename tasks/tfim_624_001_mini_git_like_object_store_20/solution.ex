  test "commit messages can contain newlines and special characters", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "data")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])

    message = "fix: handle edge case\n\nThis fixes a bug where\nnull bytes caused issues."
    {:ok, ch} = ObjectStore.commit(s, th, nil, message, "dev <dev@example.com>")

    {:ok, [entry]} = ObjectStore.log(s, ch)
    assert entry.message == message
    assert entry.author == "dev <dev@example.com>"
  end