  test "structs under non-sensitive keys are returned unchanged", %{s: s} do
    uri = URI.parse("https://example.com/x?mail=john.doe@example.com")
    result = MaskingServer.mask(s, %{when: ~D[2024-01-01], link: uri, n: 7, flag: :on})
    assert result.when == ~D[2024-01-01]
    assert result.link == uri
    assert result.n == 7
    assert result.flag == :on
    assert MaskingServer.stats(s).patterns_applied == 0
  end