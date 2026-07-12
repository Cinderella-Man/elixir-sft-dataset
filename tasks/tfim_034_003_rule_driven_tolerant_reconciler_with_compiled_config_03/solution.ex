  test "compile rejects missing key_fields" do
    assert TolerantReconciler.compile([]) == {:error, :missing_key_fields}
  end