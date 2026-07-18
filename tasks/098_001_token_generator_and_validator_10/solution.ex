  # [:safe] prevents decoding of terms that could allocate new atoms or
  # function references — standard hygiene for untrusted binaries even
  # after MAC verification.
  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end