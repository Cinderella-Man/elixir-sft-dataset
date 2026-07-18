  test "masker with empty sensitive_keys list masks nothing structurally", %{m: _} do
    empty_masker = LogMasker.new([])
    data = %{password: "visible", token: "also_visible"}
    result = LogMasker.mask(empty_masker, data)
    # Structural keys not masked, but string patterns still apply
    # password value is not a pattern-matched string so it passes through
    assert result.password == "visible"
    assert result.token == "also_visible"
  end