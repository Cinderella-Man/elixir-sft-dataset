  test "counts on an empty report is all zeros" do
    counts = MultiKeyReconciler.counts(MultiKeyReconciler.classify([], [], key_fields: [:id]))

    assert counts == %{
             one_to_one: 0,
             one_to_many: 0,
             many_to_one: 0,
             many_to_many: 0,
             only_in_left: 0,
             only_in_right: 0,
             ambiguous: 0
           }
  end