  test "compile succeeds with only key_fields" do
    assert {:ok, _config} = TolerantReconciler.compile(key_fields: [:id])
  end