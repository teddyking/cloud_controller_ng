require 'fetchers/service_binding_create_fetcher'
require 'fetchers/service_binding_list_fetcher'
require 'presenters/v3/service_binding_presenter'
require 'messages/service_binding_create_message'
require 'messages/service_bindings_list_message'
require 'actions/service_binding_create'
require 'actions/service_binding_delete'
require 'controllers/v3/mixins/app_sub_resource'
require 'cloud_controller/telemetry_logger'

class ServiceBindingsController < ApplicationController
  include AppSubResource

  def create
    message = ServiceBindingCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    app, service_instance = ServiceBindingCreateFetcher.new.fetch(message.app_guid, message.service_instance_guid)
    app_not_found! unless app
    service_instance_not_found! unless service_instance
    unauthorized! unless permission_queryer.can_write_to_space?(app.space.guid)

    accepts_incomplete = false
    begin
      service_binding = ServiceBindingCreate.new(user_audit_info).create(app, service_instance, message, volume_services_enabled?, accepts_incomplete)
      TelemetryLogger.v3_emit(
        'bind-service',
        {
          'service-id' =>  service_instance.managed_instance? ? service_instance.service_plan.service.guid : 'user-provided',
          'service-instance-id' => service_instance.guid,
          'app-id' => app.guid,
          'user-id' => current_user.guid,
        }
      )

      render status: :created, json: Presenters::V3::ServiceBindingPresenter.new(service_binding)
    rescue ServiceBindingCreate::ServiceInstanceNotBindable
      raise CloudController::Errors::ApiError.new_from_details('UnbindableService')
    rescue ServiceBindingCreate::VolumeMountServiceDisabled
      raise CloudController::Errors::ApiError.new_from_details('VolumeMountServiceDisabled')
    rescue ServiceBindingCreate::InvalidServiceBinding
      raise CloudController::Errors::ApiError.new_from_details('ServiceBindingAppServiceTaken', "#{app.guid} #{service_instance.guid}")
    end
  end

  def show
    service_binding = VCAP::CloudController::ServiceBinding.find(guid: hashed_params[:guid])

    binding_not_found! unless service_binding && permission_queryer.can_read_from_space?(service_binding.space.guid, service_binding.space.organization.guid)
    show_secrets = permission_queryer.can_read_secrets_in_space?(service_binding.space.guid, service_binding.space.organization.guid)
    render status: :ok, json: Presenters::V3::ServiceBindingPresenter.new(service_binding, show_secrets: show_secrets)
  end

  def index
    message = ServiceBindingsListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = if permission_queryer.can_read_globally?
                ServiceBindingListFetcher.new(message).fetch_all
              else
                ServiceBindingListFetcher.new(message).fetch(space_guids: permission_queryer.readable_space_guids)
              end

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceBindingPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: base_url(resource: 'service_bindings'),
      message: message,
    )
  end

  def destroy
    binding = VCAP::CloudController::ServiceBinding.where(guid: hashed_params[:guid]).eager(service_instance: { space: :organization }).first

    binding_not_found! unless binding && permission_queryer.can_read_from_space?(binding.space.guid, binding.space.organization.guid)
    unauthorized! unless permission_queryer.can_write_to_space?(binding.space.guid)

    ServiceBindingDelete.new(user_audit_info).foreground_delete_request(binding)

    head :no_content
  end

  def put
    message = ServiceBindingCreateMessage.new(hashed_params[:body]) # reuse create message but TODO create and use a update message 
    unprocessable!(message.errors.full_messages) unless message.valid?

    app, service_instance = ServiceBindingCreateFetcher.new.fetch(message.app_guid, message.service_instance_guid)
    app_not_found! unless app
    service_instance_not_found! unless service_instance
    unauthorized! unless permission_queryer.can_write_to_space?(app.space.guid)

    binding = VCAP::CloudController::ServiceBinding.find(guid: hashed_params[:guid])

    # determine if the binding is up-to-date, if not fetch from k8s
    conditional_bust(binding, hashed_params[:body][:cache_id])

    render status: :ok, json: Presenters::V3::ServiceBindingPresenter.new(binding)
  end

  private

  def conditional_bust(binding, cache_id)
    p "K8SDEBUG: binding cachebust: conditionally busting, cache_id: #{cache_id}, ccdb cache_id: #{binding.cache_id}"
    if cache_id == binding.cache_id
      p "K8SDEBUG: binding cachebust: no bust required"
      return
    end

    p "K8SDEBUG: binding cachebust: bust required"

    # fetch the binding crd from k8s
    space_guid = binding.service_instance.space.guid
    p "K8SDEBUG: binding cachebust: bust required: fetching binding #{space_guid}/#{binding.name}"
    srv_cat_client = CloudController::DependencyLocator.instance.service_catalog_client
    service_binding_crd = srv_cat_client.get_service_binding(binding.name, space_guid)

    # fetch the secret containing the credentials from k8s
    p "K8SDEBUG: binding cachebust: bust required: fetching secret #{space_guid}/#{binding.name}"
    core_v1_client = CloudController::DependencyLocator.instance.core_v1_client
    secret = core_v1_client.get_secret(binding.name, space_guid)

    # update the service_binding in ccdb
    p "K8SDEBUG: binding cachebust: bust required: updating binding in ccdb"
    binding.update({'credentials' => secret.data})
    binding.update(cache_id: service_binding_crd.metadata.resourceVersion)

    p "K8SDEBUG: binding cachebust: busted cache, cache_id: #{cache_id}, ccdb cache_id: #{binding.cache_id}"
  end

  def service_instance_not_found!
    resource_not_found!(:service_instance)
  end

  def binding_not_found!
    resource_not_found!(:service_binding)
  end

  def volume_services_enabled?
    configuration.get(:volume_services_enabled)
  end
end
