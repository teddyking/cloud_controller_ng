require 'kubernetes/kube_client_builder'

module Kubernetes
  class CoreV1Client
    def initialize(kube_client)
      @client = kube_client
    end

    # def create_image(*args)
    #   @client.create_image(*args)
    # rescue Kubeclient::HttpError => e
    #   raise CloudController::Errors::ApiError.new_from_details('KpackImageError', 'create', e.message)
    # end

    def create_secret(*args)
      @client.create_secret(*args)
    rescue Kubeclient::ResourceNotFoundError
      nil
    # rescue Kubeclient::HttpError => e
    #   raise CloudController::Errors::ApiError.new_from_details('KpackImageError', 'get', e.message)
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
