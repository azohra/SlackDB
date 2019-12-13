defmodule SlackDB.Messages do
  @moduledoc false

  alias SlackDB.Client
  alias SlackDB.Utils

  @callback get_all_replies(SlackDB.Key.t(), keyword()) ::
              {:ok, list(map())} | {:error, String.t()}
  @callback wipe_thread(SlackDB.Key.t(), keyword()) ::
              {:ok, list(tuple())} | {:error, binary}
  @callback post_thread(SlackDB.Key.t(), SlackDB.Key.value()) ::
              {:ok, list(tuple())} | {:error, String.t()}
  @callback post_thread(String.t(), String.t(), String.t(), SlackDB.Key.value()) ::
              {:ok, list(tuple())}

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)

  @spec post_thread(SlackDB.Key.t(), SlackDB.Key.value()) ::
          {:ok, list(tuple())} | {:error, String.t()}
  def post_thread(key, values) do
    with [bot_token] <- Utils.get_tokens(key.server_name, [:bot_token]) do
      post_thread(bot_token, key.channel_id, key.ts, values)
    else
      err -> err
    end
  end

  @spec post_thread(String.t(), String.t(), String.t(), SlackDB.Key.value()) ::
          {:ok, list(tuple())}
  def post_thread(bot_token, channel_id, thread_ts, values) when is_binary(values),
    do: post_thread(bot_token, channel_id, thread_ts, [values])

  def post_thread(bot_token, channel_id, thread_ts, values) when is_list(values) do
    {:ok, post_thread_recurse(bot_token, channel_id, thread_ts, values)}
  end

  defp post_thread_recurse(_bot_token, _channel_id, _thread_ts, []), do: []

  defp post_thread_recurse(bot_token, channel_id, thread_ts, [hd_msg | tail]) do
    [
      client().chat_postMessage(bot_token, hd_msg, channel_id, thread_ts: thread_ts)
      | post_thread_recurse(bot_token, channel_id, thread_ts, tail)
    ]
  end

  @doc """
  Note: just because you get a function-wide :ok doesn't mean every request was successful

  ## Options
  * `:include_key?` - boolean, default is true
  * `:token_type` - `:bot_token` or `user_token`, default is `user_token`
  """
  @spec wipe_thread(SlackDB.Key.t(), keyword()) ::
          {:ok, list(tuple())} | {:error, binary}
  def wipe_thread(key, opts \\ []) do
    token_type = Keyword.get(opts, :token_type, :user_token)

    with [token] <- Utils.get_tokens(key.server_name, [token_type]),
         {:ok, replies} <-
           get_all_replies(key, token_type: token_type) do
      result =
        case Keyword.get(opts, :include_key?, true) do
          false -> replies
          true -> [%{"ts" => key.ts} | replies]
        end
        |> Flow.from_enumerable()
        |> Flow.map(fn %{"ts" => ts} -> client().chat_delete(token, key.channel_id, ts) end)
        |> Enum.to_list()

      {:ok, result}

      # |> Enum.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
    else
      err -> err
    end
  end

  @doc """
  ## Options
  * `:token_type` - `:bot_token` or `user_token`, default is `user_token`
  """
  @spec get_all_replies(SlackDB.Key.t(), keyword()) ::
          {:ok, list(map())} | {:error, String.t()}
  def get_all_replies(key, opts \\ []) do
    token_type = Keyword.get(opts, :token_type, :user_token)

    with [token] <- Utils.get_tokens(key.server_name, [token_type]) do
      paginate_replies(token, nil, key, [])
    else
      e -> e
    end
  end

  # paginate through conversations.list responeses and collect public+private channels in a list
  # each element of the list is a map containing data about the channel shown at this doc https://api.slack.com/methods/conversations.replies
  defp paginate_replies(token, cursor, key, list) do
    with {:ok, resp} <- client().conversations_replies(token, key, cursor: cursor) do
      case get_in(resp, ["response_metadata", "next_cursor"]) do
        # notice how it's added in chunks in reverse order
        nil -> {:ok, tl(resp["messages"]) ++ list}
        cursor -> paginate_replies(token, cursor, key, list ++ tl(resp["messages"]))
      end
    end
  end
end
