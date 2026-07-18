  @doc """
  Starts the reconciler.

  Requires `:key_fields`, a non-empty list of atoms. Accepts optional `:compare_fields`
  and `:name`. Raises `ArgumentError` if `:key_fields` is missing or malformed.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    key_fields = validate_key_fields!(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields!(Keyword.get(opts, :compare_fields))

    state = %__MODULE__{key_fields: key_fields, compare_fields: compare_fields}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, state, name: name)
      :error -> GenServer.start_link(__MODULE__, state)
    end
  end