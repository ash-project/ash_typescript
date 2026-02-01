# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
          "A keyword list mapping Elixir field names to TypeScript client names. " <>
            "Use strings for the client names - no additional formatting is applied. " <>
            "(e.g., [is_active?: \"isActive\", address_line_1: \"addressLine1\"])",
        default: []
      ],
      argument_names: [
        type: :keyword_list,
        doc:
          "A keyword list mapping Elixir argument names to TypeScript client names per action. " <>
            "Use strings for the client names - no additional formatting is applied. " <>
            "(e.g., [read_action: [is_active?: \"isActive\"]])",
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
