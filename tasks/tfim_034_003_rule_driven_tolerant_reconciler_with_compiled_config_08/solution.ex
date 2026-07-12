  test "compile rejects an unknown rule for a field" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: [name: :fuzzy]) ==
             {:error, {:invalid_rule, :name}}
  end