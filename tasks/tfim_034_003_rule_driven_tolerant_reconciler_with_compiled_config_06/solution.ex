  test "compile accepts nil compare_fields" do
    assert {:ok, _} = TolerantReconciler.compile(key_fields: [:id], compare_fields: nil)
  end