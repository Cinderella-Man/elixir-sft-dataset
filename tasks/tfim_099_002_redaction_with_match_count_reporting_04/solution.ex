  test "leaves non-sensitive keys untouched", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{user_id: 42, role: "admin"})
    assert scrubbed.user_id == 42
    assert scrubbed.role == "admin"
    assert report.keys_masked == 0
  end