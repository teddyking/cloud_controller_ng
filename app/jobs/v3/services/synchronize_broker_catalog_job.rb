require 'jobs/v3/services/service_broker_catalog_updater'

module VCAP::CloudController
  module V3
    class SynchronizeBrokerCatalogJob < VCAP::CloudController::Jobs::CCJob
      attr_reader :warnings

      def initialize(name:, url:)
        @broker_name = name
        @broker_url = url
      end

      def perform
        # @warnings = Perform.new(@broker_guid).perform

        client = CloudController::DependencyLocator.instance.service_catalog_client

        b = Kubeclient::Resource.new
        b.metadata = {}
        b.metadata.name = @broker_name
        b.spec = {}
        b.spec.authInfo = {}
        b.spec.authInfo.basic = {}
        b.spec.authInfo.basic.secretRef = {}

        b.spec.url = @broker_url
        b.spec.authInfo.basic.secretRef.name = @broker_name
        b.spec.authInfo.basic.secretRef.namespace = "service-catalog"

        client.create_broker(b)
      end

      def job_name_in_configuration
        :synchronize_service_broker_catalog
      end

      def max_attempts
        1
      end

      def resource_type
        'service_brokers'
      end

      def resource_guid
        # broker_guid
        'fake-resource-guid'
      end

      def display_name
        'service_broker.catalog.synchronize'
      end

      private

      # attr_reader :broker_guid

      # class Perform
      #   def initialize(broker_guid)
      #     @broker = ServiceBroker.find(guid: broker_guid)
      #     @catalog_updater = VCAP::CloudController::V3::ServiceBrokerCatalogUpdater.new(@broker)
      #   end

      #   def perform
      #     broker.update(state: ServiceBrokerStateEnum::SYNCHRONIZING)

      #     warnings = @catalog_updater.refresh

      #     broker.update(state: ServiceBrokerStateEnum::AVAILABLE)

      #     warnings
      #   rescue => e
      #     begin
      #       broker.update(state: ServiceBrokerStateEnum::SYNCHRONIZATION_FAILED)
      #     rescue
      #       raise CloudController::Errors::V3::ApiError.new_from_details('ServiceBrokerGone') if broker.nil?
      #     end

      #     raise e
      #   end

      #   private

      #   attr_reader :broker, :warnings
      # end
    end
  end
end
