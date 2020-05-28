require 'messages/metadata_base_message'

module VCAP::CloudController
  class ServiceInstanceUpdateManagedMessage < MetadataBaseMessage
    register_allowed_keys [:cache_id]

    validates_with NoAdditionalKeysValidator
  end
end
