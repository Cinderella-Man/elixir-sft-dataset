  @doc """
  Masks sensitive data in `data`, returning the same shape.

  Maps and keyword lists are walked recursively; a value under a sensitive key
  becomes `"[MASKED]"`, while other values are walked further. Plain lists are
  walked element-by-element. String values under non-sensitive keys are scrubbed
  with the same patterns as `mask_string/2`. Structs, numbers, atoms, and other
  terms are returned unchanged.
  """
  @spec mask(server(), term()) :: term()
  def mask(server, data) do
    GenServer.call(server, {:mask, data})
  end