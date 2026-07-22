  @spec decode_and_verify(binary(), hash()) :: {:ok, binary()} | {:error, :corrupt}
  defp decode_and_verify(compressed, hash) do
    content = :zlib.uncompress(compressed)

    if hash_hex(content) == hash do
      {:ok, content}
    else
      {:error, :corrupt}
    end
  rescue
    _error -> {:error, :corrupt}
  catch
    _kind, _reason -> {:error, :corrupt}
  end