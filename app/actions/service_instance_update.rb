module VCAP::CloudController
  class ServiceInstanceUpdate
    class InvalidServiceInstance < StandardError
    end

    class << self
      def update(service_instance, message)
        logger = Steno.logger('cc.action.service_instance_update')
        cache_id = message.cache_id

        p "K8SDEBUG: update service instance guid: #{service_instance.guid}"
        p "K8SDEBUG: update service instance message cache_id: #{cache_id}"

        service_instance.db.transaction do
          MetadataUpdate.update(service_instance, message)

          # determine if the instance is up-to-date, if not fetch from k8s
          conditional_bust(service_instance, cache_id)
        end
        logger.info("Finished updating metadata on service_instance #{service_instance.guid}")
        service_instance
      rescue Sequel::ValidationFailed => e
        raise InvalidServiceInstance.new(e.message)
      end

      private

      def conditional_bust(service_instance, cache_id)
        p "K8SDEBUG: instance cachebust: conditionally busting, cache_id: #{cache_id}, ccdb cache_id: #{service_instance.cache_id}"
        if cache_id == service_instance.cache_id
          p "K8SDEBUG: instance cachebust: no bust required"
          return
        end

        p "K8SDEBUG: instance cachebust: bust required"

        # fetch the instance crd from k8s
        p "K8SDEBUG: instance cachebust: bust required: fetching service_instance #{service_instance.space.guid}/#{service_instance.name}"
        srv_cat_client = CloudController::DependencyLocator.instance.service_catalog_client
        service_instance_crd = srv_cat_client.get_service_instance(service_instance.name, service_instance.space.guid)

        # update the service_broker in ccdb
        p "K8SDEBUG: instance cachebust: bust required: updating service_instance in ccdb"

        service_instance.update(cache_id: service_instance_crd.metadata.resourceVersion)

        p "K8SDEBUG: instance cachebust: busted cache, cache_id: #{cache_id}, ccdb cache_id: #{service_instance.cache_id}"
      end
    end
  end
end
