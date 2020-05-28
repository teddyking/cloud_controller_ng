Sequel.migration do
  change do
    add_column :service_instances, :cache_id, String, size: 255, null: true
  end
end
