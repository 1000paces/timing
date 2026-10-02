class CreatePairingTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :pairing_tokens, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.bigint :expires_at_ms, null: false
      t.bigint :used_at_ms
      t.string :created_by_official_id, null: false
      t.timestamps
    end
    add_index :pairing_tokens, :token_digest, unique: true
  end
end
