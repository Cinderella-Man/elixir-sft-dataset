  test "masks multiple emails in one string", %{m: m} do
    result = LogMasker.mask_string(m, "a@b.com and carol@domain.org")
    assert result =~ "a***@b.com"
    assert result =~ "c***@domain.org"
  end