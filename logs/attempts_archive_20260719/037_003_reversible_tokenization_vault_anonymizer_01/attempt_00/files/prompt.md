Write me an Elixir module called `Anonymizer` that performs **reversible pseudonymization** (tokenization) of record fields, backed by a vault that can later restore the originals.

I need these functions in the public API:
- `Anonymizer.tokenize(records, fields)` where `records` is a list of maps and `fields` is a list of field-name atoms to pseudonymize. It returns `{tokenized_records, vault}`:
  - Each unique original value of a given field is replaced by a **stable opaque token string**. The token format is `"TOK_<FIELD>_<n>"` where `<FIELD>` is the uppercased field name and `<n>` is a per-field counter assigned in first-seen order (e.g. `"TOK_EMAIL_1"`).
  - Referential integrity: within a single `tokenize/2` call, the same original value for a field always produces the same token; different values produce different tokens. Distinct fields produce tokens in distinct namespaces even for equal values.
  - Fields not listed, and listed fields absent from a given record, are left untouched.
  - `vault` is an opaque term that records the mapping needed to reverse the transformation.
- `Anonymizer.detokenize(records, vault)` returns the list of records with every value that is a known token (per the vault) replaced by its original value. Values that are not known tokens are left exactly as-is.

The round trip must be lossless: `detokenize(tokenize(records, fields) |> elem(0), vault)` must equal the original `records`.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.