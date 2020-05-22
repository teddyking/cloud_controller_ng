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

    client = CloudController::DependencyLocator.instance.service_catalog_client

    service_offerings = if !current_user
                          ServiceOfferingListFetcher.new.fetch_public(message)
                        elsif permission_queryer.can_read_globally?
                          # ServiceOfferingListFetcher.new.fetch(message)
                          client.get_all_service_classes
                        else
                          ServiceOfferingListFetcher.new.fetch_visible(
                            message,
                            permission_queryer.readable_org_guids,
                            permission_queryer.readable_space_scoped_space_guids,
                          )
                        end

    dataset =  service_offerings.map do |s|
      labels = {}
      annotations = {}
      space_guid = nil
      shareable = false

      if s.spec.externalMetadata
        if s.spec.externalMetadata.shareable
          shareable = true
        end
      end

      OpenStruct.new(
        guid: s.metadata.uid,
        label: s.spec.externalName,
        description: s.spec.description,
        active: true, # TODO
        tags: s.spec.tags,
        requires: {}, # TODO
        created_at: s.metadata.creationTimestamp,
        updated_at: s.metadata.creationTimestamp,
        extra: "{\"shareable\": #{shareable}, \"documentation_url\": \"https://github.com\"}",
        unique_id: s.metadata.name, #TODO
        plan_updateable: s.spec.planUpdatable,
        bindable: s.spec.bindable,
        instances_retrievable: true, #TODO
        bindings_retrievable: s.spec.bindingRetrievable,
        allow_context_updates: true, #TODO
        service_broker: OpenStruct.new(guid: ""),
        labels: {},
        annotations: {},
      )

    end

    decorators = []
    #decorators << FieldServiceOfferingServiceBrokerDecorator.new(message.fields) if FieldServiceOfferingServiceBrokerDecorator.match?(message.fields)

    presenter = Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceOfferingPresenter,
      paginated_result: ListPaginator.new.get_page(dataset, message.try(:pagination_options)),
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
