  test "compile rejects invalid compare_fields" do
    assert TolerantReconciler.compile(key_fields: [:id], compare_fields: ["name"]) ==
             {:error, :invalid_compare_fields}
  end