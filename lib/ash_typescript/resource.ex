# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource do
  @moduledoc """
  Spark DSL extension for configuring TypeScript generation on Ash resources.

  This extension allows resources to define TypeScript-specific settings,
  such as custom type names for the generated TypeScript interfaces.
  """
  @typescript %Spark.Dsl.Section{
    name: :typescript,
    describe: "Define TypeScript settings for this resource",
    schema: [
      type_name: [
        type: :string,
        doc: "The name of the TypeScript type for the resource",
        required: true
      ],
      field_names: [
        type: :keyword_list,
        doc:
          "A keyword list mapping invalid field names to valid alternatives (e.g., [address_line_1: :address_line1])",
        default: []
      ],
      argument_names: [
        type: :keyword_list,
        doc:
          "A keyword list mapping invalid argument names to valid alternatives per action (e.g., [read_with_invalid_arg: [is_active?: :is_active]])",
        default: []
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typescript],
    verifiers: [
      AshTypescript.Resource.Verifiers.VerifyUniqueTypeNames,
      AshTypescript.Resource.Verifiers.VerifyFieldNames,
      AshTypescript.Resource.Verifiers.VerifyMappedFieldNames,
      AshTypescript.Resource.Verifiers.VerifyMapFieldNames
    ]
end
