  @spec deserialize(binary()) :: term()
  defp deserialize(payload_bytes) do
    :erlang.binary_to_term(payload_bytes, [:safe])
  end