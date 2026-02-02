# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.NestedProfile do
  @moduledoc """
  Embedded resource containing another embedded resource for deep nesting tests.

  Tests 3-level nesting: Resource → NestedProfile → Profile (embedded)
  With field_names at each level.
  """
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "InputParsingNestedProfile"
    field_names level_1?: "level1", has_details?: "hasDetails"
  end

  attributes do
    attribute :section_name, :string do
      allow_nil? false
      public? true
    end

    attribute :level_1?, :boolean do
      default false
      public? true
    end

    attribute :has_details?, :boolean do
      default true
      public? true
    end

    # Embedded resource within embedded resource - creates 3-level nesting
    attribute :detail_profile, AshTypescript.Test.InputParsing.Profile do
      allow_nil? true
      public? true
    end

    # NewType with field_names within embedded resource
    attribute :detail_stats, AshTypescript.Test.InputParsing.Stats do
      allow_nil? true
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
