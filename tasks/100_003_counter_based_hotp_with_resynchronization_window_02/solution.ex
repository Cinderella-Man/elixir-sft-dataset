  def generate_code(secret, counter) when is_integer(counter) and counter >= 0 do
    key = base32_decode(secret)
    hmac = :crypto.mac(:hmac, :sha, key, <<counter::64>>)
    offset = :binary.at(hmac, byte_size(hmac) - 1) &&& 0x0F

    truncated =
      (:binary.at(hmac, offset) &&& 0x7F) <<< 24 |||
        :binary.at(hmac, offset + 1) <<< 16 |||
        :binary.at(hmac, offset + 2) <<< 8 |||
        :binary.at(hmac, offset + 3)

    truncated
    |> rem(@modulo)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end