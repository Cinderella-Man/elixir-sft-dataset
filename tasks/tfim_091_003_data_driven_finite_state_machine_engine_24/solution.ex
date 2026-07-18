  test "the guard receives the whole record including state and domain fields" do
    parent = self()

    spy = fn r ->
      send(parent, {:saw, r})
      Map.get(r, :ok?)
    end

    m = Workflow.define(:a, [{:go, :a, :b, spy}])
    rec = Workflow.new(m, %{ok?: true, meta: %{z: 9}})

    assert {:ok, %{state: :b, meta: %{z: 9}, ok?: true}} =
             Workflow.transition(m, rec, :go)

    assert_received {:saw, %{state: :a, ok?: true, meta: %{z: 9}}}
  end