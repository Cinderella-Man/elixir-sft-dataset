  test "server can be registered under a name" do
    name = :"stream_reconciler_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id], name: name)
    on_exit(fn -> if Process.alive?(pid), do: StreamReconciler.stop(name) end)

    assert StreamReconciler.push_left(name, %{id: 1}) == :pending
    assert %{left: [%{id: 1}], right: []} = StreamReconciler.pending(name)
  end