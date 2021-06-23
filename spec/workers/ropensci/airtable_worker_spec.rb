require_relative "../../spec_helper.rb"

describe Ropensci::AirtableWorker do

  let(:response_200) { OpenStruct.new(status: 200, body: "Tests suite OK, build passed") }
  let(:response_200_template) { OpenStruct.new(status: 200, body: '{"result":"passed"}') }
  let(:response_400) { OpenStruct.new(status: 400, body: "error") }

  describe "perform" do
    before do
      @config = {}
      @locals = { 'bot_name' => 'ropensci-review-bot', 'issue_id' => 33, 'repo' => 'ropensci/tests', 'sender' => 'editor1' }
      @worker = described_class.new
      disable_github_calls_for(@worker)
    end

    it "should run assign_reviewer action" do
      expect(@worker).to receive(:assign_reviewer)
      @worker.perform(:assign_reviewer, @config, @locals, {})
    end
  end
end