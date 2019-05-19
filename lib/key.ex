defmodule SlackDB.Key do
  @moduledoc """
  A struct that holds all required information for a SlackDB key
  """
  use Private
  alias SlackDB.Client
  alias SlackDB.Utils

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

  @doc false
  @spec get_value(SlackDB.Key.t()) :: {:error, String.t()} | {:ok, SlackDB.value()}
  def get_value(
        %SlackDB.Key{server_name: server_name, metadata: [:single_front | _more_metadata]} = key
      ) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, resp} <- Client.conversations_replies(user_token, key) do
      case Utils.get_all_replies(user_token, key, [], resp) do
        li when is_list(li) and length(li) > 0 -> {:ok, List.first(li)["text"]}
        li when is_list(li) and length(li) == 0 -> {:error, "no_replies"}
        _ -> {:error, "error_pulling_thread"}
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  def get_value(
        %SlackDB.Key{server_name: server_name, metadata: [:single_back | _more_metadata]} = key
      ) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, %{"messages" => [_key_message | replies]}} <-
           Client.conversations_replies(user_token, key, nil, 1) do
      case replies do
        [] -> {:error, "no_replies"}
        [%{"text" => text}] -> {:ok, text}
        _ -> {:error, "unexpected_reply_format"}
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  def get_value(
        %SlackDB.Key{server_name: server_name, metadata: [:multiple | _more_metadata]} = key
      ) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, resp} <- Client.conversations_replies(user_token, key) do
      {:ok,
       Utils.get_all_replies(user_token, key, [], resp)
       |> Enum.map(fn msg -> msg["text"] end)}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  def get_value(
        %SlackDB.Key{
          server_name: server_name,
          # channel_id: channel_id,
          metadata: [:voting | _more_metadata]
        } = key
      ) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, resp} <- Client.conversations_replies(user_token, key) do
      {:ok,
       Utils.get_all_replies(user_token, key, [], resp)
       |> Enum.max_by(&tally_reactions/1)
       |> Map.get("text")}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  private do
    defp tally_reactions(message_details) do
      case message_details["reactions"] do
        nil ->
          0

        reactions_list when is_list(reactions_list) ->
          Enum.reduce(reactions_list, 0, fn react, acc -> react["count"] + acc end)
      end
    end
  end
end
