# Used by "mix format"
spark_locals_without_parens = [
  argument_names: 1,
  field_names: 1,
  fields: 1,
  metadata_field_names: 1,
  resource: 1,
  resource: 2,
  rpc_action: 2,
  rpc_action: 3,
  show_metadata: 1,
  ts_fields_const_name: 1,
  ts_result_type_name: 1,
  type_name: 1,
  typed_query: 2,
  typed_query: 3
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
