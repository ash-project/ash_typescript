# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# Used by "mix format"
spark_locals_without_parens = [
  allowed_loads: 1,
  argument_names: 1,
  denied_loads: 1,
  deprecated: 1,
  description: 1,
  enable_filter?: 1,
  enable_sort?: 1,
  error_handler: 1,
  field_names: 1,
  fields: 1,
  get?: 1,
  get_by: 1,
  identities: 1,
  metadata_field_names: 1,
  namespace: 1,
  not_found_error?: 1,
  read_action: 1,
  resource: 1,
  resource: 2,
  rpc_action: 2,
  rpc_action: 3,
  see: 1,
  show_metadata: 1,
  show_raised_errors?: 1,
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
