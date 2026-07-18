  @doc """
  Produces a valid program of `0..max_length` stack commands.

  Commands: `{:push, integer}`, `:pop`, `:peek`, `:clear`. `:pop`/`:peek` are
  only offered when the modeled stack is non-empty, so running the program can
  never underflow.
  """
  @spec stack_program(non_neg_integer()) :: StreamData.t([term()])
  def stack_program(max_length \\ 20) when is_integer(max_length) and max_length >= 0 do
    SD.bind(SD.integer(0..max_length), fn n ->
      stack_build(n, 0, [])
    end)
  end