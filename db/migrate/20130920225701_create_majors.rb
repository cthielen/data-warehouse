class CreateMajors < ActiveRecord::Migration
  def change
    create_table :majors do |t|
      t.string :code
      t.string :name

      t.timestamps
    end
  end
end
