Sequel.migration do
  change do
    add_column :service_bindings, :cache_id, String, size: 255, null: true
  end
end
