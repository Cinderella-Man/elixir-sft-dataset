  defp parse_html(input, allow) do
    {result, _} = do_parse(input, allow, [], :text, "", _poisoned_a = false)
    IO.iodata_to_binary(result)
  end