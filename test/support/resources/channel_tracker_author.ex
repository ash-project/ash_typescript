# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelTrackerAuthor do
  @moduledoc """
  Author resource for nested relationship traversal testing in :auto calculations.
  """
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key :id
    attribute :username, :string, public?: true
    attribute :email, :string, public?: true
  end

  actions do
    defaults [:read, :create]
  end
end
