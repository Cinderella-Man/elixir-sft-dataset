  test "compile rejects empty or non-atom key_fields" do
    assert TolerantReconciler.compile(key_fields: []) == {:error, :invalid_key_fields}
    assert TolerantReconciler.compile(key_fields: ["id"]) == {:error, :invalid_key_fields}
  end