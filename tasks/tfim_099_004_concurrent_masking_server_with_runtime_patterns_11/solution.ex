  test "custom patterns also apply to string values in mask/2", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\bSECRET\b/, "[X]")
    result = MaskingServer.mask(s, %{note: "the SECRET code"})
    assert result.note == "the [X] code"
  end