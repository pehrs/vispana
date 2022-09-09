defmodule Vispana.Cluster.VespaCluster do
  defstruct [:configCluster, :containerClusters, :contentClusters, :appPackage, :model]

  alias Vispana.Cluster.AppPackage
  alias Vispana.Cluster.VespaCluster
  alias Vispana.Cluster.ConfigCluster

  def empty_cluster do
    %VespaCluster{
      configCluster: %ConfigCluster{},
      containerClusters: [],
      contentClusters: [],
      appPackage: %AppPackage{},
      model: []
    }
  end

  @impl true
  @spec get_content_node_endpoint(Vispana.Cluster.VespaCluster, string) :: string
  def get_content_node_endpoint(vespa_cluster, content_hostname) do
    [port] =
      Enum.filter(vespa_cluster.model, fn model_host ->
        model_host["name"] === content_hostname
      end)
      |> Enum.flat_map(fn model_host ->
        model_host
        |> Map.get("services")
        |> Enum.filter(fn service -> service["name"] === "storagenode" end)
        |> Enum.flat_map(fn service ->
          service
          |> Map.get("ports")
          |> Enum.filter(fn port -> port["tags"] === "state status http" end)
          |> Enum.map(fn port -> port["number"] end)
        end)
      end)

    "http://" <> content_hostname <> ":" <> Integer.to_string(port)
  end
end
