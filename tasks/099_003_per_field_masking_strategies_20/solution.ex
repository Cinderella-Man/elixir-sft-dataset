  @doc """
  Masks `data`, returning the same shape with sensitive data scrubbed.

  Maps and keyword lists are walked recursively; a value whose key matches a
  policy is replaced using that key's strategy, while other values continue to
  be walked. Plain lists are walked element-by-element. String values under
  non-policy keys are pattern-scrubbed via `mask_string/2`. Structs, numbers,
  atoms, and other terms without a matching policy key are returned unchanged.
  """
  @spec mask(t(), term()) :: term()
  def mask(%__MODULE__{} = masker, data), do: do_mask(masker, data)