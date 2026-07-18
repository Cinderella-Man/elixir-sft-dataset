  @doc """
  A combinator that wraps any generator and produces non-empty lists of 1–20
  elements drawn from it.

  ## Example

      Generators.non_empty_list(StreamData.integer())
      # => [3, -1, 42, 7]  (between 1 and 20 elements)

      Generators.non_empty_list(Generators.user())
      # => [%{id: 1, name: "Alice", ...}, ...]
  """
  @spec non_empty_list(StreamData.t(a)) :: StreamData.t(nonempty_list(a)) when a: term()
  def non_empty_list(generator) do
    SD.bind(SD.integer(1..20), fn size ->
      SD.list_of(generator, length: size)
    end)
  end