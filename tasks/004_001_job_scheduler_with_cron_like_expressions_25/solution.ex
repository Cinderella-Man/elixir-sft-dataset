  defp split_opts(opts) do
    {name_opts, rest} = Keyword.split(opts, [:name])
    gen_opts = if name_opts[:name], do: [name: name_opts[:name]], else: []
    {gen_opts, rest}
  end