# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ZodOrder.NodeE do
  @moduledoc "Leaf node for Zod declaration order testing."
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderNodeE"
  end

  attributes do
    uuid_primary_key :id
    attribute :value, :string, public?: true, allow_nil?: false
  end
end
