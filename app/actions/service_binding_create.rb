require 'actions/services/database_error_service_resource_cleanup'
require 'actions/services/locks/lock_check'
require 'repositories/service_binding_event_repository'
require 'jobs/v2/services/service_binding_state_fetch'

module VCAP::CloudController
  class ServiceBindingCreate
    class InvalidServiceBinding < StandardError; end
    class ServiceInstanceNotBindable < InvalidServiceBinding; end
    class ServiceBrokerInvalidSyslogDrainUrl < InvalidServiceBinding; end
    class ServiceBrokerInvalidBindingsRetrievable < InvalidServiceBinding; end
    class ServiceBrokerRespondedAsyncWhenNotAllowed < InvalidServiceBinding; end
    class VolumeMountServiceDisabled < InvalidServiceBinding; end
    class SpaceMismatch < InvalidServiceBinding; end

    PERMITTED_BINDING_ATTRIBUTES = [:credentials, :syslog_drain_url, :volume_mounts].freeze

    include VCAP::CloudController::LockCheck

    def initialize(user_audit_info, manifest_triggered: false)
      @user_audit_info = user_audit_info
      @manifest_triggered = manifest_triggered
    end

    def create(app, service_instance, message, volume_mount_services_enabled, accepts_incomplete)
      raise ServiceInstanceNotBindable unless service_instance.bindable?
      raise VolumeMountServiceDisabled if service_instance.volume_service? && !volume_mount_services_enabled
      raise SpaceMismatch unless bindable_in_space?(service_instance, app.space)

      raise_if_instance_locked(service_instance)

      binding = ServiceBinding.new(
        service_instance: service_instance,
        app:              app,
        credentials:      {},
        type:             message.type,
        name:             message.name,
      )
      raise InvalidServiceBinding.new(binding.errors.full_messages.join(' ')) unless binding.valid?

      create_crd(binding)
      binding.save

      return # return early

      client = VCAP::Services::ServiceClientProvider.provide(instance: service_instance)

      binding_result = request_binding_from_broker(client, binding, message.parameters, accepts_incomplete)

      binding.set_fields(binding_result[:binding], PERMITTED_BINDING_ATTRIBUTES)

      begin
        if binding_result[:async]
          raise ServiceBrokerInvalidBindingsRetrievable.new unless binding.service.bindings_retrievable
          raise ServiceBrokerRespondedAsyncWhenNotAllowed.new unless accepts_incomplete

          binding.save_with_new_operation({ type: 'create', state: 'in progress', broker_provided_operation: binding_result[:operation] })
          job = Jobs::Services::ServiceBindingStateFetch.new(binding.guid, @user_audit_info, message.audit_hash)
          enqueuer = Jobs::Enqueuer.new(job, queue: Jobs::Queues.generic)
          enqueuer.enqueue
          Repositories::ServiceBindingEventRepository.record_start_create(binding, @user_audit_info, message.audit_hash, manifest_triggered: @manifest_triggered)
        else
          binding.save
          Repositories::ServiceBindingEventRepository.record_create(binding, @user_audit_info, message.audit_hash, manifest_triggered: @manifest_triggered)
        end
      rescue => e
        logger.error "Failed to save state of create for service binding #{binding.guid} with exception: #{e}"
        cleanup_binding_without_db(binding)
        raise e
      end

      binding
    end

    private

    def create_crd(service_binding)
      srv_cat_client = CloudController::DependencyLocator.instance.service_catalog_client

      b = Kubeclient::Resource.new

      b.metadata = {}
      b.spec = {}

      b.metadata.name = service_binding.name
      b.metadata.namespace = service_binding.service_instance.space.guid

      b.spec.instanceRef = {}
      b.spec.instanceRef.name = service_binding.service_instance.name

      begin
        p "K8SDEBUG: creating service binding with name #{b.metadata.namespace}/#{b.metadata.name}, instanceRef #{b.spec.instanceRef.name}"
        srv_cat_client.create_service_binding(b)
      rescue => e
        p "K8SDEBUG: create binding crd error: ", e
      end
    end

    def request_binding_from_broker(client, service_binding, parameters, accepts_incomplete)
      client.bind(service_binding, arbitrary_parameters: parameters, accepts_incomplete: accepts_incomplete)
    end

    def cleanup_binding_without_db(binding)
      service_resource_cleanup = DatabaseErrorServiceResourceCleanup.new(logger)
      service_resource_cleanup.attempt_unbind(binding)
    end

    def bindable_in_space?(service_instance, app_space)
      service_instance.space == app_space || service_instance.shared_spaces.include?(app_space)
    end

    def logger
      @logger ||= Steno.logger('cc.action.service_binding_create')
    end
  end
end
