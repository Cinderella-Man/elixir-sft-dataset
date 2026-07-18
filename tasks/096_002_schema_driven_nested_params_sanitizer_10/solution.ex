  @doc """
  Sanitize `params` against `schema`.

  Returns `{:ok, cleaned}` when every field is valid, otherwise
  `{:error, errors}` where `errors` maps a path (list of string keys and
  integer list indices) to a reason atom.
  """
  @spec sanitize(map(), map()) :: {:ok, map()} | {:error, map()}
  def sanitize(params, schema) when is_map(params) and is_map(schema) do
    {clean, errors} = walk_map(params, schema, [])

    if errors == %{} do
      {:ok, clean}
    else
      {:error, errors}
    end
  end