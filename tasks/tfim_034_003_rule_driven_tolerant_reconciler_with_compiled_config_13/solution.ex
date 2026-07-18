  test "empty inputs" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [], [])

    assert report == %{matched: [], only_in_left: [], only_in_right: []}
  end