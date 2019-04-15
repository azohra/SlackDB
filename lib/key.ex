defmodule SlackDB.Key do
  @moduledoc """
  A struct that holds all required information for a SlackDB key
  """
  @typedoc """
  A map containing the necessary attributes to identify keys uniquely
  """
  @type t :: %SlackDB.Key{
          channel_id: String.t(),
          ts: String.t(),
          key_phrase: String.t(),
          metadata: [SlackDB.key_type() | list(SlackDB.more_metadata())],
          server_name: String.t(),
          channel_name: String.t()
        }

  @enforce_keys [:channel_id, :ts, :metadata, :key_phrase]
  defstruct [:channel_id, :ts, :metadata, :key_phrase, :server_name, :channel_name]
end
