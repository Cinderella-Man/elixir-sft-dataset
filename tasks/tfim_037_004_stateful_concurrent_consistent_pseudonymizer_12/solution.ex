  test "records missing rule fields do not gain those keys", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{role: "admin"}])
    assert r == %{role: "admin"}
    refute Map.has_key?(r, :name)
    refute Map.has_key?(r, :email)
    refute Map.has_key?(r, :ssn)
  end