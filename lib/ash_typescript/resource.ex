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
      mapped_field_names: [
        type: :keyword_list,
        doc:
          "A keyword list mapping invalid field names to valid alternatives (e.g., [address_line_1: :address_line1])",
        default: []
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typescript],
    verifiers: [
      AshTypescript.Resource.VerifyUniqueTypeNames,
      AshTypescript.Resource.VerifyMappedFieldNames
    ]
end
