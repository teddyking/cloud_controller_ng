require 'fetchers/service_offering_fetcher'
require 'fetchers/service_offering_list_fetcher'
require 'fetchers/service_plan_visibility_fetcher'
require 'presenters/v3/service_offering_presenter'
require 'messages/service_offerings_list_message'
require 'messages/service_offerings_show_message'
require 'messages/metadata_update_message'
require 'messages/purge_message'
require 'actions/service_offering_delete'
require 'actions/transactional_metadata_update'
require 'controllers/v3/mixins/service_permissions'
require 'decorators/field_service_offering_service_broker_decorator'

class ServiceOfferingsController < ApplicationController
  include ServicePermissions

  def index
    not_authenticated! if user_cannot_see_marketplace?

    message = ServiceOfferingsListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = if !current_user
                ServiceOfferingListFetcher.new.fetch_public(message)
              elsif permission_queryer.can_read_globally?
                ServiceOfferingListFetcher.new.fetch(message)
              else
                ServiceOfferingListFetcher.new.fetch_visible(
                  message,
                  permission_queryer.readable_org_guids,
                  permission_queryer.readable_space_scoped_space_guids,
                )
              end

    decorators = []
    decorators << FieldServiceOfferingServiceBrokerDecorator.new(message.fields) if FieldServiceOfferingServiceBrokerDecorator.match?(message.fields)

    presenter = Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceOfferingPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      message: message,
      path: '/v3/service_offerings',
      decorators: decorators
    )

    render status: :ok, json: presenter.to_json
  end

  def show
    not_authenticated! if user_cannot_see_marketplace?

    service_offering = ServiceOfferingFetcher.fetch(hashed_params[:guid])
    service_offering_not_found! if service_offering.nil?
    service_offering_not_found! unless visible_to_current_user?(service: service_offering)

    message = ServiceOfferingsShowMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    decorators = []
    decorators << FieldServiceOfferingServiceBrokerDecorator.new(message.fields) if FieldServiceOfferingServiceBrokerDecorator.match?(message.fields)

    presenter = Presenters::V3::ServiceOfferingPresenter.new(service_offering, decorators: decorators)
    render status: :ok, json: presenter.to_json
  end

  def update
    service_offering = ServiceOfferingFetcher.fetch(hashed_params[:guid])
    service_offering_not_found! if service_offering.nil?

    cannot_write!(service_offering) unless current_user_can_write?(service_offering)

    message = MetadataUpdateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    updated_service_offering = TransactionalMetadataUpdate.update(service_offering, message)
    presenter = Presenters::V3::ServiceOfferingPresenter.new(updated_service_offering)

    render :ok, json: presenter.to_json
  end

  def put
    p "K8SDEBUG: PUTing service_offering with guid: #{hashed_params[:guid]}"
    p "K8SDEBUG: hashed_params = #{hashed_params}"

    broker_guid = hashed_params[:body][:broker_guid]
    space_guid = hashed_params[:body][:space_guid]

    service_broker = ServiceBroker.find(guid: broker_guid)
    service_offering = Service.find(guid: hashed_params[:guid], service_broker_id: service_broker.id)

    # create it in ccdb if it doesn't exist
    if service_offering == nil
      p "K8SDEBUG: service_offering nil in CCDB"

      srv_cat_client = CloudController::DependencyLocator.instance.service_catalog_client

      service_crd = nil
      if space_guid != nil
        p "K8SDEBUG: fetching namespace-scoped service class"
        service_crd = srv_cat_client.get_service_class(hashed_params[:guid], space_guid)
      else
        p "K8SDEBUG: fetching global-scoped service class"
        service_crd = srv_cat_client.get_cluster_service_class(hashed_params[:guid])
      end

      p "K8SDEBUG: fetched service crd: #{service_crd.metadata.name}"

      service_offering = Service.new
      service_offering.guid = hashed_params[:guid]
      service_offering.label = service_crd.spec.externalName
      service_offering.description = service_crd.spec.description
      service_offering.bindable = service_crd.spec.bindable
      service_offering.service_broker = service_broker
      service_offering.cache_id = service_crd.metadata.resourceVersion
    end

    p "K8SDEBUG: saving service_offering to ccdb: #{service_offering}"
    service_offering.save

    # TODO: update it in ccdb if it does exist

    presenter = Presenters::V3::ServiceOfferingPresenter.new(service_offering)
    render :ok, json: presenter.to_json
  end

  def destroy
    message = PurgeMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    service_offering = ServiceOfferingFetcher.fetch(hashed_params[:guid])
    service_offering_not_found! if service_offering.nil?

    cannot_write!(service_offering) unless current_user_can_write?(service_offering)

    service_event_repository = VCAP::CloudController::Repositories::ServiceEventRepository.new(user_audit_info)

    if message.purge?
      service_offering.purge(service_event_repository)
      service_event_repository.record_service_purge_event(service_offering)
    else
      ServiceOfferingDelete.new.delete(service_offering)
      service_event_repository.record_service_delete_event(service_offering)
    end

    head :no_content
  rescue ServiceOfferingDelete::AssociationNotEmptyError => e
    unprocessable!(e.message)
  end

  private

  def enforce_authentication?
    %w(show index).include?(action_name) ? false : super
  end

  def enforce_read_scope?
    %w(show index).include?(action_name) ? false : super
  end

  def service_offering_not_found!
    resource_not_found!(:service_offering)
  end

  def cannot_write!(service_offering)
    unauthorized! if visible_to_current_user?(service: service_offering)
    service_offering_not_found!
  end
end
