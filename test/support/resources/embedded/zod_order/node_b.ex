# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ZodOrder.NodeB do
  @moduledoc "Depends on NodeD. Used by NodeA (diamond left branch)."
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderNodeB"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :settings, AshTypescript.Test.ZodOrder.NodeD, public?: true, allow_nil?: true
  end
end
