  test "empty inputs produce an empty report" do
    report = MultiKeyReconciler.classify([], [], key_fields: [:id])

    assert report.one_to_one == []
    assert report.one_to_many == []
    assert report.many_to_one == []
    assert report.many_to_many == []
    assert report.only_in_left == []
    assert report.only_in_right == []
  end