require 'jobs/v3/services/update_broker_job'

module VCAP::CloudController
  module V3
    class ServiceBrokerUpdate
      class InvalidServiceBroker < StandardError
      end

      attr_reader :broker, :service_event_repository, :broker_cache_id

      def initialize(service_broker, service_event_repository)
        @broker = service_broker
        @broker_cache_id = service_broker.cache_id
        @service_event_repository = service_event_repository
      end

      def update(message)
        params = {}
        params[:name] = message.name if message.requested?(:name)
        params[:broker_url] = message.url if message.requested?(:url)
        params[:authentication] = message.authentication.to_json if message.requested?(:authentication)
        params[:service_broker_id] = broker.id
        cache_id = message.cache_id if message.requested?(:cache_id)

        if params[:name] && !ServiceBroker.where(name: params[:name]).exclude(guid: broker.guid).empty?
          raise InvalidServiceBroker.new('Name must be unique')
        end

        p "K8SDEBUG: update service broker with params: #{params}"
        p "K8SDEBUG: ccdb service broker name: #{broker.name}"

        # if broker.in_transitional_state?
        #  raise InvalidServiceBroker.new('Cannot update a broker when other operation is already in progress')
        # end

        pollable_job = nil
        previous_broker_state = broker.state
        ServiceBrokerUpdateRequest.db.transaction do
          broker.update(state: ServiceBrokerStateEnum::SYNCHRONIZING)

          update_request = ServiceBrokerUpdateRequest.create(params)
          MetadataUpdate.update(update_request, message, destroy_nil: false)

          service_event_repository.record_broker_event_with_request(:update, broker, message.audit_hash)

          # determine if the broker (and subsequently services/plans) is up-to-date, if not fetch all from k8s
          conditional_bust(broker, cache_id)

          synchronization_job = UpdateBrokerJob.new(update_request.guid, broker.guid, previous_broker_state)
          # UpdateBrokerJob has been updated to do nothing except put the state back to AVAILABLE
          pollable_job = Jobs::Enqueuer.new(synchronization_job, queue: Jobs::Queues.generic).enqueue_pollable
        end

        { pollable_job: pollable_job }
      end

      private

      def conditional_bust(broker, cache_id)
        p "K8SDEBUG: cachebust: conditionally busting, cache_id: #{cache_id}, ccdb cache_id: #{broker.cache_id}"

        if cache_id == broker.cache_id
          p "K8SDEBUG: cachebust: no bust required"
          return
        end

        p "K8SDEBUG: cachebust: bust required"

        # fetch the broker crd from k8s
        srv_cat_client = CloudController::DependencyLocator.instance.service_catalog_client

        broker_crd = nil
        if broker.space_guid != nil
          # space-scoped broker
          p "K8SDEBUG: cachebust: bust required: fetching namespace-scoped broker with name #{broker.name} and ns #{broker.space_guid}"
          broker_crd = srv_cat_client.get_broker(broker.name, broker.space_guid)
        else
          # global broker
          p "K8SDEBUG: cachebust: bust required: fetching cluster broker with name #{broker.name}"
          broker_crd = srv_cat_client.get_cluster_broker(broker.name)
        end

        p "K8SDEBUG: cachebust: bust required: broker_crd: #{broker_crd}"

        # update the service_broker in ccdb
        p "K8SDEBUG: cachebust: bust required: updating service_broker in ccdb"

        broker.update(cache_id: broker_crd.metadata.resourceVersion)

        p "K8SDEBUG: cachebust: busted cache, cache_id: #{cache_id}, ccdb cache_id: #{broker.cache_id}"
      end
    end
  end
end
