# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ZodOrder.ZLeaf do
  @moduledoc "Leaf reached only through `ANestedHolder`'s union and typed map."
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderZLeaf"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule AshTypescript.Test.ZodOrder.ANestedHolder do
  @moduledoc """
  Reaches `ZLeaf` only through a union member and a typed map field. Its name
  sorts before `ZLeaf`'s, so only a dependency found through those nested
  types declares `ZLeaf` first.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderANestedHolder"
  end

  attributes do
    uuid_primary_key :id

    attribute :choice, :union,
      public?: true,
      constraints: [
        types: [
          leaf: [type: AshTypescript.Test.ZodOrder.ZLeaf],
          label: [type: :string]
        ]
      ]

    attribute :wrapper, :map,
      public?: true,
      constraints: [fields: [leaf: [type: AshTypescript.Test.ZodOrder.ZLeaf, allow_nil?: true]]]
  end
end

defmodule AshTypescript.Test.ZodOrder.ZWrapped do
  @moduledoc "The `instance_of` of `AStructHolder`'s struct attribute."
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderZWrapped"
  end

  attributes do
    uuid_primary_key :id
    attribute :leaf, AshTypescript.Test.ZodOrder.ZLeaf, public?: true
  end
end

defmodule AshTypescript.Test.ZodOrder.AStructHolder do
  @moduledoc """
  Has a `:struct` that is `instance_of` an embedded resource and also declares
  `fields`. Ash's manifest drops the fields and types it as the resource, so
  its schema references `ZWrapped`'s.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderAStructHolder"
  end

  attributes do
    uuid_primary_key :id

    attribute :wrapped, :struct,
      public?: true,
      constraints: [
        instance_of: AshTypescript.Test.ZodOrder.ZWrapped,
        fields: [leaf: [type: AshTypescript.Test.ZodOrder.ZLeaf, allow_nil?: true]]
      ]
  end
end
