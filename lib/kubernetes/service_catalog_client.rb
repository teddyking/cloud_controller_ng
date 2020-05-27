require 'kubernetes/kube_client_builder'

module Kubernetes
  class ServiceCatalogClient
    def initialize(kube_client)
      @client = kube_client
    end

    def create_broker(*args)
      @client.create_service_broker(*args)
    end

    def get_broker(name, namespace)
      @client.get_service_brokers(name: name, namespace: namespace).first
    end

    def create_cluster_broker(*args)
      @client.create_cluster_service_broker(*args)
    end

    def get_cluster_broker(name)
      @client.get_cluster_service_brokers(name: name).first
    end

    def get_brokers(namespaces)
      brokers = []

      namespaces.each do |n|
        brokers = brokers + @client.get_service_brokers(namespace: n)
      end

      brokers
    end

    def get_cluster_service_class(name)
      get_services.find do |s|
        s.metadata.name == name
      end
    end

    def get_cluster_service_plan(name)
      get_plans.find do |p|
        p.metadata.name == name
      end
    end

    def get_all_brokers(*args)
      @client.get_cluster_service_brokers + @client.get_service_brokers
    end

    def get_plans
      @client.get_cluster_service_plans
    end

    def get_services
      @client.get_cluster_service_classes
    end
  end
end
