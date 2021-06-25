require_relative "../../spec_helper.rb"

describe Ropensci::AirtableWorker do

  describe "perform" do
    before do
      @config = {}
      @locals = { "bot_name" => "ropensci-review-bot", "issue_id" => 33, "repo" => "ropensci/tests", "sender" => "editor1" }
      @worker = described_class.new
      disable_github_calls_for(@worker)
    end

    it "should run assign_reviewer action" do
      expect(@worker).to receive(:assign_reviewer)
      @worker.perform(:assign_reviewer, @config, @locals, {})
    end

    it "should run remove_reviewer action" do
      expect(@worker).to receive(:remove_reviewer)
      @worker.perform(:remove_reviewer, @config, @locals, {})
    end

    it "should load airtable config and params" do
      @worker.perform(:action, @config, @locals, {})
      expect(@worker.airtable_config[:api_key]).to eq("ropensci_airtable_api_key_abcde")
      expect(@worker.airtable_config[:base_id]).to eq("ropensci_airtable_base_id_12345")
    end

    it "should load params" do
      @worker.perform(:action, @config, @locals, { reviewer: "tester", package_name: "A" })
      expect(@worker.params.reviewer).to eq("tester")
      expect(@worker.params.package_name).to eq("A")
    end
  end

  describe "#assign_reviewer" do
    before do
      @worker = described_class.new
      @worker.context = OpenStruct.new({repo: "testing/new_package", issue_id: "33"})
      @worker.params = OpenStruct.new({ reviewer: "@reviewer21", package_name: "TestPackage"})
      @worker.airtable_config = {api_key: "ABC", base_id: "123"}
      disable_github_calls_for(@worker)
    end

    it "should clean reviewer github user" do
      expect(Octokit).to receive(:user).with("reviewer21")
      @worker.assign_reviewer
    end

    it "should respond to GitHub if user is invalid" do
      expect(Octokit).to receive(:user).with("reviewer21").and_raise(Octokit::NotFound)
      expect(@worker).to receive(:respond).with("I could not find user @reviewer21")

      @worker.assign_reviewer
    end

    describe "connects with Airtable" do
      let(:reviewer_in_airtable) { OpenStruct.new({current_assignment: "", id: 111, save: true}) }
      let(:reviewers_table) { double(all: [reviewer_in_airtable], create: [reviewer_in_airtable]) }
      let(:reviews_table) { double(create: true) }

      before do
        reviewer = OpenStruct.new({ login: "reviewer21", name: "Rev Iewer", email: "rev@iwe.rs" })
        expect(Octokit).to receive(:user).with("reviewer21").and_return(reviewer)
        expect(Airrecord).to receive(:table).once.with("ABC", "123", "reviewers-prod").and_return(reviewers_table)
        expect(Airrecord).to receive(:table).once.with("ABC", "123", "reviews").and_return(reviews_table)
      end

      it "should retrieve user from reviewers table" do
        expect(reviewers_table).to receive(:all).and_return([reviewer_in_airtable])
        expect(reviewers_table).to_not receive(:create)

        @worker.assign_reviewer
      end

      it "should create user in reviewers table if not present" do
        expect(reviewers_table).to receive(:all).and_return([])
        expect(reviewers_table).to receive(:create).with(github: "reviewer21", name: "Rev Iewer", email: "rev@iwe.rs").and_return(reviewer_in_airtable)

        @worker.assign_reviewer
      end

      it "should update reviewer current assignment" do
        expect(reviewer_in_airtable.current_assignment).to eq("")
        @worker.assign_reviewer
        expect(reviewer_in_airtable.current_assignment).to eq("https://github.com/testing/new_package/33")
      end

      it "should create entry in the reviews table" do
        expect(reviews_table).to receive(:create).with(id_no: "33",
                                                       github: [111],
                                                       onboarding_url: "https://github.com/testing/new_package/33",
                                                       package: "TestPackage")

        @worker.assign_reviewer
      end

      it "should respond to GitHub with form link" do
        expected_response = "@reviewer21: If you haven't done so, please fill [this form](https://airtable.com/shrnfDI2S9uuyxtDw) for us to update our reviewers records."
        expect(@worker).to receive(:respond).with(expected_response)

        @worker.assign_reviewer
      end
    end
  end

  describe "#remove_reviewer" do
    before do
      @worker = described_class.new
      @worker.context = OpenStruct.new({repo: "testing/new_package", issue_id: "33"})
      @worker.params = OpenStruct.new({ reviewer: "@reviewer21", package_name: "TestPackage"})
      @worker.airtable_config = {api_key: "ABC", base_id: "123"}
      disable_github_calls_for(@worker)
    end

    describe "connects with Airtable" do
      let(:reviewer_entry) { OpenStruct.new({current_assignment: "http://current.url", id: 111, save: true}) }
      let(:review_entry) { OpenStruct.new({destroy: true}) }
      let(:reviewers_table) { double(all: [reviewer_entry]) }
      let(:reviews_table) { double(all: [review_entry]) }

      before do
        expect(Airrecord).to receive(:table).once.with("ABC", "123", "reviewers-prod").and_return(reviewers_table)
        expect(Airrecord).to receive(:table).once.with("ABC", "123", "reviews").and_return(reviews_table)
      end

      it "should update current assignment in reviewers table" do
        expect(reviewers_table).to receive(:all).and_return([reviewer_entry])
        expect(reviewer_entry).to receive(:save)
        @worker.remove_reviewer
        expect(reviewer_entry.current_assignment).to eq("")
      end

      it "should not update current assignment i user is not in the reviewers table" do
        expect(reviewers_table).to receive(:all).and_return([])
        expect(reviewer_entry).to_not receive(:save)
        @worker.remove_reviewer
      end

      it "should delete entry in the reviews table" do
        expect(reviews_table).to receive(:all).and_return([review_entry])
        expect(review_entry).to receive(:destroy)

        @worker.remove_reviewer
      end

      it "should not delete entry in the reviews table if is not present" do
        expect(reviews_table).to receive(:all).and_return([])
        expect(review_entry).to_not receive(:destroy)

        @worker.remove_reviewer
      end
    end
  end
end