  def tokenize(records, fields) when is_list(records) and is_list(fields) do
    # A duplicate field atom must behave like a single mention: a second pass
    # over an already-tokenized field would tokenize the token itself, and the
    # round trip through detokenize/2 would no longer be lossless.
    fields = Enum.uniq(fields)

    {reversed, vault} =
      Enum.reduce(records, {[], new_vault()}, fn record, {acc, vault} ->
        {record2, vault2} =
          Enum.reduce(fields, {record, vault}, fn field, {rec, v} ->
            case Map.fetch(rec, field) do
              {:ok, value} ->
                {token, v2} = get_or_create_token(v, field, value)
                {Map.put(rec, field, token), v2}

              :error ->
                {rec, v}
            end
          end)

        {[record2 | acc], vault2}
      end)

    {Enum.reverse(reversed), vault}
  end