defmodule SlackDB.Key do
  @moduledoc """
  A struct that holds all required information for a SlackDB key
  """
  alias SlackDB.Client
  alias SlackDB.Messages
  alias SlackDB.Utils

  @typedoc """
  Types of SlackDB keys represented as atoms

  Types
    * `:voting` - replies to keys are treated as a ballot where reactions represent support for that particular value. winner takes all.
    * `:multiple` - the reply thread represents an array that is returned in full and in chronological order
    * `:single_front` - the first reply to the key is the value
    * `:single_back` - the most recent reply to the key is the value
  """
  @type type :: :voting | :multiple | :single_front | :single_back

  @typedoc """
  More key metadata options represented as atoms

  Types
    * `:constant` - key cannot changed after creation (save for deletion)
    * `:undeletable` - key cannot be deleted (through this API)
  """
  @type more_metadata :: :constant | :undeletable

  @typedoc """
  Represents the types of values that keys can hold. Since all values are stored in Slack,
  they are all returned as strings (or a list of strings in the case of key_type `:multiple`)
  """
  @type value :: String.t() | list(String.t())

  @typedoc """
  A map containing the necessary attributes to identify keys uniquely
  """
  @type t :: %SlackDB.Key{
          channel_id: String.t(),
          ts: String.t(),
          key_phrase: String.t(),
          metadata: [type() | list(more_metadata())],
          server_name: String.t(),
          channel_name: String.t()
        }

  @enforce_keys [:channel_id, :ts, :metadata, :key_phrase]
  defstruct [:channel_id, :ts, :metadata, :key_phrase, :server_name, :channel_name]

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)
  defp messages(), do: Application.get_env(:slackdb, :messages_adapter, Messages)

  @doc false
  @spec get_value(SlackDB.Key.t()) :: {:error, String.t()} | {:ok, SlackDB.value()}
  def get_value(%SlackDB.Key{metadata: [:single_front | _more_metadata]} = key) do
    with {:ok, [first_reply | _other_replies]} <- messages().get_all_replies(key) do
      {:ok, first_reply["text"]}
    else
      {:ok, []} -> {:error, "no_replies"}
      err -> err
    end
  end

  def get_value(
        %SlackDB.Key{server_name: server_name, metadata: [:single_back | _more_metadata]} = key
      ) do
    with [user_token] <- Utils.get_tokens(server_name, [:user_token]),
         {:ok, %{"messages" => [_key_message | replies]}} <-
           client().conversations_replies(user_token, key, []) do
      case List.last(replies) do
        nil -> {:error, "no_replies"}
        %{"text" => text} -> {:ok, text}
        _ -> {:error, "unexpected_reply_format"}
      end
    else
      err -> err
    end
  end

  def get_value(%SlackDB.Key{metadata: [:multiple | _more_metadata]} = key) do
    with {:ok, replies} <- messages().get_all_replies(key) do
      {:ok, replies |> Enum.map(fn msg -> msg["text"] end)}
    else
      err -> err
    end
  end

  def get_value(%SlackDB.Key{metadata: [:voting | _more_metadata]} = key) do
    with {:ok, replies} <- messages().get_all_replies(key) do
      {:ok,
       replies
       |> Enum.max_by(&tally_reactions/1)
       |> Map.get("text")}
    else
      err -> err
    end
  end

  defp tally_reactions(message_details) do
    case message_details["reactions"] do
      nil ->
        0

      reactions_list when is_list(reactions_list) ->
        Enum.reduce(reactions_list, 0, fn react, acc -> react["count"] + acc end)
    end
  end
end
