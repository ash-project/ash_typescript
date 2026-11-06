# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TaskNote do
  @moduledoc """
  A recursive embedded resource: its `replies` are notes. An argument of
  `AshTypescript.Test.Task`'s `:accept_notes`, so its zod and valibot schemas
  are lazy (`SchemaCore` finds it on a cycle).
  """

  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "TaskNote"
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true, allow_nil?: false

    attribute :replies, {:array, :struct},
      public?: true,
      constraints: [items: [instance_of: __MODULE__]]
  end
end

defmodule AshTypescript.Test.TaskNoteBoard do
  @moduledoc """
  Not recursive itself, but its `pinned` note is: its schema stays eager and is
  declared after `AshTypescript.Test.TaskNote`'s.
  """

  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "TaskNoteBoard"
  end

  attributes do
    uuid_primary_key :id
    attribute :pinned, AshTypescript.Test.TaskNote, public?: true, allow_nil?: false
  end
end
