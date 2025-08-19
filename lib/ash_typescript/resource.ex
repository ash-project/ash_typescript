defmodule AshTypescript.Resource do
  @typescript %Spark.Dsl.Section{
    name: :typescript,
    describe: "Define TypeScript settings for this resource",
    schema: [
      type_name: [
        type: :string,
        doc: "The name of the TypeScript type for the resource",
        required: true
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typescript]
end
