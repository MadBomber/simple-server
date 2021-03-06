class UpdateLatestBloodPressuresPerPatientPerMonthsToVersion2 < ActiveRecord::Migration[5.1]
  def change
    drop_view :latest_blood_pressures_per_patient_per_quarters, materialized: true, revert_to_version: 1
    drop_view :latest_blood_pressures_per_patients, materialized: true, revert_to_version: 1
    update_view :latest_blood_pressures_per_patient_per_months,
      version: 2,
      revert_to_version: 1,
      materialized: true
    create_view :latest_blood_pressures_per_patient_per_quarters, materialized: true
    create_view :latest_blood_pressures_per_patients, materialized: true
  end
end
