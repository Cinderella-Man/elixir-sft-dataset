  @doc """
  Removes a single occurrence of `interval` from `tree`.

  Returns `{:ok, new_tree}` when the interval was present, or
  `{:error, :not_found}` otherwise. When two identical intervals are stored,
  only one of them is removed.
  """
  @spec delete(t(), interval()) :: {:ok, t()} | {:error, :not_found}
  def delete(tree, {_s, _f} = interval) do
    case do_delete(tree, interval) do
      {new_tree, true} -> {:ok, new_tree}
      {_unchanged, false} -> {:error, :not_found}
    end
  end