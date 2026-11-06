# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TaskOutline do
  @moduledoc """
  Mutually recursive embedded resources: an outline's `items` are
  `AshTypescript.Test.TaskOutlineItem`s, and an item's `sublist` is an outline.
  An argument of `AshTypescript.Test.Task`'s `:accept_notes`.
  """

  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "TaskOutline"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false

    attribute :items, {:array, :struct},
      public?: true,
      allow_nil?: false,
      constraints: [items: [instance_of: AshTypescript.Test.TaskOutlineItem]]
  end
end

defmodule AshTypescript.Test.TaskOutlineItem do
  @moduledoc "An item of an `AshTypescript.Test.TaskOutline`; its `sublist` is an outline."

  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "TaskOutlineItem"
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true, allow_nil?: false

    attribute :sublist, :struct,
      public?: true,
      constraints: [instance_of: AshTypescript.Test.TaskOutline]
  end
end
