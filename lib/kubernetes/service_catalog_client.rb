require 'kubernetes/kube_client_builder'

module Kubernetes
  class ServiceCatalogClient
    def initialize(kube_client)
      @client = kube_client
    end

    def create_broker(*args)
      @client.create_cluster_service_broker(*args)
    end

    def get_brokers
      @client.get_cluster_service_brokers
    end

    def get_plans
      @client.get_cluster_service_plans
    end

    # def update_image(*args)
    #   @client.update_image(*args)
    # rescue Kubeclient::HttpError => e
    #   raise CloudController::Errors::ApiError.new_from_details('KpackImageError', 'update', e.message)
    # end

    # def delete_image(name, namespace)
    #   @client.delete_image(name, namespace)
    # rescue Kubeclient::ResourceNotFoundError
    #   nil
    # rescue Kubeclient::HttpError => e
    #   raise CloudController::Errors::ApiError.new_from_details('KpackImageError', 'delete', e.message)
    # end
  end
end
