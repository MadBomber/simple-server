require "rails_helper"

RSpec.describe CohortAnalyticsQuery do
  let!(:facility1) { create(:facility) }
  let!(:facility2) { create(:facility) }
  let(:analytics) { CohortAnalyticsQuery.new(Patient.where(registration_facility: [facility1, facility2])) }

  let(:jan) { DateTime.new(2019, 1, 1) }
  let(:feb) { DateTime.new(2019, 2, 1) }
  let(:march) { DateTime.new(2019, 3, 1) }
  let(:april) { DateTime.new(2019, 4, 1) }
  let(:may) { DateTime.new(2019, 5, 1) }
  let(:june) { DateTime.new(2019, 6, 1) }
  let(:july) { DateTime.new(2019, 7, 1) }

  describe "#patient_counts_by_period" do
    before do
      allow(analytics).to receive(:patient_counts).and_return({})
    end

    context "monthly" do
      it "correctly calculates the dates of monthly cohort reports" do
        analytics.patient_counts_by_period(:month, 3, from_time: june)

        expect(analytics).to have_received(:patient_counts).with(feb, feb.end_of_month, march, april.end_of_month)
        expect(analytics).to have_received(:patient_counts).with(march, march.end_of_month, april, may.end_of_month)
        expect(analytics).to have_received(:patient_counts).with(april, april.end_of_month, may, june.end_of_month)
      end

      it "returns patient counts for the last 3 monthly cohorts" do
        expected_result = {
          [april, may] => {},
          [march, april] => {},
          [feb, march] => {}
        }

        travel_to(june) do
          expect(analytics.patient_counts_by_period(:month, 3, from_time: june)).to eq(expected_result)
        end
      end
    end

    context "quarterly" do
      let(:oct_prev) { DateTime.new(2018, 10, 1) }
      let(:dec_prev) { DateTime.new(2018, 12, 1) }

      it "correctly calculates the dates of quarterly cohort reports" do
        analytics.patient_counts_by_period(:quarter, 2, from_time: july)

        expect(analytics).to have_received(:patient_counts).with(april, april.end_of_quarter, july, july.end_of_quarter)
        expect(analytics).to have_received(:patient_counts).with(jan, jan.end_of_quarter, april, april.end_of_quarter)
      end

      it "returns patient counts for the last 3 quarterly cohorts" do
        expected_result = {
          [april, july] => {},
          [jan, april] => {}
        }

        travel_to(june) do
          expect(analytics.patient_counts_by_period(:quarter, 2, from_time: july)).to eq(expected_result)
        end
      end
    end
  end

  describe "#patient_counts" do
    let!(:jan_registered_patients_1) do
      travel_to(jan) do
        create_list(:patient, 10, registration_facility: facility1)
      end
    end

    let!(:jan_registered_patients_2) do
      travel_to(jan) do
        create_list(:patient, 5, registration_facility: facility2)
      end
    end

    let(:cohort_start) { DateTime.new(2019, 1, 1).beginning_of_quarter }
    let(:cohort_end) { cohort_start.end_of_quarter }
    let(:report_start) { DateTime.new(2019, 4, 1).beginning_of_quarter }
    let(:report_end) { report_start.end_of_quarter }
    let(:counts) { analytics.patient_counts(cohort_start, cohort_end, report_start, report_end).deep_symbolize_keys }

    it "calculates return and control patient counts in Q2 for patients registered in Q1" do
      travel_to(april) do
        # Facility 1: 2 patients under control, 3 not controlled
        jan_registered_patients_1[0..1].each { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility1) }
        jan_registered_patients_1[2..4].each { |patient| create(:blood_pressure, :hypertensive, patient: patient, facility: facility2) }

        # Facility 2: 3 patients under control, 1 not controlled
        jan_registered_patients_2[0..2].each { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility1) }
        jan_registered_patients_2[3..3].each { |patient| create(:blood_pressure, :hypertensive, patient: patient, facility: facility2) }
      end

      expected_result = {
        registered: {
          :total => 15,
          facility1.id => 10,
          facility2.id => 5
        },
        followed_up: {
          :total => 9,
          facility1.id => 5,
          facility2.id => 4
        },
        defaulted: {
          :total => 6,
          facility1.id => 5,
          facility2.id => 1
        },
        controlled: {
          :total => 5,
          facility1.id => 2,
          facility2.id => 3
        },
        uncontrolled: {
          :total => 4,
          facility1.id => 3,
          facility2.id => 1
        }
      }.deep_symbolize_keys

      expect(counts).to eq(expected_result)
    end

    context "when a patient makes multiple follow-up visits" do
      it "only counts the patient once in the registration facility" do
        travel_to(april) do
          jan_registered_patients_1[0].tap { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility1) }
          jan_registered_patients_1[0].tap { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility2) }
        end

        expected_follow_ups = {
          :total => 1,
          facility1.id => 1
        }.deep_symbolize_keys

        expect(counts[:followed_up].deep_symbolize_keys).to eq(expected_follow_ups)
      end

      it "marks patient uncontrolled if most recent bp is hypertensive" do
        travel_to(april) do
          jan_registered_patients_1[0].tap { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility1) }
        end
        travel_to(may) do
          jan_registered_patients_1[0].tap { |patient| create(:blood_pressure, :hypertensive, patient: patient, facility: facility2) }
        end

        expect(counts[:controlled][:total]).to eq(0)
        expect(counts[:uncontrolled][:total]).to eq(1)
      end

      it "marks patient controlled if most recent bp is under control" do
        travel_to(april) do
          jan_registered_patients_1[0].tap { |patient| create(:blood_pressure, :hypertensive, patient: patient, facility: facility1) }
        end
        travel_to(may) do
          jan_registered_patients_1[0].tap { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility2) }
        end

        expect(counts[:controlled][:total]).to eq(1)
        expect(counts[:uncontrolled][:total]).to eq(0)
      end
    end

    context "monthly" do
      let(:cohort_start) { DateTime.new(2019, 1, 1).beginning_of_month }
      let(:cohort_end) { cohort_start.end_of_month }
      let(:report_start) { DateTime.new(2019, 2, 1).beginning_of_month }
      let(:report_end) { DateTime.new(2019, 3, 1).end_of_month }

      it "calculates return and control patient counts in Feb-Mar for patients registered in Jan" do
        travel_to(march) do
          # Facility 1: 2 patients under control, 3 not controlled
          jan_registered_patients_1[0..1].each { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility1) }
          jan_registered_patients_1[2..4].each { |patient| create(:blood_pressure, :hypertensive, patient: patient, facility: facility2) }

          # Facility 2: 3 patients under control, 1 not controlled
          jan_registered_patients_2[0..2].each { |patient| create(:blood_pressure, :under_control, patient: patient, facility: facility1) }
          jan_registered_patients_2[3..3].each { |patient| create(:blood_pressure, :hypertensive, patient: patient, facility: facility2) }
        end

        expected_result = {
          registered: {
            :total => 15,
            facility1.id => 10,
            facility2.id => 5
          },
          followed_up: {
            :total => 9,
            facility1.id => 5,
            facility2.id => 4
          },
          defaulted: {
            :total => 6,
            facility1.id => 5,
            facility2.id => 1
          },
          controlled: {
            :total => 5,
            facility1.id => 2,
            facility2.id => 3
          },
          uncontrolled: {
            :total => 4,
            facility1.id => 3,
            facility2.id => 1
          }
        }.deep_symbolize_keys

        expect(counts).to eq(expected_result)
      end
    end

    context "with discarded patients" do
      before { jan_registered_patients_1[0..2].each(&:discard_data) }

      it "does not count discarded patients" do
        expect(counts[:registered][:total]).to eq(12)
      end
    end
  end
end
