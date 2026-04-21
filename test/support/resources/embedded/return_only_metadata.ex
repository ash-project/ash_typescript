# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ReturnOnlyMetadata do
  @moduledoc """
  Embedded resource used ONLY as a generic action return type (via `:struct` +
  `instance_of`). Regression fixture for issue #66, which surfaced because
  embedded resources referenced solely through generic action return types
  were not discovered for TypeScript schema generation.
  """
  use Ash.Resource,
    data_layer: :embedded,
    domain: nil,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "ReturnOnlyMetadata"
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true, allow_nil?: false
    attribute :score, :integer, public?: true, default: 0
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:label, :score]
    end
  end
end
