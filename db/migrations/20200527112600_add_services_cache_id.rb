Sequel.migration do
  change do
    add_column :services, :cache_id, String, size: 255, null: true
  end
end
