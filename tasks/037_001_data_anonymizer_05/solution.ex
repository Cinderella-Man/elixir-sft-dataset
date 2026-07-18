  @doc """
  Anonymizes `records` in accordance with `rules`.

  ## Parameters

    * `records` – a list of maps (each map represents one record).
    * `rules`   – a map whose keys are field-name atoms and whose values are
                  rule atoms or tuples (see module doc for supported rules).

  ## Returns

  A list of maps of the same length and structure as `records`. Fields named
  in `rules` are transformed; all other fields are left untouched. If a record
  does not contain a field named in `rules`, that entry is silently skipped.

  ## Examples

      iex> records = [
      ...>   %{name: "Alice", email: "alice@example.com", age: 30},
      ...>   %{name: "Bob",   email: "bob@example.com",   age: 25},
      ...>   %{name: "Alice", email: "alice@example.com", age: 42},
      ...> ]
      iex> rules = %{name: :mask, email: :redact}
      iex> Anonymizer.anonymize(records, rules)
      [
        %{name: "A***e", email: "[REDACTED]", age: 30},
        %{name: "B*b",   email: "[REDACTED]", age: 25},
        %{name: "A***e", email: "[REDACTED]", age: 42}
      ]

  Note that both records with `name: "Alice"` produce the same masked output,
  demonstrating referential integrity.
  """
  @spec anonymize([map()], %{atom() => rule()}) :: [map()]
  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    Enum.map(records, &anonymize_record(&1, rules))
  end