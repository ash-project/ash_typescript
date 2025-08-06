# Used by "mix format"
spark_locals_without_parens = [
  fields: 1,
  resource: 1,
  resource: 2,
  rpc_action: 2,
  rpc_action: 3,
  ts_fields_const_name: 1,
  ts_result_type_name: 1,
  typed_query: 1,
  typed_query: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:ash],
  plugins: [Spark.Formatter],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
