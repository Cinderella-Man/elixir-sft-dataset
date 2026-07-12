  test "partitions records into matched, only_in_left and only_in_right" do
    config = config!(key_fields: [:id])

    report =
      TolerantReconciler.run(config, [%{id: 1}, %{id: 2}], [%{id: 1}, %{id: 3}])

    assert length(report.matched) == 1
    assert report.only_in_left == [%{id: 2}]
    assert report.only_in_right == [%{id: 3}]
  end