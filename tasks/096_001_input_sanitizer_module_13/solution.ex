  @doc """
  Ensures `input` is safe for interpolation as a SQL identifier
  (table or column name).

  ## Rules

    * Keeps only alphanumeric characters and underscores.
    * Returns `{:error, :empty}` when the result is the empty string.
    * Prepends `"_"` when the first character is a digit (most SQL dialects
      forbid identifiers that start with a digit).
    * Returns `{:ok, sanitized}` on success.

  ## Examples

      iex> Sanitizer.sql_identifier("users")
      {:ok, "users"}

      iex> Sanitizer.sql_identifier("my-table!")
      {:ok, "mytable"}

      iex> Sanitizer.sql_identifier("123col")
      {:ok, "_123col"}

      iex> Sanitizer.sql_identifier("!@#")
      {:error, :empty}

  """
  @spec sql_identifier(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def sql_identifier(input) when is_binary(input) do
    sanitized = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    cond do
      sanitized == "" ->
        {:error, :empty}

      String.match?(sanitized, ~r/\A[0-9]/) ->
        {:ok, "_" <> sanitized}

      true ->
        {:ok, sanitized}
    end
  end