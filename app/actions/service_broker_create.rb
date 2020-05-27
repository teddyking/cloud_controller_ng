require 'jobs/v3/services/synchronize_broker_catalog_job'

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

        # create crd
        create_crd(params)

        pollable_job = nil
        ServiceBroker.db.transaction do
          broker = ServiceBroker.create(params)
          MetadataUpdate.update(broker, message)

          service_event_repository.record_broker_event_with_request(:create, broker, message.audit_hash)

          synchronization_job = SynchronizeBrokerCatalogJob.new(broker.guid)
          # The SynchronizeBrokerCatalogJob has been updated to _not_ fetch the catalog
          pollable_job = Jobs::Enqueuer.new(synchronization_job, queue: Jobs::Queues.generic).enqueue_pollable
        end

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

      def create_crd(params)
        core_v1_client = CloudController::DependencyLocator.instance.core_v1_client
        srv_cat_client = CloudController::DependencyLocator.instance.service_catalog_client

        s = Kubeclient::Resource.new
        b = Kubeclient::Resource.new

        # create the secret
        s.metadata = {}
        s.data = {}

        s.metadata.name = params[:name]
        s.metadata.namespace = "service-catalog"

        s.data.username = Base64.encode64(params[:auth_username])
        s.data.password = Base64.encode64(params[:auth_password])

        if params[:space_guid]
          s.metadata.namespace = params[:space_guid]
        end

        begin
          p "creating k8s secret with name #{params[:name]}"
          core_v1_client.create_secret(s)
        rescue => e
          p "create secret error: ", e
        end

        # create the broker
        b.metadata = {}
        b.metadata.annotations = {}
        b.spec = {}
        b.spec.authInfo = {}
        b.spec.authInfo.basic = {}
        b.spec.authInfo.basic.secretRef = {}

        b.metadata.name = params[:name]

        b.spec.url = params[:broker_url]
        b.spec.authInfo.basic.secretRef.name = params[:name]

        begin
          if params[:space_guid]
            # space-scoped broker
            b.metadata.namespace = params[:space_guid]
            b.metadata.annotations['cloudfoundry.org/space_guid'] = params[:space_guid]

            p "creating service cat broker with name #{params[:name]}"
            srv_cat_client.create_broker(b)
          else
            # global broker
            b.spec.authInfo.basic.secretRef.namespace = "service-catalog"

            p "creating service cat cluster broker with name #{params[:name]}"
            srv_cat_client.create_cluster_broker(b)
          end
        rescue => e
          p "create broker crd error: ", e
        end
      end
    end
  end
end
