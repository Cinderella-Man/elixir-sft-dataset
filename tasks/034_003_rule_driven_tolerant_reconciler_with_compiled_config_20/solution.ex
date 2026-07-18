  @doc """
  Validates reconciliation options and returns an opaque configuration.

  ## Options

    * `:key_fields` (required) — a non-empty list of atoms forming the composite key.
    * `:compare_fields` (optional) — a list of atoms to compare on matched pairs. When
      omitted or `nil`, every field present in either record of a pair is compared,
      minus the key fields.
    * `:rules` (optional) — a keyword list of `field => rule`. Compared fields without
      an entry use the `:exact` rule. Defaults to `[]`.

  Returns `{:ok, config}` or one of `{:error, :missing_key_fields}`,
  `{:error, :invalid_key_fields}`, `{:error, :invalid_compare_fields}`,
  `{:error, :invalid_rules}` or `{:error, {:invalid_rule, field}}`.

  ## Examples

      iex> {:ok, config} = TolerantReconciler.compile(key_fields: [:id])
      iex> match?(%TolerantReconciler{}, config)
      true

      iex> TolerantReconciler.compile([])
      {:error, :missing_key_fields}
  """
  @spec compile(keyword()) ::
          {:ok, config()}
          | {:error,
             :missing_key_fields
             | :invalid_key_fields
             | :invalid_compare_fields
             | :invalid_rules
             | {:invalid_rule, field()}}
  def compile(opts) when is_list(opts) do
    with {:ok, key_fields} <- validate_key_fields(opts),
         {:ok, compare_fields} <- validate_compare_fields(opts),
         {:ok, rules} <- validate_rules(opts) do
      {:ok,
       %__MODULE__{
         key_fields: key_fields,
         compare_fields: compare_fields,
         rules: rules
       }}
    end
  end

  def compile(_opts), do: {:error, :missing_key_fields}