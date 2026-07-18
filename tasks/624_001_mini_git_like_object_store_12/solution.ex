  defp do_store(state, content) do
    hash = sha1(content)
    {hash, Map.put_new(state, hash, content)}
  end