# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: modification_tag.proto

require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message "diego.bbs.models.ModificationTag" do
    optional :epoch, :string, 1
    optional :index, :uint32, 2
  end
end

module Diego
  module Bbs
    module Models
      ModificationTag = Google::Protobuf::DescriptorPool.generated_pool.lookup("diego.bbs.models.ModificationTag").msgclass
    end
  end
end
