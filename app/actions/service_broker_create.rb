require 'jobs/v3/services/synchronize_broker_catalog_job'
require 'base64'

module VCAP::CloudController
  module V3
    class ServiceBrokerCreate
      class InvalidServiceBroker < StandardError
      end

      class SpaceNotFound < StandardError
      end

      def initialize(service_event_repository)
        @service_event_repository = service_event_repository
      end

      def create(message)
        params = {
          name: message.name,
          broker_url: message.url,
          auth_username: message.username,
          auth_password: message.password,
          space_guid: message.relationships_message.space_guid,
          state: ServiceBrokerStateEnum::SYNCHRONIZING
        }

        core_v1_client = CloudController::DependencyLocator.instance.core_v1_client

        s = Kubeclient::Resource.new
        s.metadata = {}
        s.metadata.name = message.name
        s.metadata.namespace = "service-catalog"
        s.data = {}
        s.data.username = Base64.encode64(message.username)
        s.data.password = Base64.encode64(message.password)

        begin
          core_v1_client.create_secret(s)
        rescue => e
          p "create secret error: ", e
        end

        # pollable_job = nil
        # ServiceBroker.db.transaction do
        #   broker = ServiceBroker.create(params)
        #   MetadataUpdate.update(broker, message)

        # service_event_repository.record_broker_event_with_request(:create, broker, message.audit_hash)

        synchronization_job = SynchronizeBrokerCatalogJob.new(
          name: message.name,
          url: message.url,
        )
        pollable_job = Jobs::Enqueuer.new(synchronization_job, queue: Jobs::Queues.generic).enqueue_pollable
        # end

        { pollable_job: pollable_job }
      rescue Sequel::ValidationFailed => e
        raise InvalidServiceBroker.new(e.errors.full_messages.join(','))
      end

      private

      attr_reader :service_event_repository

      def route_services_enabled?
        VCAP::CloudController::Config.config.get(:route_services_enabled)
      end

      def volume_services_enabled?
        VCAP::CloudController::Config.config.get(:volume_services_enabled)
      end
    end
  end
end
