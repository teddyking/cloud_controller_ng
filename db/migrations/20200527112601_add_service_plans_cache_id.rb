Sequel.migration do
  change do
    add_column :service_plans, :cache_id, String, size: 255, null: true
  end
end
