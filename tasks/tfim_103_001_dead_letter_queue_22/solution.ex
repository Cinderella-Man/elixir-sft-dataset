  test "start_link registers the server under the given :name option" do
    name = :dlq_name_option_registration_test

    pid = start_supervised!({DLQ, [clock: &Clock.now/0, name: name]}, id: :named_dlq)

    assert Process.whereis(name) == pid
    assert {:ok, id} = DLQ.push(name, "q", :via_name, :err, %{k: 1})
    assert [entry] = DLQ.peek(name, "q", 10)
    assert entry.id == id
    assert entry.message == :via_name
    assert entry.metadata == %{k: 1}
  end