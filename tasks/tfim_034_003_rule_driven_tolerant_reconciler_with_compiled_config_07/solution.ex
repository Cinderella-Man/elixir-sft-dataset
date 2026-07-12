  test "compile rejects non-keyword rules" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: %{name: :exact}) ==
             {:error, :invalid_rules}
  end