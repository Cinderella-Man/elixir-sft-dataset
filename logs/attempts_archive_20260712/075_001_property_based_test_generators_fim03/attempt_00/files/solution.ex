  # Produces a non-empty, letters-only string of at most 50 characters.
  # Draws a length first, then fills exactly that many codepoints from the
  # union of a–z and A–Z, so empty strings and digits are structurally
  # impossible — no filter step required.
  defp user_name do
    letter = SD.member_of(Enum.concat(?a..?z, ?A..?Z))

    SD.bind(SD.integer(1..50), fn length ->
      SD.bind(SD.list_of(letter, length: length), fn codepoints ->
        SD.constant(List.to_string(codepoints))
      end)
    end)
  end