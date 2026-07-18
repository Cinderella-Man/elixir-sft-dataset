  test "a nil key does not match a present key" do
    config = config!(key_fields: [:id])

    report = TolerantReconciler.run(config, [%{value: 7}], [%{id: 1, value: 7}])

    assert report.matched == []
    assert report.only_in_left == [%{value: 7}]
    assert report.only_in_right == [%{id: 1, value: 7}]
  end