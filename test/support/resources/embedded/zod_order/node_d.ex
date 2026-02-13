# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ZodOrder.NodeD do
  @moduledoc "Depends on NodeE (direct + array). Used by NodeB and NodeC (diamond)."
  use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "ZodOrderNodeD"
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true, allow_nil?: false
    attribute :detail, AshTypescript.Test.ZodOrder.NodeE, public?: true, allow_nil?: true
    attribute :items, {:array, AshTypescript.Test.ZodOrder.NodeE}, public?: true, default: []
  end
end
