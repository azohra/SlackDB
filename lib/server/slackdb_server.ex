defmodule SlackDB.Server do
  @moduledoc false

  use GenServer

  alias SlackDB.Utils
  alias SlackDB.Client
  alias SlackDB.Utils
  alias SlackDB.Messages
  alias SlackDB.Channels

  @required_keys [
    :bot_token,
    :user_token,
    :bot_name,
    :supervisor_channel_name,
    :supervisor_channel_id
  ]

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)
  defp slackdb(), do: Application.get_env(:slackdb, :slackdb_adapter, SlackDB)
  defp messages(), do: Application.get_env(:slackdb, :messages_adapter, Messages)
  defp channels(), do: Application.get_env(:slackdb, :channels_adapter, Channels)

  @doc """
  Start genserver, pull server config from application environment and pass to init/1
  """
  def start_link do
    config = Application.get_env(:slackdb, :servers)

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  ####################################################################################
  ## GENSERVER CALLBACKS #############################################################
  ####################################################################################

  @impl true
  def init(config) do
    case verify_config(config) do
      {:error, msg} ->
        {:stop, msg}

      :ok ->
        server_states =
          config
          |> Map.keys()
          |> Enum.map(fn server_name ->
            {server_name,
             slackdb().read(
               server_name,
               get_in(config, [server_name, :supervisor_channel_name]),
               server_name
             )}
          end)
          |> Enum.map(&initialize_supervisor_channel/1)

        config =
          config
          |> populate_channels(server_states)

        {:ok, config}
    end
  end

  @impl true
  def handle_call(
        {:create, server_name, channel_name, key_phrase, values, all_metadata},
        _from,
        state
      ) do
    resp =
      with channel_id when is_binary(channel_id) <-
             get_in(state, [server_name, :channels, channel_name]) do
        messages().post_key_val(server_name, channel_id, key_phrase, values, all_metadata)
      else
        nil -> {:error, "channel_name_not_in_database"}
      end

    {:reply, resp, state}
  end

  def handle_call({:invite, server_name, channel_name, user_ids}, _from, state)
      when is_list(user_ids) do
    resp =
      with channel_id when is_binary(channel_id) <-
             get_in(state, [server_name, :channels, channel_name]) do
        channels().invite_to_channel(server_name, channel_id, user_ids)
      else
        nil -> {:error, "channel_name_not_in_database"}
      end

    {:reply, resp, state}
  end

  def handle_call({:put_channel, server_name, channel_name, channel_id}, _from, state) do
    new_state = state |> put_in([server_name, :channels, channel_name], channel_id)
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:archive, server_name, channel_name}, _from, state) do
    resp =
      with %{user_token: user_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            client().conversations_archive(user_token, channel_id)
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
      end

    new_state =
      case resp do
        {:ok, _} ->
          {_val, new} = state |> pop_in([server_name, :channels, channel_name])
          new

        {:error, _} ->
          state
      end

    {:reply, resp, new_state}
  end

  def handle_call({:dump}, _from, state), do: {:reply, state, state}

  ####################################################################################
  ## INIT HELPERS ####################################################################
  ####################################################################################

  defp populate_channels(map, []), do: map

  defp populate_channels(map, [{server_name, state} | more_server_states]) do
    populate_channels(map, more_server_states)
    |> put_in([server_name, :channels], state)
  end

  defp initialize_supervisor_channel({server_name, {:ok, server_state}}) do
    case server_state |> Jason.decode() do
      {:ok, map} -> {server_name, map}
      other -> {server_name, other}
    end
  end

  defp initialize_supervisor_channel({server_name, {:error, _error_message}}) do
    key_phrase = server_name
    metadata = :single_back

    init =
      with [sprvsr_chnl_id] <- Utils.get_tokens(server_name, [:supervisor_channel_id]),
           {:ok, _thread} <-
             messages().post_key_val(server_name, sprvsr_chnl_id, key_phrase, "%{}", [metadata]) do
        %{}
      else
        err -> err
      end

    {server_name, init}
  end

  defp verify_config(config) do
    Enum.filter(config, fn
      {_server_name, server_config} when is_map(server_config) ->
        @required_keys
        |> Enum.all?(&Map.has_key?(server_config, &1))
        |> Kernel.not()

      _ ->
        true
    end)
    |> case do
      [] ->
        :ok

      list ->
        list_string = list |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")

        {:error, "The following servers are improperly configured: " <> list_string}
    end
  end
end
