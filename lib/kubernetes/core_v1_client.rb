require 'kubernetes/kube_client_builder'

module Kubernetes
  class CoreV1Client
    def initialize(kube_client)
      @client = kube_client
    end

    def create_secret(*args)
      @client.create_secret(*args)
    rescue Kubeclient::ResourceNotFoundError
      nil
    end

    def get_secret(name, namespace)
      @client.get_secrets.find do |s|
        s.metadata.name == name &&
        s.metadata.namespace == namespace
      end
    end
  end
end
