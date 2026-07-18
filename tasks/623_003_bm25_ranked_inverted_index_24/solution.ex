  @doc """
  Starts the inverted-index process.

  Options:

    * `:name` — optional process registration name.
    * `:stop_words` — a `MapSet` of words to exclude during tokenization;
      defaults to a built-in English stop-word set.
    * `:k1` — BM25 term-frequency saturation parameter (default `1.2`).
    * `:b` — BM25 length-normalization parameter (default `0.75`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end