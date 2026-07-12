  test "compile accepts all four rule kinds" do
    assert {:ok, _} =
             TolerantReconciler.compile(
               key_fields: [:id],
               rules: [
                 amount: {:numeric, 0.01},
                 name: :case_insensitive,
                 notes: :ignore,
                 status: :exact
               ]
             )
  end