def scalar do
  SD.one_of([
    SD.constant(nil),
    SD.boolean(),
    SD.integer(),
    SD.string(:alphanumeric, max_length: 8)
  ])
end