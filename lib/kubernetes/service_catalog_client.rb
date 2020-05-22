require 'kubernetes/kube_client_builder'

module Kubernetes
  class ServiceCatalogClient
    def initialize(kube_client)
      @client = kube_client
    end

    def create_broker(*args)
      @client.create_service_broker(*args)
    end

    def create_cluster_broker(*args)
      @client.create_cluster_service_broker(*args)
    end

    def get_brokers(namespaces)
      brokers = []

      namespaces.each do |n|
        brokers = brokers + @client.get_service_brokers(namespace: "cf-ns-" + n)
      end

      brokers
    end

    def get_all_brokers(*args)
      @client.get_cluster_service_brokers + @client.get_service_brokers
    end

    def get_plans
      @client.get_cluster_service_plans
    end

    def get_all_service_classes
      @client.get_cluster_service_classes + @client.get_service_classes
    end
  end
end
