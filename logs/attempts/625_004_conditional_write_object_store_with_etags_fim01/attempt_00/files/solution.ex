  @spec put_precondition_met?(%{optional(key()) => object()}, key(), keyword()) :: boolean()
  defp put_precondition_met?(objects, key, opts) do
    cond do
      Keyword.get(opts, :if_none_match) == "*" ->
        not Map.has_key?(objects, key)

      Keyword.has_key?(opts, :if_match) ->
        expected = Keyword.get(opts, :if_match)

        case Map.fetch(objects, key) do
          {:ok, %{etag: ^expected}} -> true
          _other -> false
        end

      true ->
        true
    end
  end