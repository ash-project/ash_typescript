# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TaskNode do
  @moduledoc """
  A recursive resource (its `parent` is a node), used only as action metadata
  by `AshTypescript.Test.Task`'s `:read_with_rich_metadata`.

  Not embedded; recursive embedded resources are `AshTypescript.Test.TaskNote`
  and `AshTypescript.Test.TaskOutline`.
  """

  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "TaskNode"
  end

  attributes do
    uuid_primary_key :id, public?: true
    attribute :label, :string, public?: true
    attribute :parent, :struct, public?: true, constraints: [instance_of: __MODULE__]
  end
end
