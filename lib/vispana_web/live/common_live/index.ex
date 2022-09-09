defmodule VispanaWeb.VispanaCommon do
  import Logger, warn: false

  use VispanaWeb, :live_view
  alias Vispana.ClusterLoader
  alias Vispana.Component.Refresher.RefreshInterval

  @impl true
  def mount(params, _session, socket) do
    log(:debug, "Started mounting...")
    config_host = params["config_host"]

    # FIXME: The port should really be looked up via the vespa model
    # # Get tenant, application and instance from
    # :19071/config/v1/cloud.config.application-id
    # And then get the model from
    # :19071/config/v2/tenant/{tenant}/application/{application}/cloud.config.model
    # The config control endpoint port is the port tagged with "state external query http"
    # in the "container-clustercontroller" service with "index" == 0
    # config_control_endpoint = String.replace(config_host, ":19071", ":19050")

    socket =
      socket
      |> assign(:refresh, %RefreshInterval{interval: -1})
      |> assign_refresh_changeset()
      |> assign(:config_host, config_host)

    # load cluster data only if socket is connected
    socket =
      if connected?(socket) do
        case vespa_cluster_load(config_host) do
          {:ok, vespa_cluster} ->
            config_control_endpoint = get_config_control_endpoint(vespa_cluster, config_host)
            socket
            |> assign(:is_loading, false)
            |> assign(:nodes, vespa_cluster)
            |> assign(:config_control_endpoint, config_control_endpoint)

          {:error, error} ->
            socket
            |> assign(:is_loading, true)
            |> put_flash(:error, error.message)
        end
      else
        # Elixir will first call this method to estabilish a connection and
        # then call mount again to update the socket if any update is available
        socket
        |> assign(:is_loading, true)
      end

    log(:debug, "Finished mounting")
    {:ok, socket}
  end

  @impl true
  def get_config_control_endpoint(vespa_cluster, config_host) do
    # Model is the ".hosts" result from
    # :19071/config/v2/tenant/default/application/default/cloud.config.model

    [port] =
      Enum.flat_map(vespa_cluster.model, fn model_host ->
        model_host
        |> Map.get("services")
        |> Enum.filter(fn service -> service["name"] === "container-clustercontroller" end)
        |> Enum.filter(fn service -> service["index"] === 0 end)
        |> Enum.flat_map(fn service ->
          service
          |> Map.get("ports")
          |> Enum.filter(fn port -> port["tags"] === "state external query http" end)
          |> Enum.map(fn port -> port["number"] end)
        end)
      end)

    String.replace(config_host, ":19071", ":" <> Integer.to_string(port))
  end

  @impl true
  def handle_params(_params, _url, socket) do
    # Sets page title
    socket =
      case socket.assigns.live_action do
        :config -> socket |> assign(:page_title, "Vispana - Config Overview")
        :container -> socket |> assign(:page_title, "Vispana - Container Overview")
        :content -> socket |> assign(:page_title, "Vispana - Content Overview")
        :apppackage -> socket |> assign(:page_title, "Vispana - App package Overview")
        :ctrlstatus -> socket |> assign(:page_title, "Vispana - Cluster Details")
        :_ -> socket |> assign(:page_title, "Vispana")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _value, socket) do
    log(:debug, "Refresh request")
    config_host = socket.assigns()[:config_host]

    socket =
      case vespa_cluster_load(config_host) do
        {:ok, vespa_cluster} ->
          socket
          |> assign(:is_loading, false)
          |> assign(:nodes, vespa_cluster)

        {:error, error} ->
          socket
          |> put_flash(:error, "Failed to refresh: " <> error.message)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "refresh_interval",
        %{"refresh_interval" => refresh_params},
        %{assigns: %{refresh: refresh}} = socket
      ) do
    interval = String.to_integer(refresh_params["interval"])
    log(:debug, "Refresh interval: #{interval}")

    changeset =
      refresh
      |> RefreshInterval.change_refresh_rate(refresh_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      # Assign result to changeset for the screen & fire background process
      |> assign(:changeset, changeset)
      |> assign(:interval, interval)

    if connected?(socket) and interval > 0 do
      Process.send_after(self(), :refresh, interval)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    log(:debug, "Started handle_info...")

    config_host = socket.assigns()[:config_host]
    refresh_interval = Map.get(socket.assigns(), :interval, -1)

    # if refresh interval is smaller than 0, auto refresh is off
    if refresh_interval < 1 do
      {:noreply, socket}
    else
      socket =
        case vespa_cluster_load(config_host) do
          {:ok, vespa_cluster} ->
            socket
            |> assign(:is_loading, false)
            |> assign(:nodes, vespa_cluster)

          {:error, error} ->
            socket
            |> assign(:is_loading, true)
            |> put_flash(:error, "Failed to refresh: " <> error.message)
        end

      if connected?(socket) do
        # very unlikely that this will be needed one day, but throttling
        # based on last time fetched might help with back pressure
        Process.send_after(self(), :refresh, refresh_interval)
      end

      log(:debug, "Finished handle_info")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp vespa_cluster_load(config_host) do
    try do
      {:ok, ClusterLoader.load(config_host)}
    rescue
      e in RuntimeError ->
        IO.inspect(e)
        {:error, e}
    end
  end

  defp assign_refresh_changeset(%{assigns: %{refresh: refresh}} = socket) do
    socket
    |> assign(:changeset, RefreshInterval.change_refresh_rate(refresh))
  end

  @impl true
  def render(assigns) do
    ~L"""
    """
  end
end
