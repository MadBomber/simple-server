require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'Associations' do
    it { should have_many(:user_authentications) }
  end

  describe 'Validations' do
    it { should validate_presence_of(:full_name) }
    it_behaves_like 'a record that validates device timestamps'
  end

  describe '.build_with_phone_number_authentication' do
    context 'all required params are present and are valid' do
      let(:registration_facility) { create(:facility) }
      let(:id) { SecureRandom.uuid }
      let(:full_name) { Faker::Name.name }
      let(:phone_number) { Faker::PhoneNumber.phone_number }
      let(:password_digest) { BCrypt::Password.create('1234') }
      let(:params) do
        { id: id,
          full_name: full_name,
          phone_number: phone_number,
          password_digest: password_digest,
          registration_facility_id: registration_facility.id,
          organization_id: registration_facility.organization.id,
          device_created_at: Time.current.iso8601,
          device_updated_at: Time.current.iso8601 }
      end

      let(:user) { User.build_with_phone_number_authentication(params) }
      let(:phone_number_authentication) { user.phone_number_authentication }

      it 'builds a valid user' do
        expect(user).to be_valid
        expect(user.id).to eq(id)
        expect(user.full_name).to eq(full_name)
        expect(user.user_authentications).to be_present
        expect(user.user_authentications.size).to eq(1)
      end

      it 'builds a valid phone number authentication a user' do
        expect(phone_number_authentication).to be_instance_of(PhoneNumberAuthentication)
        expect(phone_number_authentication).to be_valid
        expect(phone_number_authentication.password_digest).to eq(password_digest)
        expect(phone_number_authentication.registration_facility_id).to eq(registration_facility.id)
      end

      it 'assigns an otp and access token to the phone number authentication' do
        expect(phone_number_authentication.otp).to be_present
        expect(phone_number_authentication.otp_expires_at).to be_present
        expect(phone_number_authentication.access_token).to be_present
      end

      it 'creates the user with required associations when save is called on it' do
        expect { user.save }.to change(User, :count).by(1)

        expect(user.user_authentications).to be_present
        expect(user.phone_number_authentication).to be_present
        expect(user.phone_number_authentication)
          .to eq(PhoneNumberAuthentication.find_by(phone_number: phone_number))
      end
    end
  end

  describe "Search" do
    shared_examples "full_name search" do |search_method|
      context 'searches whole words against full names' do
        let!(:user_1) { create(:user, full_name: "Sri Priyanka John") }
        let!(:user_2) { create(:user, full_name: "Priya Sri Gupta") }

        ["Sri", "sri", "SRi", "sRi", "SRI", "sRI"].each do |term|
          it "returns results for case-insensitive searches: #{term.inspect}" do
            expect(User.public_send(search_method, term)).to match_array([user_1, user_2])
          end
        end

        ["Priyanka", "John", "Priyanka John"].each do |term|
          it "matches on first name, last name or full names: #{term.inspect}" do
            expect(User.public_send(search_method, term)).to match_array(user_1)
          end
        end

        ["pri", "sr"].each do |term|
          it "partially matches on first name, last name or full names: #{term.inspect}" do
            expect(User.public_send(search_method, term)).to match_array([user_1, user_2])
          end
        end

        ["\n\n", ""].each do |term|
          it "returns nothing for unmatched searches: #{term.inspect}" do
            expect(User.public_send(search_method, term)).to be_empty
          end
        end

        ["gupta\n\n\r", "\b      gupta         "].each do |term|
          it "ignores escape characters and whitespace around words: #{term.inspect}" do
            expect(User.public_send(search_method, term)).to match_array(user_2)
          end
        end
      end
    end

    describe ".search_by_name_or_phone" do
      include_examples "full_name search", :search_by_name_or_phone

      context "searches against phone_number" do
        let!(:user_1) { create(:user, full_name: "Sri Priyanka John") }
        let!(:user_2) { create(:user, full_name: "Priya Sri Gupta") }

        it "matches a user with a phone number" do
          expect(User.search_by_name_or_phone(user_1.phone_number)).to match_array(user_1)
        end

        it "returns nothing for combinations that don't match" do
          expect(User.search_by_name_or_phone(user_1.phone_number + user_2.phone_number))
            .to be_empty

          expect(User.search_by_name_or_phone(""))
            .to be_empty
        end

        it "matches a combination of name and phone number from the same user" do
          expect(User.search_by_name_or_phone(user_1.phone_number + " " + "John"))
            .to match_array(user_1)

          expect(User.search_by_name_or_phone("Gupta" + " " + user_2.phone_number))
            .to match_array(user_2)
        end

        it "matches multiple users against multiple phone numbers" do
          expect(User.search_by_name_or_phone("Priya Sri" + " " + user_1.phone_number))
            .to match_array([user_1, user_2])

          expect(User.search_by_name_or_phone(user_1.phone_number + " " + user_2.phone_number))
            .to match_array([user_1, user_2])
        end
      end
    end

    describe ".search_by_name_or_email" do
      include_examples "full_name search", :search_by_name_or_email

      context "searches against email" do
        let!(:admin_1) { create(:admin, full_name: "Sri Priyanka John") }
        let!(:admin_2) { create(:admin, full_name: "Priya Sri Gupta") }

        it "matches an admin with an email" do
          expect(User.search_by_name_or_email(admin_1.email)).to match_array(admin_1)
        end

        it "returns nothing for combinations that don't match" do
          expect(User.search_by_name_or_email(admin_1.email + admin_2.email))
            .to be_empty

          expect(User.search_by_name_or_email(""))
            .to be_empty
        end

        it "matches a combination of name and email from the same admin" do
          expect(User.search_by_name_or_email(admin_1.email + " " + "John"))
            .to match_array(admin_1)

          expect(User.search_by_name_or_email("Gupta" + " " + admin_2.email))
            .to match_array(admin_2)
        end

        it "matches multiple users against multiple emails" do
          expect(User.search_by_name_or_email("Priya Sri" + " " + admin_1.email))
            .to match_array([admin_1, admin_2])

          expect(User.search_by_name_or_email(admin_1.email + " " + admin_2.email))
            .to match_array([admin_1, admin_2])
        end
      end
    end
  end
end
