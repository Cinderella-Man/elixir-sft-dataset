  # Produces a non-empty lowercase alphanumeric string of 1–20 characters.
  defp alnum_segment do
    lowercase_alnum = SD.member_of(Enum.concat(?a..?z, ?0..?9))

    SD.bind(SD.integer(1..20), fn length ->
      SD.bind(SD.list_of(lowercase_alnum, length: length), fn codepoints ->
        SD.constant(List.to_string(codepoints))
      end)
    end)
  end