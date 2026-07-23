  test "mask/2 on a raw string agrees with mask_string/2", %{m: m} do
    input = "contact carol@domain.org about 5500 0055 5555 5559 and 987-65-4321"
    assert LogMasker.mask(m, input) == LogMasker.mask_string(m, input)
  end