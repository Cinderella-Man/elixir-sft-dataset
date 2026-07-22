  @spec hotp(secret(), non_neg_integer()) :: String.t()
  defp hotp(secret, step) do
    key = base32_decode(secret)
    hash = :crypto.mac(:hmac, :sha, key, <<step::64>>)
    offset = rem(:binary.at(hash, byte_size(hash) - 1), @offset_modulo)

    truncated =
      :binary.at(hash, offset) * 16_777_216 +
        :binary.at(hash, offset + 1) * 65_536 +
        :binary.at(hash, offset + 2) * 256 +
        :binary.at(hash, offset + 3)

    truncated
    |> rem(@truncate_modulo)
    |> rem(@modulo)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end