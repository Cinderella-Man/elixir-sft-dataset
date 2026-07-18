  @doc """
  Redacts `data`, returning `{scrubbed, report}`.

  Maps and keyword lists are walked recursively; plain lists are walked
  element-by-element. Sensitive keys have their values replaced with
  `"[REDACTED]"`, while every other string is pattern-scrubbed. Structs,
  numbers, atoms, and other terms are returned unchanged.
  """
  @spec redact(t(), term()) :: {term(), report()}
  def redact(%__MODULE__{} = redactor, data), do: walk(redactor, data)