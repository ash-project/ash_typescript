# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.EmptyResource do
  @moduledoc """
  Test resource with minimal configuration.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "EmptyResource"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id, public?: false
  end

  actions do
    defaults [:read]
  end
end
