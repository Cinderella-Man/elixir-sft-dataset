  @doc """
  Puts `flag_name` into multivariate mode.

  `variants` is a list of `{variant_atom, weight_integer}` tuples whose weights
  must sum to exactly 100. Raises `ArgumentError` otherwise.
  """
  @spec set_variants(atom(), [{atom(), non_neg_integer()}]) :: :ok
  def set_variants(flag_name, variants) when is_list(variants) do
    validated = validate_variants(variants)
    GenServer.call(server(), {:set, flag_name, {:variants, validated}})
  end