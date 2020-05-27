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
      @client.get_service_brokers.find do |b|
        b.metadata.name == name &&
        b.metadata.namespace == namespace
      end
    end

    def create_cluster_broker(*args)
      @client.create_cluster_service_broker(*args)
    end

    def get_cluster_broker(name)
      @client.get_cluster_service_brokers.find do |b|
        b.metadata.name == name
      end
    end

    def get_service_class(name, namespace)
      @client.get_service_classes.find do |s|
        s.metadata.name == name &&
        s.metadata.namespace == namespace
      end
    end

    def get_cluster_service_class(name)
      @client.get_cluster_service_classes.find do |s|
        s.metadata.name == name
      end
    end

    def get_service_plan(name, namespace)
      @client.get_service_plans.find do |p|
        p.metadata.name == name &&
        p.metadata.namespace == namespace
      end
    end

    def get_cluster_service_plan(name)
      @client.get_cluster_service_plans.find do |p|
        p.metadata.name == name
      end
    end

    def get_broker(name)
      broker = nil

      broker = @client.get_cluster_service_brokers.find do |b|
        b.metadata.name == brokerName
      end

      if broker.nil?
        broker = @client.get_service_brokers.find do |b|
          b.metadata.name == brokerName
        end
      end

      broker
    end
  end
end
