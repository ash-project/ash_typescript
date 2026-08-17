# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.NestedArrayConstraints do
  @moduledoc false

  use Ash.Resource, domain: nil

  actions do
    action :validate, :boolean do
      argument :bounded_matrix, {:array, {:array, :integer}} do
        allow_nil? false
        constraints min_length: 1, max_length: 2, items: [min_length: 2, max_length: 3]
      end

      run fn _input, _context -> {:ok, true} end
    end
  end
end
