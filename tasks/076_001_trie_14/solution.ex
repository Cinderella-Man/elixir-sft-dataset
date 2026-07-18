  @doc """
  Returns `true` if `word` was explicitly inserted, `false` otherwise.

  A prefix that was never inserted on its own will return `false`.
  """
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{root: root}, word) when is_binary(word) do
    word_exists?(root, String.graphemes(word))
  end