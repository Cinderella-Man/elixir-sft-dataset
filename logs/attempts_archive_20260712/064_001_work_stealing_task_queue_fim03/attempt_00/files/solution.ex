  # Divide `items` into `n` chunks as evenly as possible.
  # The first `rem(length, n)` chunks get one extra item.
  # Always returns exactly `n` lists (some may be `[]` when n > length(items)).
  @spec partition(list(), pos_integer()) :: [list()]
  defp partition(items, n) do
    total = length(items)
    base_size = div(total, n)
    # How many workers get one extra item
    extras = rem(total, n)

    {chunks, _remaining} =
      Enum.reduce(0..(n - 1), {[], items}, fn i, {acc, rest} ->
        chunk_size = if i < extras, do: base_size + 1, else: base_size
        {chunk, tail} = Enum.split(rest, chunk_size)
        {[chunk | acc], tail}
      end)

    Enum.reverse(chunks)
  end