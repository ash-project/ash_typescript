# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ZodOrder.ZRefLeaf do
  @moduledoc "Leaf reached only through the named types of the `TypeRef` holders."
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderZRefLeaf"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule AshTypescript.Test.ZodOrder.AliasedLeafBox do
  @moduledoc "An aliased field-bearing NewType holding `ZRefLeaf`: it has its own named schema."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [fields: [leaf: [type: AshTypescript.Test.ZodOrder.ZRefLeaf, allow_nil?: true]]]

  def typescript_type_alias, do: "ZodOrderAliasedLeafBox"
end

defmodule AshTypescript.Test.ZodOrder.InlineLeafBox do
  @moduledoc "A field-bearing NewType holding `ZRefLeaf`, without an alias: its schema is inline."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [fields: [leaf: [type: AshTypescript.Test.ZodOrder.ZRefLeaf, allow_nil?: true]]]
end

defmodule AshTypescript.Test.ZodOrder.EntryLeafBox do
  @moduledoc """
  A map custom type holding `ZRefLeaf` through `typescript_fields/0`. Tests
  give it a `custom_types` `map` entry with `zod` / `valibot`, which replace
  its schema.
  """
  use AshTypescript.Test.PassThroughType

  def typescript_fields,
    do: [leaf: [type: AshTypescript.Test.ZodOrder.ZRefLeaf, allow_nil?: true]]
end

defmodule AshTypescript.Test.ZodOrder.ANamedRefHolder do
  @moduledoc """
  Reaches `ZRefLeaf` only through named types with their own schema, which
  reference it lazily. Its name sorts before `ZRefLeaf`'s, so it is declared
  first unless a dependency is (wrongly) found through them.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderANamedRefHolder"
  end

  attributes do
    uuid_primary_key :id
    attribute :aliased_box, AshTypescript.Test.ZodOrder.AliasedLeafBox, public?: true
    attribute :entry_box, AshTypescript.Test.ZodOrder.EntryLeafBox, public?: true
  end
end

defmodule AshTypescript.Test.ZodOrder.AInlineRefHolder do
  @moduledoc """
  Reaches `ZRefLeaf` through a named type rendered inline, so `ZRefLeaf` is
  declared first although its name sorts later.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderAInlineRefHolder"
  end

  attributes do
    uuid_primary_key :id
    attribute :inline_box, AshTypescript.Test.ZodOrder.InlineLeafBox, public?: true
  end
end
