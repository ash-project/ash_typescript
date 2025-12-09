# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.LocationTuple do
  @moduledoc """
  NewType tuple with typescript_field_names callback for testing input parsing.

  Tests tuple type with problematic field names:
  - lat_1 → "lat1"
  - is_verified? → "isVerified"
  """
  use Ash.Type.NewType,
    subtype_of: :tuple,
    constraints: [
      fields: [
        lat_1: [type: :float, allow_nil?: false],
        lng_1: [type: :float, allow_nil?: false],
        is_verified?: [type: :boolean, allow_nil?: true]
      ]
    ]

  def typescript_field_names do
    [
      lat_1: "lat1",
      lng_1: "lng1",
      is_verified?: "isVerified"
    ]
  end
end
